import 'package:Bloomee/utils/friendly_error.dart';
import 'package:flutter/material.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/routes/app_router.dart';
import 'package:Bloomee/services/downloaded_playlists.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:Bloomee/blocs/library/cubit/library_items_cubit.dart';
import 'package:Bloomee/services/plugin/plugin_service.dart';
import 'package:Bloomee/services/download/rust_download_service.dart';
import 'package:Bloomee/src/rust/api/downloader/types.dart';
import 'package:Bloomee/utils/download_types.dart';
import 'package:path/path.dart' as path;
import 'package:Bloomee/blocs/internet_connectivity/cubit/connectivity_cubit.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/core/constants/setting_keys.dart';
import 'package:Bloomee/repository/bloomee/download_repository.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/services/db/global_db.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/plugins/utils/media_id.dart';
import 'package:Bloomee/services/download_crypto.dart';
import 'package:Bloomee/services/meta_resolver/smart_track_replacement_service.dart';
import 'package:Bloomee/services/player/fallback_source.dart';
import 'package:Bloomee/services/player/stream_swaps.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:async/async.dart';

part 'downloader_state.dart';

class DownloaderCubit extends Cubit<DownloaderState> {
  final ConnectivityCubit connectivityCubit;
  final LibraryItemsCubit libraryItemsCubit;
  final DownloadRepository _downloadRepo;
  final SettingsDAO _settingsDao;
  final PluginService _pluginService;
  final RustDownloadService _downloadService = RustDownloadService();
  Future<void>? _serviceInitialization;
  final List<DownloadProgress> _activeDownloads = [];
  StreamSubscription? _librarySubscription;
  Timer? _libraryRefreshDebounce;
  StreamSubscription<DownloadManagerEvent>? _downloadSubscription;
  List<Track> _downloadedSongs = [];
  final Set<String> _persistingTaskIds = <String>{};
  bool _restoredSnapshots = false;
  Future<void>? _activeLoadFuture;

  /// False until the downloaded songs have been read once (with hundreds of
  /// files on an SD card this takes a while; Offline shows a spinner).
  bool get initialLoadDone => _initialLoadCompleter.isCompleted;
  bool _needsReload = false;
  // Tracks completion of initial downloaded songs load (prevents playback race)
  final CancelableCompleter<void> _initialLoadCompleter =
      CancelableCompleter<void>();

  DownloaderCubit({
    required this.connectivityCubit,
    required this.libraryItemsCubit,
    required DownloadRepository downloadRepo,
    required SettingsDAO settingsDao,
    required PluginService pluginService,
  })  : _downloadRepo = downloadRepo,
        _settingsDao = settingsDao,
        _pluginService = pluginService,
        super(DownloaderInitial()) {
    _setupLibrarySubscription();
    _loadDownloadedSongs();
    unawaited(_downloadRepo
        .encryptExistingDownloads()
        .then((_) => _loadDownloadedSongs()));
    unawaited(_warmUpDownloadService());
    unawaited(_watchNetwork());
    // A song added to a playlist that was downloaded with "Download all".
    DownloadedPlaylists.autoDownload =
        (title, track) => unawaited(downloadSong(track, showSnackbar: false));
  }

  // ── Playlist downloads ("Download all") ───────────────────────────────────

  final Map<String, PlaylistDownloadBatch> _batches = {};

  /// The playlist downloads in progress, for the progress notification.
  Iterable<PlaylistDownloadBatch> get playlistBatches => _batches.values;

  PlaylistDownloadBatch? _batchOf(String trackId) => _batches.values
      .where((b) =>
          b.ids.contains(trackId) &&
          !b.done.contains(trackId) &&
          !b.failed.contains(trackId))
      .firstOrNull;

