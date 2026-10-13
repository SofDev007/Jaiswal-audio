// Phase 2: a parsed CSV through matching → review → save, plus retry,
// resume and cancel.
//
// Run with: flutter test test/csv_import_flow_test.dart

import 'dart:async';

import 'package:Bloomee/plugins/blocs/import/content_import_cubit.dart';
import 'package:Bloomee/plugins/blocs/import/content_import_state.dart';
import 'package:Bloomee/services/csv_playlist_parser.dart';
import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_fakes.dart';

const _csv = 'Track Name,Artist Name(s),Album Name\n'
    'Exact Song,Band,One\n' // line 2
    'Close Song,Band,One\n' // line 3
    'Unknown Song,Nobody,Two\n' // line 4
    'Exact Song,Band,One\n' // line 5: duplicate of 2
    ',Band,One\n'; // line 6: no title

/// Matches per title: confident, uncertain, nothing.
List<ScoredTrackCandidate> _byTitle(TrackMatchTarget target) => switch (target.title) {
      'Exact Song' => [candidate('Exact Song', 0.97, artist: 'Band')],
      'Close Song' => [
          candidate('Close Song (Live)', 0.62, artist: 'Band'),
          candidate('Close Song', 0.58, artist: 'Band'),
        ],
      _ => <ScoredTrackCandidate>[],
    };

final _parsed = parseCsvPlaylist(_csv);
const _summary =
    ImportCollectionSummary(title: 'My Mix', kind: ImportCollectionType.playlist);

Future<PluginResponse> _noPluginCalls(ContentImporterCommand _) =>
    throw StateError('file import must not call the importer plugin');

({ContentImportCubit cubit, FakePluginService svc, FakeResolver resolver,
    RecordingPlaylistDao dao}) _setup({List<String>? resolvers, MatchFn? match}) {
  final svc = FakePluginService(_noPluginCalls, resolvers: resolvers);
  final resolver = FakeResolver(svc, match ?? _byTitle);
  final dao = RecordingPlaylistDao();
  final cubit = ContentImportCubit(
      pluginService: svc, resolver: resolver, playlistDao: dao);
  return (cubit: cubit, svc: svc, resolver: resolver, dao: dao);
}

