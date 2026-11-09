// Download progress in the notification panel (Android). One notification
// per playlist being downloaded with "Download all" ("Downloading Sune hue
// gaane · 12 of 26 · about 4 min left") and one for songs downloaded one by
// one; each shows the song's cover and turns into a "downloaded" notice at
// the end. Drawn natively by DownloadNotifications.kt.

import 'dart:async';
import 'dart:io';

import 'package:Bloomee/blocs/downloader/cubit/downloader_cubit.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/utils/download_types.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadNotifier {
  DownloadNotifier._(this._cubit);

  static const _channel = MethodChannel('jarx/downloads');
  static const _singlesId = 4100;
  static DownloadNotifier? _instance;

  final DownloaderCubit _cubit;
  Timer? _throttle;
  bool _singlesShown = false;
  final Set<int> _batchIds = {};

  /// Starts showing download progress for [cubit]'s downloads.
  static void attach(DownloaderCubit cubit) {
    if (!Platform.isAndroid || _instance != null) return;
    final n = _instance = DownloadNotifier._(cubit);
    cubit.stream.listen((_) {
      if (cubit.state.downloads.isNotEmpty) unawaited(_askOnce());
      n._schedule();
    });
    DownloaderCubit.onDownloadsChanged = n._schedule;
    DownloaderCubit.onPlaylistFinished = n._finished;
    DownloaderCubit.downloadedTracks.listen(n._songDone);
  }

  /// Android 13+ needs permission for this notification: asked once, the
  /// first time something downloads (never again if the user says no).
  static Future<void> _askOnce() async {
    if (_asked) return;
    _asked = true;
    try {
      final settings = SettingsDAO(DBProvider.db);
      if (await settings.getSettingBool(_askedKey) == true) return;
      await settings.putSettingBool(_askedKey, true);
      if (!await Permission.notification.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }

  static bool _asked = false;
  static const _askedKey = 'downloadNotificationPermissionAsked';

  static int _idFor(String playlist) =>
      4200 + (playlist.hashCode & 0x7fffffff) % 700;

  /// At most about one update a second (Android drops faster updates).
  void _schedule() {
    if (_throttle?.isActive ?? false) return;
    _throttle = Timer(const Duration(milliseconds: 900), () {
      unawaited(_update());
    });
  }

  static const _active = {
    DownloadState.downloading,
    DownloadState.resolving,
    DownloadState.fetchingMetadata,
    DownloadState.retrying,
    DownloadState.queued,
    DownloadState.paused,
  };

  Future<void> _update() async {
    final downloads = [
      for (final d in _cubit.state.downloads)
        if (_active.contains(d.status.state)) d
    ];
    final batches = _cubit.playlistBatches.toList();
    final inBatch = <String>{for (final b in batches) ...b.ids};

    // Playlists.
    for (final b in batches) {
      final id = _idFor(b.title);
      _batchIds.add(id);
      final current = downloads
          .where((d) =>
              b.ids.contains(d.task.song.id) &&
              d.status.state == DownloadState.downloading)
          .firstOrNull;
      final total = b.ids.length;
      final fraction =
          (b.settled + (current?.status.progress ?? 0).clamp(0.0, 1.0)) /
              total;
      final eta = b.eta;
      final waiting = current != null &&
          _cubit.isWaitingForWifi(current.task.taskId);
      await _show(
        id: id,
        title: 'Downloading ${b.title}',
        text: [
          '${b.done.length} of $total songs',
          if (waiting) 'waiting for Wi-Fi' else if (eta != null) _eta(eta),
        ].join(' · '),
        sub: current?.task.song.title,
        progress: (fraction * 1000).round(),
        max: 1000,
        cover: current?.task.song,
      );
    }

    // Songs downloaded one by one.
    final singles = [
      for (final d in downloads)
        if (!inBatch.contains(d.task.song.id)) d
    ];
    if (singles.isEmpty) {
      if (_singlesShown) {
        _singlesShown = false;
        await _channel.invokeMethod('cancel', {'id': _singlesId});
      }
      return;
    }
    _singlesShown = true;
    final first = singles.first;
    final waiting = _cubit.isWaitingForWifi(first.task.taskId);
    final pct = (first.status.progress.clamp(0.0, 1.0) * 100).round();
    await _show(
      id: _singlesId,
      title: singles.length == 1
          ? 'Downloading ${first.task.song.title}'
          : 'Downloading ${singles.length} songs',
      text: waiting
          ? 'Waiting for Wi-Fi'
          : singles.length == 1
              ? [
                  first.task.song.artists.map((a) => a.name).join(', '),
                  '$pct%',
                ].where((s) => s.isNotEmpty).join(' · ')
              : 'Now: ${first.task.song.title} · $pct%',
      progress: first.status.state == DownloadState.downloading ? pct : 0,
      max: first.status.state == DownloadState.downloading ? 100 : 0,
      cover: first.task.song,
    );
  }

  Future<void> _songDone(Track t) async {
    if (_cubit.playlistBatches.any((b) => b.ids.contains(t.id))) return;
    // Only when no other single is still going (that one keeps the slot).
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final stillGoing = _cubit.state.downloads.any((d) =>
        _active.contains(d.status.state) &&
        !_cubit.playlistBatches.any((b) => b.ids.contains(d.task.song.id)));
    if (stillGoing) return;
    _singlesShown = false;
    await _show(
      id: _singlesId,
      title: 'Downloaded ${t.title}',
      text: 'Ready to play offline',
      ongoing: false,
      done: true,
      cover: t,
      timeoutMs: 8000,
    );
  }

  Future<void> _finished(PlaylistDownloadBatch b) async {
    final ok = b.failed.isEmpty;
    await _show(
      id: _idFor(b.title),
      title: ok ? '${b.title} downloaded' : '${b.title}: ${b.done.length} downloaded',
      text: ok
          ? 'All ${b.done.length} songs are ready to play offline'
          : '${b.failed.length} failed · open the playlist to retry',
      ongoing: false,
      done: true,
    );
  }

  static String _eta(Duration d) {
    if (d.inMinutes >= 60) {
      return 'about ${d.inHours} h ${d.inMinutes % 60} min left';
    }
    if (d.inMinutes >= 1) return 'about ${d.inMinutes + 1} min left';
    return 'less than a minute left';
  }

  Future<void> _show({
    required int id,
    required String title,
    required String text,
    String? sub,
    int progress = 0,
    int max = 0,
    bool ongoing = true,
    bool done = false,
    Track? cover,
    int timeoutMs = 0,
  }) async {
    try {
      await _channel.invokeMethod('show', {
        'id': id,
        'title': title,
        'text': text,
        'sub': sub,
        'progress': progress,
        'max': max,
        'ongoing': ongoing,
        'done': done,
        'cover': cover == null ? null : await _coverFile(cover),
        'timeoutMs': timeoutMs,
      });
    } catch (_) {
      // A notification must never break downloading.
    }
  }

  static final Map<String, String?> _covers = {};

  /// A local file of [t]'s cover for the notification's picture.
  static Future<String?> _coverFile(Track t) async {
    final url = t.thumbnail.url;
    if (url.isEmpty) return null;
    if (!url.startsWith('http')) return File(url).existsSync() ? url : null;
    if (_covers.containsKey(url)) return _covers[url];
    try {
      final dir = Directory(p.join(
          (await getTemporaryDirectory()).path, 'download_notification_covers'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, '${url.hashCode & 0x7fffffff}.img'));
      if (!await file.exists()) {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
        try {
          final res = await (await client.getUrl(Uri.parse(url))).close();
          if (res.statusCode != 200) return _covers[url] = null;
          await res.pipe(file.openWrite());
        } finally {
          client.close();
        }
      }
      if (_covers.length > 200) _covers.clear();
      return _covers[url] = file.path;
    } catch (_) {
      return _covers[url] = null;
    }
  }
}
