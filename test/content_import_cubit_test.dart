// Phase 1: playlist-link import reliability (timeouts, retries, cancel,
// typed errors, one call per plugin at a time).
//
// testWidgets is used only for its fake clock: tester.pump(d) advances time,
// so multi-minute plugin calls and backoff waits run instantly.
//
// Run with: flutter test test/content_import_cubit_test.dart

import 'dart:async';

import 'package:Bloomee/plugins/blocs/import/content_import_cubit.dart';
import 'package:Bloomee/plugins/blocs/import/content_import_state.dart';
import 'package:Bloomee/plugins/errors/plugin_exceptions.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_fakes.dart';

const _url = 'https://open.spotify.com/playlist/abc';

ImportTrackItem _item(int i) =>
    ImportTrackItem(title: 'Song $i', artists: ['Artist $i'], isExplicit: false);

PluginResponse _info(int? count) => PluginResponse.collectionInfo(
      ImportCollectionSummary(
        title: 'Mix',
        kind: ImportCollectionType.playlist,
        trackCount: count,
      ),
    );

PluginResponse _tracks(int n) =>
    PluginResponse.importTracks([for (var i = 0; i < n; i++) _item(i)]);

Future<PluginResponse> _after(Duration d, PluginResponse r) =>
    Future.delayed(d, () => r);

Future<PluginResponse> _failAfter(Duration d, String message) =>
    Future.delayed(d, () => throw PluginExecutionException(message: message));

/// A plugin that answers every step, with the given overrides.
Handler _plugin({
  Future<PluginResponse> Function()? check,
  Future<PluginResponse> Function()? info,
  Future<PluginResponse> Function()? tracks,
}) {
  return (cmd) {
    if (cmd is ContentImporterCommand_GetTracks) {
      return tracks?.call() ?? Future.value(_tracks(3));
    }
    if (cmd is ContentImporterCommand_GetCollectionInfo) {
      return info?.call() ?? Future.value(_info(3));
    }
    return check?.call() ?? Future.value(const PluginResponse.canHandle(true));
  };
}

/// Resolver plugin "yt" is loaded and finds nothing, so fetched tracks go
/// to review unmatched.
ContentImportCubit _cubit(FakePluginService svc, {RecordingPlaylistDao? dao}) {
  return ContentImportCubit(
    pluginService: svc,
    resolver: FakeResolver(svc),
    playlistDao: dao ?? RecordingPlaylistDao(),
  );
}

