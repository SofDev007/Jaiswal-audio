import 'dart:async';
import 'dart:developer';
import 'dart:math' show max, min, pow;

import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/plugins/blocs/import/content_import_state.dart';
import 'package:Bloomee/plugins/errors/plugin_exceptions.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/csv_playlist_parser.dart';
import 'package:Bloomee/services/plugin/plugin_service.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart';
import 'package:Bloomee/src/rust/api/plugin/types.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';

const int _kResolutionConcurrency = 5;
const double _kMinConfidence = 0.45;
const int _kMaxCandidatesPerTrack = 5;

// Step budgets. The host caps every plugin HTTP request at 30 s
// (rust/src/api/plugin/adapters/content_importer/mod.rs), so a step that makes
// one request gets a little more than that.
const Duration kImportCheckTimeout = Duration(seconds: 15);
const Duration kImportInfoTimeout = Duration(seconds: 45);

/// A call the app gave up on keeps running in Rust and holds that plugin's
/// lock until it finishes. The next call waits this long for it, then fails
/// as [ImportErrorKind.pluginBusy] instead of queueing silently.
const Duration kImportBusyWait = Duration(seconds: 40);

/// Tries per step, counting the first; only transient failures are retried.
const int kImportMaxAttempts = 3;

/// The plugin fetches every page of the collection inside one `getTracks`
/// call, so that call's budget grows with the collection: 45 s plus 15 s per
/// page of 50 tracks, capped at 10 minutes. An unknown size budgets for 1000.
// ponytail: a size-based ceiling, not stall detection. Detecting a stalled
// plugin needs the host to report its HTTP activity (Rust + bridge change).
Duration importTracksTimeout(int? trackCount) {
  final pages = max(1, ((trackCount ?? 1000) / 50).ceil());
  return Duration(seconds: min(600, 45 + 15 * pages));
}

/// Best-effort reading of a plugin failure. Importer plugins report errors as
/// free text, so this matches status codes and common phrases in it.
ImportErrorKind classifyImportError(Object error) {
  if (error is _PluginBusyException) return ImportErrorKind.pluginBusy;
  if (error is TimeoutException) return ImportErrorKind.timeout;
  if (error is PluginNotLoadedException || error is PluginNotFoundException) {
    return ImportErrorKind.pluginUnavailable;
  }
  final text =
      (error is PluginException ? error.message : '$error').toLowerCase();
  bool has(List<String> words) => words.any(text.contains);

  if (has(['429', 'rate limit', 'too many requests'])) {
    return ImportErrorKind.rateLimited;
  }
  if (has(['500', '502', '503', '504', 'bad gateway', 'service unavailable'])) {
    return ImportErrorKind.network;
  }
  if (has(['401', '403', 'unauthorized', 'forbidden', 'access denied'])) {
    return ImportErrorKind.authFailed;
  }
  if (has(['404', 'not found', 'private', 'does not exist', 'deleted'])) {
    return ImportErrorKind.notFound;
  }
  if (has([
    'timed out',
    'timeout',
    'error sending request',
    'connection',
    'dns',
    'network',
    'socket',
  ])) {
    return ImportErrorKind.network;
  }
  return ImportErrorKind.unknown;
}

class _PluginBusyException implements Exception {
  const _PluginBusyException();
}

class ContentImportCubit extends Cubit<ContentImportState> {
  final PluginService _pluginService;
  final CrossPluginResolver _resolver;
  final PlaylistDAO _playlistDao;

  /// Bumped by every new import, [cancel] and [reset]; work from an older run
  /// sees the change after its next await and stops without emitting.
  int _run = 0;

  /// Per plugin, the latest call's completion (never errors).
  final Map<String, Future<void>> _inFlight = {};

  ContentImportCubit({
    PluginService? pluginService,
    CrossPluginResolver? resolver,
    PlaylistDAO? playlistDao,
  })  : _pluginService = pluginService ?? ServiceLocator.pluginService,
        _resolver = resolver ??
            CrossPluginResolver(
              pluginService: pluginService ?? ServiceLocator.pluginService,
            ),
        _playlistDao = playlistDao ?? _defaultPlaylistDao(),
        super(const ContentImportState());