  /// Downloads [songs] of playlist [title] as one batch: no message per
  /// song; one at the end ("X downloaded" or "N downloaded, M failed"), and
  /// the failed ones are kept so the playlist can offer Retry.
  Future<void> downloadPlaylist(String title, List<Track> songs) async {
    if (songs.isEmpty) return;
    final batch = PlaylistDownloadBatch(title, {for (final t in songs) t.id});
    _batches[title] = batch;
    await DownloadedPlaylists.setFailed(title, const []);
    onDownloadsChanged?.call();
    for (final song in songs) {
      var queued = false;
      try {
        queued = await downloadSong(song, showSnackbar: false);
      } catch (_) {}
      if (!queued) _settle(song.id, ok: false);
    }
  }

  /// Tries the failed songs of playlist [title] again; each one also gets
  /// another source if its own fails again.
  Future<void> retryPlaylist(String title, List<Track> playlistTracks) async {
    final failed = (await DownloadedPlaylists.loadFailed())[title] ?? const [];
    final ids = failed.toSet();
    _fallbackTried.removeAll(ids);
    await downloadPlaylist(
        title, [for (final t in playlistTracks) if (ids.contains(t.id)) t]);
  }

  /// A song reached its end state. Returns true when it belongs to a
  /// playlist batch (then the per-song message is left out).
  bool _settle(String trackId, {required bool ok}) {
    final batch = _batchOf(trackId);
    if (batch == null) return false;
    (ok ? batch.done : batch.failed).add(trackId);
    if (ok) batch.lastDone = DateTime.now();
    if (batch.finished) unawaited(_finishBatch(batch));
    onDownloadsChanged?.call();
    return true;
  }