void main() {
  group('importTracksTimeout', () {
    test('grows with the playlist and is capped', () {
      expect(importTracksTimeout(0), const Duration(seconds: 60));
      expect(importTracksTimeout(120), const Duration(seconds: 90));
      expect(importTracksTimeout(1000), const Duration(seconds: 345));
      expect(importTracksTimeout(null), importTracksTimeout(1000));
      expect(importTracksTimeout(100000), const Duration(minutes: 10));
    });

    test('is never below the old flat 10 s budget', () {
      for (final n in [null, 0, 1, 50, 51, 5000]) {
        expect(importTracksTimeout(n), greaterThan(const Duration(seconds: 30)));
      }
    });
  });

  group('classifyImportError', () {
    PluginExecutionException e(String m) => PluginExecutionException(message: m);

    test('reads plugin failures', () {
      expect(classifyImportError(e('HTTP 429 Too Many Requests')),
          ImportErrorKind.rateLimited);
      expect(classifyImportError(e('rate limit exceeded')),
          ImportErrorKind.rateLimited);
      expect(classifyImportError(e('HTTP 503 Service Unavailable')),
          ImportErrorKind.network);
      expect(classifyImportError(e('HTTP 401: invalid client')),
          ImportErrorKind.authFailed);
      expect(classifyImportError(e('403 Forbidden')),
          ImportErrorKind.authFailed);
      expect(classifyImportError(e('HTTP 404: resource not found')),
          ImportErrorKind.notFound);
      expect(classifyImportError(e('This playlist is private')),
          ImportErrorKind.notFound);
      expect(
          classifyImportError(
              e('error sending request for url (https://api.spotify.com)')),
          ImportErrorKind.network);
      expect(classifyImportError(e('operation timed out')),
          ImportErrorKind.network);
      expect(classifyImportError(e('could not parse response')),
          ImportErrorKind.unknown);
    });

    test('reads app-side failures', () {
      expect(classifyImportError(TimeoutException('slow')),
          ImportErrorKind.timeout);
      expect(
          classifyImportError(const PluginNotLoadedException(pluginId: 'x')),
          ImportErrorKind.pluginUnavailable);
    });

    test('only network and rate-limit failures are retried', () {
      expect(
          ImportErrorKind.values.where((k) => k.isTransient).toSet(),
          {ImportErrorKind.network, ImportErrorKind.rateLimited});
    });
  });

  group('playlist-link import', () {
    testWidgets('a playlist slower than the old 10 s budget imports in order',
        (tester) async {
      final svc = FakePluginService(_plugin(
        info: () => _after(const Duration(seconds: 3), _info(1200)),
        tracks: () => _after(const Duration(seconds: 100), _tracks(1200)),
      ));
      final cubit = _cubit(svc);

      unawaited(cubit.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 50));
      expect(cubit.state.phase, ImportPhase.fetchingTracks);
      expect(cubit.state.phaseStartedAt, isNotNull);

      await tester.pump(const Duration(seconds: 60));
      expect(cubit.state.phase, ImportPhase.review);
      expect(cubit.state.tracks, hasLength(1200));
      expect(cubit.state.tracks.take(3).map((t) => t.sourceTrack.title),
          ['Song 0', 'Song 1', 'Song 2']);
      expect(svc.calls, ['check', 'info', 'tracks']);
      await cubit.close();
    });

    testWidgets('transient failures are retried with backoff', (tester) async {
      var n = 0;
      final svc = FakePluginService(_plugin(
        tracks: () => ++n < 3
            ? _failAfter(const Duration(seconds: 1), 'error sending request')
            : Future.value(_tracks(2)),
      ));
      final cubit = _cubit(svc);

      unawaited(cubit.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 2)); // first try failed at 1 s
      expect(cubit.state.attempt, 2);
      expect(svc.calls.where((c) => c == 'tracks'), hasLength(1));

      await tester.pump(const Duration(seconds: 20)); // 2 s + 6 s backoff
      expect(cubit.state.phase, ImportPhase.review);
      expect(svc.calls.where((c) => c == 'tracks'), hasLength(3));
      await cubit.close();
    });

    testWidgets('a rate limit stops after three tries', (tester) async {
      final svc = FakePluginService(_plugin(
        tracks: () => _failAfter(Duration.zero, 'HTTP 429'),
      ));
      final cubit = _cubit(svc);

      unawaited(cubit.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 9));
      expect(cubit.state.phase, ImportPhase.fetchingTracks); // waiting 10 s

      await tester.pump(const Duration(seconds: 60)); // 10 s + 30 s
      expect(cubit.state.phase, ImportPhase.error);
      expect(cubit.state.errorKind, ImportErrorKind.rateLimited);
      expect(svc.calls.where((c) => c == 'tracks'), hasLength(3));
      await cubit.close();
    });

    testWidgets('a missing playlist is reported once, not retried',
        (tester) async {
      final svc = FakePluginService(_plugin(
        info: () => _failAfter(Duration.zero, 'HTTP 404: Not found'),
      ));
      final cubit = _cubit(svc);

      unawaited(cubit.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 30));
      expect(cubit.state.phase, ImportPhase.error);
      expect(cubit.state.errorKind, ImportErrorKind.notFound);
      // The raw message keeps the prefix the screen's fallback matches on.
      expect(cubit.state.error, startsWith('Failed to fetch collection info: '));
      expect(svc.calls, ['check', 'info']);
      await cubit.close();
    });

    testWidgets('unsupported URLs and empty playlists get their own errors',
        (tester) async {
      final unsupported = FakePluginService(_plugin(
        check: () => Future.value(const PluginResponse.canHandle(false)),
      ));
      final empty = FakePluginService(_plugin(
        tracks: () => Future.value(const PluginResponse.importTracks([])),
      ));
      final a = _cubit(unsupported);
      final b = _cubit(empty);

      unawaited(a.checkUrl('spotify', 'https://example.com'));
      unawaited(b.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 1));
      expect(a.state.errorKind, ImportErrorKind.unsupportedUrl);
      expect(b.state.errorKind, ImportErrorKind.emptyCollection);
      await a.close();
      await b.close();
    });

    testWidgets('a retry after a timeout waits for the abandoned call',
        (tester) async {
      var infoCalls = 0;
      final svc = FakePluginService(_plugin(
        info: () => ++infoCalls == 1
            ? _after(const Duration(seconds: 60), _info(2)) // over the 45 s budget
            : _after(const Duration(seconds: 1), _info(2)),
      ));
      final cubit = _cubit(svc);

      unawaited(cubit.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 46));
      expect(cubit.state.phase, ImportPhase.error);
      expect(cubit.state.errorKind, ImportErrorKind.timeout);

      // The first info call is still running "in Rust": nothing new is sent.
      unawaited(cubit.retry());
      await tester.pump(const Duration(seconds: 5));
      expect(cubit.state.phase, ImportPhase.checkingUrl);
      expect(svc.calls, ['check', 'info']);

      // It finishes at 60 s; the retry then runs normally.
      await tester.pump(const Duration(seconds: 20));
      expect(cubit.state.phase, ImportPhase.review);
      expect(svc.calls, ['check', 'info', 'check', 'info', 'tracks']);
      expect(svc.maxActive, 1);
      await cubit.close();
    });

    testWidgets('a call stuck behind a long abandoned one fails as busy',
        (tester) async {
      var infoCalls = 0;
      final svc = FakePluginService(_plugin(
        info: () => ++infoCalls == 1
            ? _after(const Duration(seconds: 200), _info(2))
            : Future.value(_info(2)),
      ));
      final cubit = _cubit(svc);

      unawaited(cubit.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 46));
      expect(cubit.state.errorKind, ImportErrorKind.timeout);

      unawaited(cubit.retry());
      await tester.pump(const Duration(seconds: 41));
      expect(cubit.state.phase, ImportPhase.error);
      expect(cubit.state.errorKind, ImportErrorKind.pluginBusy);
      expect(svc.calls, ['check', 'info']);

      await tester.pump(const Duration(seconds: 200)); // let the call drain
      expect(svc.maxActive, 1);
      await cubit.close();
    });

    testWidgets('cancel returns to the link and ignores the late answer',
        (tester) async {
      final svc = FakePluginService(_plugin(
        tracks: () => _after(const Duration(seconds: 30), _tracks(5)),
      ));
      final cubit = _cubit(svc);

      unawaited(cubit.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 5));
      expect(cubit.state.phase, ImportPhase.fetchingTracks);

      cubit.cancel();
      expect(cubit.state.phase, ImportPhase.idle);
      expect(cubit.state.url, _url);

      await tester.pump(const Duration(seconds: 40));
      expect(cubit.state.phase, ImportPhase.idle);
      expect(cubit.state.tracks, isEmpty);
      await cubit.close();
    });

    testWidgets('a second import while one is running is ignored',
        (tester) async {
      final svc = FakePluginService(_plugin(
        info: () => _after(const Duration(seconds: 5), _info(2)),
      ));
      final cubit = _cubit(svc);

      unawaited(cubit.checkUrl('spotify', _url));
      unawaited(cubit.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 1));
      unawaited(cubit.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 10));
      expect(svc.calls, ['check', 'info', 'tracks']);
      await cubit.close();
    });

    testWidgets('a failed save retries into review with the tracks kept',
        (tester) async {
      final dao = RecordingPlaylistDao()..fail = true;
      final svc = FakePluginService(_plugin());
      final cubit = _cubit(svc, dao: dao);

      unawaited(cubit.checkUrl('spotify', _url));
      await tester.pump(const Duration(seconds: 1));
      expect(cubit.state.phase, ImportPhase.review);

      await cubit.saveToLibrary();
      expect(cubit.state.errorKind, ImportErrorKind.saveFailed);

      await cubit.retry();
      expect(cubit.state.phase, ImportPhase.review);
      expect(cubit.state.tracks, hasLength(3));
      expect(svc.calls, ['check', 'info', 'tracks']); // nothing refetched
      await cubit.close();
    });

    testWidgets('file import still goes straight to matching',
        (tester) async {
      final svc = FakePluginService(_plugin());
      final cubit = _cubit(svc);

      await cubit.loadFromFile(
        [_item(0), _item(1)],
        const ImportCollectionSummary(
            title: 'From file', kind: ImportCollectionType.playlist),
      );
      expect(cubit.state.phase, ImportPhase.review);
      expect(cubit.state.tracks, hasLength(2));
      expect(svc.calls, isEmpty);
      await cubit.close();
    });
  });
}