void main() {
  test('the sample file parses to 3 tracks and 2 skipped rows', () {
    expect(_parsed.tracks.map((t) => t.title),
        ['Exact Song', 'Close Song', 'Unknown Song']);
    expect(_parsed.skipped, const [
      CsvSkippedRow(5, CsvSkipReason.duplicate, duplicateOfLine: 2),
      CsvSkippedRow(6, CsvSkipReason.missingTitle),
    ]);
  });

  test('matching shows matched, uncertain and unmatched with confidence',
      () async {
    final s = _setup();
    await s.cubit.loadFromFile(_parsed.tracks, _summary,
        skippedRows: _parsed.skipped);

    final st = s.cubit.state;
    expect(st.phase, ImportPhase.review);
    expect(st.tracks.map((t) => t.matchState), [
      ImportMatchState.matched,
      ImportMatchState.uncertain,
      ImportMatchState.unmatched,
    ]);
    expect(st.tracks[0].confidence, 0.97);
    expect(st.tracks[1].confidence, 0.62);
    expect(st.tracks[1].confidences, [0.62, 0.58]);
    expect(st.tracks[2].confidence, isNull);
    expect(st.countWhere(ImportMatchState.uncertain), 1);
    expect(st.skippedRows, _parsed.skipped);
    expect(s.svc.calls, isEmpty);
    await s.cubit.close();
  });

  test('picking a candidate is a user choice with that candidate\'s confidence',
      () async {
    final s = _setup();
    await s.cubit.loadFromFile(_parsed.tracks, _summary);
    s.cubit.pickCandidate(1, 1);
    final e = s.cubit.state.tracks[1];
    expect(e.matchState, ImportMatchState.userSelected);
    expect(e.confidence, 0.58);
    expect(e.effectiveTrack!.title, 'Close Song');

    s.cubit.pickCandidate(1, -1);
    expect(s.cubit.state.tracks[1].matchState, ImportMatchState.skipped);
    expect(s.cubit.state.tracks[1].confidence, isNull);
    await s.cubit.close();
  });

  test('save keeps file order and leaves out unmatched and skipped tracks',
      () async {
    final s = _setup();
    await s.cubit.loadFromFile(_parsed.tracks, _summary);
    s.cubit.pickCandidate(1, 1);
    await s.cubit.saveToLibrary();

    expect(s.cubit.state.phase, ImportPhase.done);
    expect(s.dao.saved['My Mix'],
        ['yt::Exact Song::Band', 'yt::Close Song::Band']);
    await s.cubit.close();
  });

  test('a failed save retries into review, then saves', () async {
    final s = _setup();
    await s.cubit.loadFromFile(_parsed.tracks, _summary);
    s.dao.fail = true;
    await s.cubit.saveToLibrary();
    expect(s.cubit.state.errorKind, ImportErrorKind.saveFailed);

    await s.cubit.retry();
    expect(s.cubit.state.phase, ImportPhase.review);
    expect(s.resolver.looked, hasLength(3)); // nothing matched twice
    await s.cubit.saveToLibrary();
    expect(s.dao.saved['My Mix'], hasLength(2));
    await s.cubit.close();
  });

  test('no resolver plugin: error keeps the tracks; retry resumes matching',
      () async {
    final s = _setup(resolvers: []);
    await s.cubit.loadFromFile(_parsed.tracks, _summary,
        skippedRows: _parsed.skipped);
    expect(s.cubit.state.phase, ImportPhase.error);
    expect(s.cubit.state.errorKind, ImportErrorKind.noResolvers);
    expect(s.cubit.state.tracks, hasLength(3));
    expect(s.cubit.state.skippedRows, hasLength(2));

    s.svc.resolvers = ['yt']; // the user loads a plugin
    await s.cubit.retry();
    expect(s.cubit.state.phase, ImportPhase.review);
    expect(s.cubit.state.countWhere(ImportMatchState.matched), 1);
    expect(s.cubit.state.skippedRows, hasLength(2));
    await s.cubit.close();
  });

  test('a matching failure keeps the tracks; retry resumes', () async {
    final s = _setup();
    s.svc.listingError = StateError('plugin system restarting');
    await s.cubit.loadFromFile(_parsed.tracks, _summary);
    expect(s.cubit.state.errorKind, ImportErrorKind.matchingFailed);
    expect(s.cubit.state.tracks, hasLength(3));
    expect(s.resolver.looked, isEmpty);

    await s.cubit.retry();
    expect(s.cubit.state.phase, ImportPhase.review);
    expect(s.resolver.looked, ['Exact Song', 'Close Song', 'Unknown Song']);
    await s.cubit.close();
  });

  test('a lookup that throws is retried alone, not the whole playlist',
      () async {
    var flaky = true;
    final s = _setup(match: (t) {
      if (t.title == 'Close Song' && flaky) {
        flaky = false;
        throw StateError('socket closed');
      }
      return _byTitle(t);
    });
    await s.cubit.loadFromFile(_parsed.tracks, _summary);
    expect(s.cubit.state.phase, ImportPhase.review);
    expect(s.cubit.state.tracks[1].status, TrackResolutionStatus.error);
    expect(s.cubit.state.tracks[1].matchState, ImportMatchState.unmatched);

    await s.cubit.retryFailedLookups();
    expect(s.cubit.state.phase, ImportPhase.review);
    expect(s.cubit.state.tracks[1].matchState, ImportMatchState.uncertain);
    // Only the failed one was looked up again; the no-match one was not.
    expect(s.resolver.looked,
        ['Exact Song', 'Close Song', 'Unknown Song', 'Close Song']);
    await s.cubit.close();
  });

  test('cancel while matching goes to review with what was matched',
      () async {
    final gate = Completer<void>();
    final s = _setup(match: (t) async {
      if (t.title != 'Exact Song') await gate.future;
      return _byTitle(t);
    });
    final run = s.cubit.loadFromFile(_parsed.tracks, _summary);
    await pumpEventQueue();
    expect(s.cubit.state.phase, ImportPhase.resolving);

    s.cubit.cancel();
    expect(s.cubit.state.phase, ImportPhase.review);
    expect(s.cubit.state.tracks[0].matchState, ImportMatchState.matched);
    expect(s.cubit.state.tracks[1].matchState, ImportMatchState.pending);

    gate.complete(); // late answers must not change the review
    await run;
    expect(s.cubit.state.phase, ImportPhase.review);
    expect(s.cubit.state.tracks[1].matchState, ImportMatchState.pending);

    await s.cubit.saveToLibrary();
    expect(s.dao.saved['My Mix'], ['yt::Exact Song::Band']);
    await s.cubit.close();
  });

  test('a second file import while one is matching is ignored', () async {
    final gate = Completer<void>();
    final s = _setup(match: (t) async {
      await gate.future;
      return _byTitle(t);
    });
    final first = s.cubit.loadFromFile(_parsed.tracks, _summary);
    await pumpEventQueue();
    await s.cubit.loadFromFile([_parsed.tracks.first],
        const ImportCollectionSummary(
            title: 'Other', kind: ImportCollectionType.playlist));
    expect(s.cubit.state.collectionInfo!.title, 'My Mix');

    gate.complete();
    await first;
    expect(s.cubit.state.tracks, hasLength(3));
    await s.cubit.close();
  });
}