  Future<void> _finishBatch(PlaylistDownloadBatch batch) async {
    _batches.remove(batch.title);
    await DownloadedPlaylists.setFailed(batch.title, batch.failed.toList());
    onPlaylistFinished?.call(batch);
    final context = GlobalRoutes.globalRouterKey.currentContext;
    if (context == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final ok = batch.failed.isEmpty;
    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Default_Theme.themeColor,
        icon: Icon(
            ok ? Icons.download_done_rounded : Icons.error_outline_rounded,
            color: ok ? Default_Theme.accentColor2 : Colors.amber,
            size: 34),
        title: Text(
          ok
              ? l10n.playlistDownloadDone(batch.title)
              : l10n.playlistDownloadPartial(
                  batch.done.length, batch.failed.length),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: ok
            ? null
            : Text(l10n.playlistDownloadFailedBanner(batch.failed.length),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(
                    color: Default_Theme.accentColor2,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ));
  }

  /// Hooks for the download notification (see download_notifier.dart).
  static VoidCallback? onDownloadsChanged;
  static void Function(PlaylistDownloadBatch batch)? onPlaylistFinished;

  // ── Download over Wi-Fi / mobile data ─────────────────────────────────────

  bool _wifiOnly = false;
  bool _onWifi = true;
  final Set<String> _pausedForWifi = {};
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  /// The user chose "Download over: Wi-Fi".
  bool get downloadOverWifiOnly => _wifiOnly;

  /// [taskId] is paused only because there is no Wi-Fi right now.
  bool isWaitingForWifi(String taskId) => _pausedForWifi.contains(taskId);

  static bool _isWifi(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.wifi) ||
      r.contains(ConnectivityResult.ethernet);

  Future<void> _watchNetwork() async {
    try {
      _wifiOnly =
          await _settingsDao.getSettingBool(SettingKeys.downloadWifiOnly) ??
              false;
      _onWifi = _isWifi(await Connectivity().checkConnectivity());
    } catch (e) {
      log('Network check failed: $e', name: 'DownloaderCubit');
    }
    _netSub = Connectivity().onConnectivityChanged.listen((r) {
      _onWifi = _isWifi(r);
      unawaited(_applyNetworkRule());
    });
  }

  /// "Download over": Wi-Fi only (true) or also mobile data (false).
  Future<void> setDownloadOverWifiOnly(bool wifiOnly) async {
    _wifiOnly = wifiOnly;
    await _settingsDao.putSettingBool(SettingKeys.downloadWifiOnly, wifiOnly);
    await _applyNetworkRule();
  }

  bool get _mustWaitForWifi => _wifiOnly && !_onWifi;

  static const _waitingForWifiText =
      'Waiting for Wi-Fi: downloads continue when you are on Wi-Fi';

  /// On mobile data with "Wi-Fi" chosen: pause what is running and remember
  /// it; back on Wi-Fi (or the setting changed): resume exactly those.
  Future<void> _applyNetworkRule() async {
    if (_mustWaitForWifi) {
      for (final d in List.of(_activeDownloads)) {
        if (_running.contains(d.status.state)) await _holdForWifi(d.task.taskId);
      }
    } else if (_pausedForWifi.isNotEmpty) {
      final ids = List.of(_pausedForWifi);
      _pausedForWifi.clear();
      for (final id in ids) {
        await resumeDownload(id);
      }
      _emitUpdatedState();
    }
  }

  Future<void> _holdForWifi(String taskId) async {
    if (!_pausedForWifi.add(taskId)) return;
    await pauseDownload(taskId);
    _emitUpdatedState();
  }

  /// Waits for initial downloaded songs to be loaded from database.
  /// Call this before using [isDownloaded] on first app startup to prevent
  /// race conditions on Android where playback might start before DB load completes.
  Future<void> ensureDownloadsInitialized() async {
    try {
      await _initialLoadCompleter.operation.value;
    } catch (_) {
      // Ignore cancellation; initialization will proceed normally
    }
  }

  Future<void> _warmUpDownloadService() async {
    try {
      await _ensureDownloadServiceReady();
    } catch (error, stackTrace) {
      log(
        'Failed to initialize Rust download service',
        name: 'DownloaderCubit',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _ensureDownloadServiceReady() {
    if (_downloadService.isInitialized && _downloadSubscription != null) {
      return Future.value();
    }

    final inFlight = _serviceInitialization;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _initializeDownloadService();
    _serviceInitialization = future.whenComplete(() {
      if (!_downloadService.isInitialized || _downloadSubscription == null) {
        _serviceInitialization = null;
      }
    });
    return _serviceInitialization!;
  }

  /// The folder chosen in Download settings (on Android: phone storage or
  /// SD card). Falls back to the default when it can't be used, e.g. the SD
  /// card was taken out.
  Future<Directory> _getDownloadDirectory() async {
    final fallback = Platform.isAndroid || Platform.isIOS
        ? (await getDownloadsDirectory()) ??
            await getApplicationDocumentsDirectory()
        : await getApplicationDocumentsDirectory();
    // iOS moves the app's folders between installs, so a saved path goes stale.
    if (Platform.isIOS) return fallback;
    final p = await _settingsDao.getSettingStr(SettingKeys.downPathSetting);
    if (p == null || p.isEmpty) return fallback;
    try {
      return await Directory(p).create(recursive: true);
    } catch (e) {
      log('Download folder $p unavailable, using ${fallback.path}: $e',
          name: 'DownloaderCubit');
      return fallback;
    }
  }

  void _setupLibrarySubscription() {
    _librarySubscription = libraryItemsCubit.stream.listen((_) {
      _libraryRefreshDebounce?.cancel();
      _libraryRefreshDebounce = Timer(const Duration(milliseconds: 600), () {
        if (!isClosed) {
          _loadDownloadedSongs();
        }
      });
    });
  }

  Future<void> _loadDownloadedSongs() {
    if (_activeLoadFuture != null) {
      _needsReload = true;
      return _activeLoadFuture!;
    }

    final completer = Completer<void>();
    _activeLoadFuture = completer.future;
    _needsReload = false;

    _executeLoad(completer);

    return completer.future;
  }

  Future<void> _executeLoad(Completer<void> completer) async {
    try {
      _downloadedSongs = await _downloadRepo.getDownloadedTracks();
      _emitUpdatedState();
      // Signal that initial load is complete
      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }
      completer.complete();
    } catch (error, stackTrace) {
      // Even on error, mark as attempted to avoid hanging
      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.completeError(error, stackTrace);
      }
      completer.completeError(error, stackTrace);
    } finally {
      _activeLoadFuture = null;
      if (_needsReload) {
        unawaited(_loadDownloadedSongs());
      }
    }
  }

  void _emitUpdatedState() {
    emit(DownloaderTasksUpdated(
      List.from(_activeDownloads),
      List.from(_downloadedSongs),
    ));
  }

  /// Public method to refresh downloaded songs
  Future<void> refreshDownloadedSongs() async {
    await _loadDownloadedSongs();
  }

  Future<void> _initializeDownloadService() async {
    await _pluginService.initialize();

    final supportDirectory = await getApplicationSupportDirectory();
    final tempDirectory = await getTemporaryDirectory();
    await _downloadService.initialize(
      pluginManager: _pluginService.manager,
      stateDir: path.join(supportDirectory.path, 'download_manager'),
      tempDir: path.join(tempDirectory.path, 'bloomee_downloads'),
    );

    _downloadSubscription ??= _downloadService.events.listen(
      _handleDownloadEvent,
      onError: (Object error, StackTrace stackTrace) {
        log(
          'Rust download event stream failed',
          name: 'DownloaderCubit',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );

    if (_restoredSnapshots) {
      return;
    }

    final snapshots = await _downloadService.restoreTasks();
    _restoredSnapshots = true;
    if (snapshots.isNotEmpty) {
      for (final snapshot in snapshots) {
        _upsertSnapshot(snapshot, emitState: false);
      }
      _emitUpdatedState();
    }
  }

  void _handleDownloadEvent(DownloadManagerEvent event) {
    event.map(
      taskUpdated: (value) {
        final snapshot = value.field0;
        _upsertSnapshot(snapshot);
        // Started (or resumed) on mobile data while "Wi-Fi" is chosen.
        if (_mustWaitForWifi &&
            const {
              DownloadTaskState.queued,
              DownloadTaskState.resolving,
              DownloadTaskState.downloading,
              DownloadTaskState.retrying,
            }.contains(snapshot.state)) {
          unawaited(_holdForWifi(snapshot.taskId));
        }
        if (snapshot.state == DownloadTaskState.failed &&
            !_downloadFromOtherSource(snapshot)) {
          // No other source left: the song (the one asked for, if this was
          // its other-source copy) has failed.
          final asked = _fallbackFor.remove(snapshot.track.id) ?? snapshot.track;
          if (!_settle(asked.id, ok: false)) {
            SnackbarService.showMessage(
              snapshot.lastError ?? 'Failed to download ${snapshot.track.title}',
            );
          }
        }
        onDownloadsChanged?.call();
      },
      taskCompletedPendingAck: (value) {
        final snapshot = value.field0;
        _upsertSnapshot(snapshot);
        unawaited(_persistCompletedSnapshot(snapshot));
      },
      taskRemoved: (value) {
        _activeDownloads.removeWhere(
          (item) => item.task.taskId == value.taskId,
        );
        _emitUpdatedState();
      },
      recoverySummary: (value) {
        if (value.restored > 0) {
          SnackbarService.showMessage(
            'Restored ${value.restored} download${value.restored == 1 ? '' : 's'} after restart',
          );
        }
      },
    );
  }

  static final _downloaded = StreamController<Track>.broadcast();

  /// Songs as their download is saved (e.g. to fetch their lyrics for
  /// offline use).
  static Stream<Track> get downloadedTracks => _downloaded.stream;

  /// The song asked for, by the id of the other-source copy downloaded for it.
  final Map<String, Track> _fallbackFor = {};
  final Set<String> _fallbackTried = {};

  /// When [failed] can't be downloaded from its own source (YouTube now
  /// blocks some songs), downloads the same song from another source
  /// instead, once per song. Returns false when it won't try.
  bool _downloadFromOtherSource(DownloadTaskSnapshot failed) {
    final original = failed.track;
    if (isLocalMediaId(original.id) ||
        _fallbackFor.containsKey(original.id) ||
        !_fallbackTried.add(original.id)) {
      return false;
    }
    unawaited(() async {
      try {
        Track? other = await StreamSwaps.lookup(original);
        if (other == null) {
          final pick = await pickFallback(
              SmartTrackReplacementService.create(_pluginService), original);
          other = pick?.track;
        }
        if (other == null) {
          // Nothing found (e.g. right after start, before the plugins have
          // loaded): let the next retry look again.
          _fallbackTried.remove(original.id);
          if (!_settle(original.id, ok: false)) {
            SnackbarService.showMessage(
                failed.lastError ?? 'Failed to download ${original.title}');
          }
          return;
        }
        _fallbackFor[other.id] = original;
        await cancelDownload(failed.taskId);
        if (_batchOf(original.id) == null) {
          SnackbarService.showMessage(
              'Downloading ${original.title} from another source');
        }
        await downloadSong(other, showSnackbar: false);
      } catch (e, s) {
        _fallbackTried.remove(original.id);
        log('Download fallback failed',
            name: 'DownloaderCubit', error: e, stackTrace: s);
        if (!_settle(original.id, ok: false)) {
          SnackbarService.showMessage(
              failed.lastError ?? 'Failed to download ${original.title}');
        }
      }
    }());
    return true;
  }

  Future<void> _persistCompletedSnapshot(DownloadTaskSnapshot snapshot) async {
    if (!_persistingTaskIds.add(snapshot.taskId)) {
      return;
    }
    final original = _fallbackFor.remove(snapshot.track.id);
    if (original != null) {
      unawaited(StreamSwaps.remember(original, snapshot.track));
    }

    try {
      final filePath = snapshot.targetPath;
      if (filePath.isEmpty) {
        throw StateError('Completed download has no target path');
      }

      final fileName = snapshot.fileName.isNotEmpty
          ? snapshot.fileName
          : path.basename(filePath);
      final downloadDirectory = path.dirname(filePath);

      await _downloadRepo.saveDownload(
        fileName: fileName,
        filePath: downloadDirectory,
        lastDownloaded: DateTime.now(),
        // A copy from another source is saved as the song that was asked
        // for, so its playlist and playback see it as downloaded.
        track: original ?? snapshot.track,
      );
      await _downloadService.acknowledgePersisted(snapshot.taskId);
      if (DownloadCrypto.supported) {
        // After the record is saved, so a failure leaves a playable plain
        // file that encryptExistingDownloads picks up on the next start.
        try {
          await _downloadRepo.encryptDownload(
              (original ?? snapshot.track).id, filePath);
        } catch (e) {
          log('Could not encrypt ${snapshot.track.title}: $e',
              name: 'DownloaderCubit');
        }
      }
      if (!_settle((original ?? snapshot.track).id, ok: true)) {
        SnackbarService.showMessage('Downloaded ${snapshot.track.title}');
      }
      _downloaded.add(original ?? snapshot.track);
      await _loadDownloadedSongs();
    } catch (error, stackTrace) {
      log(
        'Failed to persist completed download ${snapshot.taskId}',
        name: 'DownloaderCubit',
        error: error,
        stackTrace: stackTrace,
      );
      SnackbarService.showMessage(
        'Downloaded file is ready, but saving it to the library failed.',
      );
    } finally {
      _persistingTaskIds.remove(snapshot.taskId);
    }
  }

  void _upsertSnapshot(
    DownloadTaskSnapshot snapshot, {
    bool emitState = true,
  }) {
    final progress = _progressFromSnapshot(snapshot);
    final index = _activeDownloads.indexWhere(
      (item) => item.task.taskId == snapshot.taskId,
    );

    if (index == -1) {
      _activeDownloads.insert(0, progress);
    } else {
      _activeDownloads[index] = progress;
    }

    if (emitState) {
      _emitUpdatedState();
    }
  }

  DownloadProgress _progressFromSnapshot(DownloadTaskSnapshot snapshot) {
    final filePath = snapshot.targetPath.isNotEmpty
        ? snapshot.targetPath
        : snapshot.tempPath;

    final downloadTask = DownloadTask(
      taskId: snapshot.taskId,
      song: snapshot.track,
      mediaId: snapshot.track.id,
      fileName: snapshot.fileName.isNotEmpty
          ? snapshot.fileName
          : path.basename(filePath),
      targetPath: snapshot.targetPath,
    );

    return DownloadProgress(
      task: downloadTask,
      status: DownloadStatus(
        state: _mapDownloadState(snapshot.state),
        progress: snapshot.progress.clamp(0.0, 1.0),
        // A failed task can carry a raw engine error; show plain words.
        message: snapshot.state == DownloadTaskState.failed
            ? friendlyError(snapshot.message,
                fallback: 'Download failed. Try again.')
            : snapshot.message,
        filePath: snapshot.targetPath.isNotEmpty ? snapshot.targetPath : null,
      ),
    );
  }

  DownloadState _mapDownloadState(DownloadTaskState state) {
    switch (state) {
      case DownloadTaskState.queued:
        return DownloadState.queued;
      case DownloadTaskState.resolving:
        return DownloadState.resolving;
      case DownloadTaskState.downloading:
        return DownloadState.downloading;
      case DownloadTaskState.paused:
        return DownloadState.paused;
      case DownloadTaskState.retrying:
        return DownloadState.retrying;
      case DownloadTaskState.writingMetadata:
        return DownloadState.fetchingMetadata;
      case DownloadTaskState.completedPendingAck:
        return DownloadState.completed;
      case DownloadTaskState.failed:
        return DownloadState.failed;
      case DownloadTaskState.cancelled:
        return DownloadState.cancelled;
    }
  }

  DownloadProgress? _findDownloadByMediaId(String mediaId) {
    try {
      return _activeDownloads
          .firstWhere((item) => item.task.mediaId == mediaId);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isAlreadyDownloaded(Track song) async {
    final dbRecord = await _downloadRepo.getDownload(song.id);
    if (dbRecord != null) {
      final file = File(path.join(dbRecord.filePath, dbRecord.fileName));
      if (await file.exists()) {
        log("${song.title} is already downloaded and file exists.",
            name: "DownloaderCubit");
        return true;
      } else {
        log("Stale DB record found for ${song.title}. Removing.",
            name: "DownloaderCubit");
        await _downloadRepo.removeDownload(song.id);
        return false;
      }
    }
    return false;
  }

  /// The main public method to initiate a new download.
  /// Returns true when the song is queued (or was already queued/resumed).
  Future<bool> downloadSong(Track song, {bool showSnackbar = true}) async {
    try {
      await _ensureDownloadServiceReady();
    } catch (error, stackTrace) {
      log(
        'Failed to prepare download service for ${song.title}',
        name: 'DownloaderCubit',
        error: error,
        stackTrace: stackTrace,
      );
      if (showSnackbar) {
        SnackbarService.showMessage('Error: Download service is unavailable.');
      }
      return false;
    }

    if (connectivityCubit.state != ConnectivityState.connected) {
      if (showSnackbar) SnackbarService.showMessage("No internet connection.");
      return false;
    }

    // Pre-download checks
    final existingDownload = _findDownloadByMediaId(song.id);
    if (existingDownload != null) {
      if (existingDownload.status.state == DownloadState.paused ||
          existingDownload.status.state == DownloadState.failed) {
        await resumeDownload(existingDownload.task.taskId);
        if (showSnackbar) {
          SnackbarService.showMessage('Resuming ${song.title}...');
        }
      } else if (showSnackbar) {
        SnackbarService.showMessage('${song.title} is already in the queue.');
      }
      return true;
    }

    if (await _isAlreadyDownloaded(song)) {
      if (showSnackbar) {
        SnackbarService.showMessage("${song.title} is already downloaded.");
      }
      _settle(song.id, ok: true); // counts as done in a playlist batch
      return true;
    }

    final directory = await _getDownloadDirectory();

    if (showSnackbar) {
      SnackbarService.showMessage("Preparing download for ${song.title}...");
    }

    try {
      final storedQuality = await _settingsDao.getSettingStr(
        SettingKeys.downQuality,
        defaultValue: 'Medium',
      );
      await _downloadService.enqueue(
        request: EnqueueDownloadRequest(
          track: song,
          downloadDir: directory.path,
          preferredQuality: storedQuality ?? 'Medium',
        ),
      );

      if (showSnackbar) {
        SnackbarService.showMessage('Added ${song.title} to download queue');
      }
      return true;
    } catch (e, stackTrace) {
      log(
        'Failed to queue download for ${song.title}',
        name: 'DownloaderCubit',
        error: e,
        stackTrace: stackTrace,
      );

      if (showSnackbar) {
        SnackbarService.showMessage('Error: Could not start download.');
      }
      return false;
    }
  }

  Future<void> pauseDownload(String taskId) async {
    await _ensureDownloadServiceReady();
    await _downloadService.pause(taskId);
  }

  Future<void> resumeDownload(String taskId) async {
    if (_mustWaitForWifi) {
      SnackbarService.showMessage(_waitingForWifiText);
      return;
    }
    await _ensureDownloadServiceReady();
    await _downloadService.resume(taskId);
  }

  static const _running = {
    DownloadState.downloading,
    DownloadState.resolving,
    DownloadState.fetchingMetadata,
    DownloadState.retrying,
    DownloadState.queued,
  };

  /// Some download is running or waiting its turn.
  bool get anyRunning =>
      _activeDownloads.any((d) => _running.contains(d.status.state));

  /// Pauses every running or queued download (Offline's "Pause all").
  Future<void> pauseAll() async {
    for (final d in List.of(_activeDownloads)) {
      if (_running.contains(d.status.state)) {
        await pauseDownload(d.task.taskId);
      }
    }
  }

  /// Resumes every paused download.
  Future<void> resumeAll() async {
    if (_mustWaitForWifi) return; // they would only pause again
    _pausedForWifi.clear();
    for (final d in List.of(_activeDownloads)) {
      if (d.status.state == DownloadState.paused) {
        await resumeDownload(d.task.taskId);
      }
    }
  }

  Future<void> cancelDownload(String taskId) async {
    await _ensureDownloadServiceReady();
    await _downloadService.cancel(taskId);
  }

  @override
  Future<void> close() async {
    _libraryRefreshDebounce?.cancel();
    await _librarySubscription?.cancel();
    await _netSub?.cancel();
    await _downloadSubscription?.cancel();
    await _downloadService.dispose();
    await super.close();
  }

  /// Check whether a song is downloaded.
  bool isDownloaded(String mediaId) {
    return _downloadedSongs.any((s) => s.id == mediaId);
  }

  /// Get the download info for a song, if available.
  Future<DownloadDB?> getDownloadInfo(Track song) async {
    return _downloadRepo.getDownload(song.id);
  }

  /// Remove a downloaded song and its file.
  Future<void> removeDownload(Track song) async {
    await _downloadRepo.removeDownload(song.id);
    await _loadDownloadedSongs();
    SnackbarService.showMessage("${song.title} download removed");
  }
}

/// One playlist's "Download all": which songs finished or failed.
class PlaylistDownloadBatch {
  PlaylistDownloadBatch(this.title, this.ids);
  final String title;
  final Set<String> ids;
  final Set<String> done = {};
  final Set<String> failed = {};
  final DateTime started = DateTime.now();
  DateTime? lastDone;

  int get settled => done.length + failed.length;
  bool get finished => settled >= ids.length;

  /// Time left, from the pace of the songs done so far; null until one is.
  Duration? get eta {
    final last = lastDone;
    if (last == null || done.isEmpty) return null;
    final perSong = last.difference(started) ~/ done.length;
    return perSong * (ids.length - settled);
  }
}