  static PlaylistDAO _defaultPlaylistDao() {
    final trackDao = TrackDAO(DBProvider.db);
    return PlaylistDAO(DBProvider.db, trackDao);
  }

  bool _stale(int run) => isClosed || run != _run;

  /// An import is running; starting another one is ignored.
  bool get isBusy => const {
        ImportPhase.checkingUrl,
        ImportPhase.fetchingInfo,
        ImportPhase.fetchingTracks,
        ImportPhase.resolving,
        ImportPhase.saving,
      }.contains(state.phase);

  // ── Steps 1–3: check the URL, fetch collection info, fetch tracks ────────

  Future<void> checkUrl(String pluginId, String url) async {
    if (isBusy) return;
    final run = ++_run;
    emit(ContentImportState(
      phase: ImportPhase.checkingUrl,
      pluginId: pluginId,
      url: url,
      phaseStartedAt: DateTime.now(),
    ));

    // The prefixes keep the raw messages the screen already localizes.
    var failurePrefix = 'Failed to check URL';
    try {
      final canHandle = await _callWithRetry(
        run,
        pluginId,
        ContentImporterCommand.canHandleUrl(url: url),
        kImportCheckTimeout,
      );
      if (_stale(run)) return;
      if (canHandle is! PluginResponse_CanHandle || !canHandle.field0) {
        return _fail(ImportErrorKind.unsupportedUrl,
            'This plugin cannot handle the provided URL.');
      }

      failurePrefix = 'Failed to fetch collection info';
      _enterStep(ImportPhase.fetchingInfo);
      final info = await _callWithRetry(
        run,
        pluginId,
        ContentImporterCommand.getCollectionInfo(url: url),
        kImportInfoTimeout,
      );
      if (_stale(run)) return;
      if (info is! PluginResponse_CollectionInfo) {
        return _fail(ImportErrorKind.unexpectedResponse,
            'Unexpected response when fetching collection info.');
      }

      failurePrefix = 'Failed to fetch tracks';
      _enterStep(ImportPhase.fetchingTracks, collectionInfo: info.field0);
      final tracks = await _callWithRetry(
        run,
        pluginId,
        ContentImporterCommand.getTracks(url: url),
        importTracksTimeout(info.field0.trackCount),
      );
      if (_stale(run)) return;
      if (tracks is! PluginResponse_ImportTracks) {
        return _fail(ImportErrorKind.unexpectedResponse,
            'Unexpected response when fetching tracks.');
      }
      if (tracks.field0.isEmpty) {
        return _fail(ImportErrorKind.emptyCollection, 'No tracks found.');
      }

      emit(state.copyWith(
        tracks: List.unmodifiable(
          tracks.field0.map((t) => ImportTrackEntry(sourceTrack: t)),
        ),
        phase: ImportPhase.resolving,
      ));
      await _resolveTracks(run);
    } catch (e) {
      if (_stale(run)) return;
      log('$failurePrefix: $e', name: 'ContentImportCubit');
      _fail(classifyImportError(e), '$failurePrefix: $e');
    }
  }

  void _enterStep(ImportPhase phase, {ImportCollectionSummary? collectionInfo}) {
    emit(state.copyWith(
      phase: phase,
      collectionInfo: collectionInfo,
      attempt: 1,
      phaseStartedAt: DateTime.now(),
    ));
  }

  void _fail(ImportErrorKind kind, String message) {
    emit(state.copyWith(
      phase: ImportPhase.error,
      errorKind: kind,
      error: message,
    ));
  }

  /// [_call], retried with backoff while the failure is transient.
  Future<PluginResponse> _callWithRetry(
    int run,
    String pluginId,
    ContentImporterCommand command,
    Duration timeout,
  ) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await _call(pluginId, command, timeout);
      } catch (e) {
        final kind = classifyImportError(e);
        if (!kind.isTransient || attempt >= kImportMaxAttempts || _stale(run)) {
          rethrow;
        }
        // Network: 2 s, then 6 s. Rate limit: 10 s, then 30 s.
        final base = kind == ImportErrorKind.rateLimited ? 10 : 2;
        final wait = Duration(seconds: base * pow(3, attempt - 1).toInt());
        log('Attempt $attempt failed ($kind), retrying in $wait: $e',
            name: 'ContentImportCubit');
        emit(state.copyWith(attempt: attempt + 1));
        await Future<void>.delayed(wait);
        if (_stale(run)) rethrow;
      }
    }
  }

  /// One importer call. Calls to a plugin never overlap: Rust runs one at a
  /// time per plugin, and a call the app stopped waiting for (timeout or
  /// cancel) still holds that slot until it finishes. Waiting for it here keeps
  /// the new call's [timeout] from being spent in that queue.
  Future<PluginResponse> _call(
    String pluginId,
    ContentImporterCommand command,
    Duration timeout,
  ) async {
    final previous = _inFlight[pluginId];
    if (previous != null) {
      try {
        await previous.timeout(kImportBusyWait);
      } on TimeoutException {
        throw const _PluginBusyException();
      }
    }

    final call = _pluginService.execute(
      pluginId: pluginId,
      request: PluginRequest.contentImporter(command),
    );
    final settled = call.then<void>((_) {}, onError: (_) {});
    _inFlight[pluginId] = settled;
    unawaited(settled.whenComplete(() {
      if (identical(_inFlight[pluginId], settled)) _inFlight.remove(pluginId);
    }));
    return call.timeout(timeout);
  }

  // ── Step 4: Resolve Tracks ───────────────────────────────────────────────

  /// Matches every entry that has no answer yet (pending, interrupted or
  /// errored); entries already matched or found unmatched are kept, so this
  /// also resumes an earlier run. Never throws: a failure becomes an error
  /// state that keeps the tracks for [retry].
  Future<void> _resolveTracks(int run) async {
    final List<String> resolverPluginIds;
    try {
      resolverPluginIds = await _getContentResolverPluginIds();
    } catch (e) {
      if (_stale(run)) return;
      log('Listing resolver plugins failed: $e', name: 'ContentImportCubit');
      return _fail(ImportErrorKind.matchingFailed, 'Matching failed: $e');
    }
    if (_stale(run)) return;
    if (resolverPluginIds.isEmpty) {
      log('No content-resolver plugins loaded.', name: 'ContentImportCubit');
      return _fail(ImportErrorKind.noResolvers, 'No resolver plugins loaded.');
    }

    final tracks = List<ImportTrackEntry>.from(state.tracks);
    final semaphore = Semaphore(_kResolutionConcurrency);
    final futures = <Future<void>>[];

    for (var i = 0; i < tracks.length; i++) {
      final index = i;
      final status = tracks[i].status;
      if (status == TrackResolutionStatus.resolved ||
          status == TrackResolutionStatus.failed) {
        continue;
      }
      futures.add(
        semaphore.run(() => _resolveOneEntry(
              run: run,
              tracks: tracks,
              index: index,
              pluginIds: resolverPluginIds,
            )),
      );
    }

    try {
      await Future.wait(futures);
    } catch (e) {
      if (_stale(run)) return;
      log('Matching failed: $e', name: 'ContentImportCubit');
      final counts = _recount(tracks);
      emit(state.copyWith(
        tracks: List.unmodifiable(tracks),
        resolvedCount: counts.resolved,
        failedCount: counts.failed,
      ));
      return _fail(ImportErrorKind.matchingFailed, 'Matching failed: $e');
    }

    if (!_stale(run)) {
      final counts = _recount(tracks);
      log(
        'Resolution complete: ${counts.resolved} resolved, '
        '${counts.failed} failed out of ${tracks.length}',
        name: 'ContentImportCubit',
      );
      emit(state.copyWith(
        tracks: List.unmodifiable(tracks),
        resolvedCount: counts.resolved,
        failedCount: counts.failed,
        phase: ImportPhase.review,
      ));
    }
  }

  Future<void> _resolveOneEntry({
    required int run,
    required List<ImportTrackEntry> tracks,
    required int index,
    required List<String> pluginIds,
  }) async {
    if (_stale(run)) return;

    final entry = tracks[index];

    // Mark as resolving.
    tracks[index] = entry.copyWith(status: TrackResolutionStatus.resolving);
    emit(state.copyWith(tracks: List.unmodifiable(tracks)));

    try {
      final target = TrackMatchTarget.fromImport(
        title: entry.sourceTrack.title,
        artists: entry.sourceTrack.artists,
        durationMs: entry.sourceTrack.durationMs?.toInt(),
      );

      // Use the shared resolver — parallel across plugins, scored, with
      // early-exit on high confidence.
      final candidates = await _resolver.resolveTrack(
        target: target,
        pluginIds: pluginIds,
        sequential: false,
        minConfidence: _kMinConfidence,
        earlyAcceptThreshold: 0.93,
        limit: _kMaxCandidatesPerTrack,
      );

      if (_stale(run)) return;

      if (candidates.isNotEmpty) {
        tracks[index] = entry.copyWith(
          status: TrackResolutionStatus.resolved,
          resolvedTrack: candidates.first.track,
          candidates: candidates.map((c) => c.track).toList(growable: false),
          confidences:
              candidates.map((c) => c.confidence).toList(growable: false),
        );
      } else {
        tracks[index] = entry.copyWith(
          status: TrackResolutionStatus.failed,
          candidates: const [],
        );
      }
    } catch (e) {
      log(
        'Failed to resolve "${entry.sourceTrack.title}": $e',
        name: 'ContentImportCubit',
      );
      if (!_stale(run)) {
        tracks[index] = entry.copyWith(
          status: TrackResolutionStatus.error,
          candidates: const [],
          confidences: const [],
        );
      }
    }

    // Emit progress.
    if (!_stale(run)) {
      final counts = _recount(tracks);
      emit(state.copyWith(
        tracks: List.unmodifiable(tracks),
        resolvedCount: counts.resolved,
        failedCount: counts.failed,
      ));
    }
  }

  // ── Cancel / retry ───────────────────────────────────────────────────────

  /// Stops the running import. While matching, the tracks matched so far go
  /// to review; before that, the screen returns to the link input. A plugin
  /// call already running in Rust can't be interrupted from Dart: it finishes
  /// in the background and the next call waits for it (see [_call]).
  void cancel() {
    switch (state.phase) {
      case ImportPhase.resolving:
        _run++;
        log('Resolution cancelled by user.', name: 'ContentImportCubit');
        final counts = _recount(state.tracks);
        emit(state.copyWith(
          phase: ImportPhase.review,
          resolvedCount: counts.resolved,
          failedCount: counts.failed,
        ));
      case ImportPhase.checkingUrl:
      case ImportPhase.fetchingInfo:
      case ImportPhase.fetchingTracks:
        _run++;
        log('Import cancelled by user.', name: 'ContentImportCubit');
        emit(ContentImportState(pluginId: state.pluginId, url: state.url));
      default:
        return;
    }
  }

  /// Retries after an error, redoing as little as possible: a failed save
  /// goes back to review with the matches intact; once tracks were fetched or
  /// parsed, matching resumes with them (no refetch, no re-reading the file);
  /// otherwise the same URL starts over.
  Future<void> retry() async {
    if (state.phase != ImportPhase.error) return;
    if (state.errorKind == ImportErrorKind.saveFailed) {
      emit(state.copyWith(phase: ImportPhase.review, clearError: true));
      return;
    }
    if (state.tracks.isNotEmpty) return _resumeMatching();
    final pluginId = state.pluginId;
    final url = state.url;
    if (pluginId == null || pluginId.isEmpty || url == null) return reset();
    await checkUrl(pluginId, url);
  }

  /// From review: looks up again the tracks whose lookup errored (not the
  /// ones that simply had no match), then returns to review.
  Future<void> retryFailedLookups() async {
    if (state.phase != ImportPhase.review ||
        !state.tracks.any((t) => t.status == TrackResolutionStatus.error)) {
      return;
    }
    await _resumeMatching();
  }

  /// Matches the kept tracks that have no answer yet.
  Future<void> _resumeMatching() {
    final run = ++_run;
    emit(state.copyWith(
      phase: ImportPhase.resolving,
      attempt: 1,
      phaseStartedAt: DateTime.now(),
      clearError: true,
    ));
    return _resolveTracks(run);
  }

  // ── User candidate selection ─────────────────────────────────────────────

  void pickCandidate(int trackIndex, int? candidateIdx) {
    final tracks = List<ImportTrackEntry>.from(state.tracks);
    if (trackIndex < 0 || trackIndex >= tracks.length) return;

    tracks[trackIndex] = tracks[trackIndex].copyWith(
      selectedCandidateIndex: candidateIdx,
    );

    final counts = _recount(tracks);
    emit(state.copyWith(
      tracks: List.unmodifiable(tracks),
      resolvedCount: counts.resolved,
      failedCount: counts.failed,
    ));
  }

  // ── Step 5: Save to Library ──────────────────────────────────────────────

  Future<void> saveToLibrary({String? customName}) async {
    final info = state.collectionInfo;
    if (info == null || state.phase != ImportPhase.review) return;

    emit(state.copyWith(phase: ImportPhase.saving));

    try {
      final rawName = customName?.trim().isNotEmpty == true
          ? customName!.trim()
          : info.title.trim();
      final playlistName = rawName.isNotEmpty ? rawName : 'Imported Playlist';

      final playlistId = await _playlistDao.ensurePlaylist(playlistName);

      final thumbUrl = info.thumbnailUrl;
      if (thumbUrl != null && thumbUrl.isNotEmpty) {
        await _playlistDao.updatePlaylistThumbnail(playlistId, thumbUrl);
      }

      var savedCount = 0;
      for (final entry in state.tracks) {
        final track = entry.effectiveTrack;
        if (track != null) {
          await _playlistDao.addTrackToPlaylist(playlistId, track);
          savedCount++;
        }
      }

      log('Saved $savedCount tracks to "$playlistName".',
          name: 'ContentImportCubit');

      emit(state.copyWith(
        phase: ImportPhase.done,
        resolvedCount: savedCount,
      ));
    } catch (e) {
      log('saveToLibrary failed: $e', name: 'ContentImportCubit');
      _fail(ImportErrorKind.saveFailed, 'Failed to save playlist: $e');
    }
  }

  // ── Reset ────────────────────────────────────────────────────────────────

  void reset() {
    _run++;
    emit(const ContentImportState());
  }

  // ── File import (M3U, CSV) ────────────────────────────────────────────────

  /// Loads tracks parsed from a file and starts matching, skipping the
  /// URL-check / collection-info / fetch-tracks plugin steps. [summary] gives
  /// the playlist name; [skippedRows] are the file rows left out, for review.
  Future<void> loadFromFile(
    List<ImportTrackItem> tracks,
    ImportCollectionSummary summary, {
    List<CsvSkippedRow> skippedRows = const [],
  }) async {
    if (isBusy) return;
    final run = ++_run;
    emit(ContentImportState(
      phase: ImportPhase.resolving,
      collectionInfo: summary,
      tracks: List.unmodifiable(
        tracks.map((t) => ImportTrackEntry(sourceTrack: t)).toList(),
      ),
      skippedRows: List.unmodifiable(skippedRows),
      phaseStartedAt: DateTime.now(),
    ));
    await _resolveTracks(run);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Returns only loaded content-resolver plugin IDs.
  Future<List<String>> _getContentResolverPluginIds() async {
    final available = await _pluginService.getAvailablePlugins();
    final loadedIds = _pluginService.getLoadedPlugins().toSet();
    return available
        .where((p) =>
            p.pluginType == PluginType.contentResolver &&
            loadedIds.contains(p.manifest.id))
        .map((p) => p.manifest.id)
        .toList(growable: false);
  }

  /// Single source of truth for resolved/failed counts.
  ({int resolved, int failed}) _recount(List<ImportTrackEntry> tracks) {
    var resolved = 0;
    var failed = 0;
    for (final t in tracks) {
      if (t.isSkipped) {
        failed++;
      } else if (t.effectiveTrack != null) {
        resolved++;
      } else if (t.status != TrackResolutionStatus.pending &&
          t.status != TrackResolutionStatus.resolving) {
        failed++;
      }
    }
    return (resolved: resolved, failed: failed);
  }
}
