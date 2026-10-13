// Recommendations v1: where candidates come from (CandidateGatherer) and how
// batches are queued (RelatedSongsManager).
//
// Run with: flutter test test/recommendation_pipeline_test.dart

import 'dart:async';

import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/player/player_engine.dart';
import 'package:Bloomee/services/player/related_songs_manager.dart';
import 'package:Bloomee/services/plugin/plugin_service.dart';
import 'package:Bloomee/services/recommendations/candidate_gatherer.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/recs_dataset.dart';
import 'import_fakes.dart';

Future<PluginResponse> _noImporter(ContentImporterCommand _) =>
    throw StateError('not an importer test');

PluginResponse _radio(List<Track> items, [String? next]) =>
    PluginResponse.moreTracks(PagedTracks(items: items, nextPageToken: next));

PluginResponse _artist(String name, List<Track> top, List<String> related) =>
    PluginResponse.artistDetails(ArtistDetails(
      summary: ArtistSummary(id: 'yt::${name.toLowerCase()}', name: name),
      topTracks: top,
      albums: const PagedAlbums(items: []),
      relatedArtists: [
        for (final r in related)
          ArtistSummary(id: 'yt::${r.toLowerCase()}', name: r),
      ],
    ));

/// Finds the same song on whichever plugin it is asked about.
class _Matcher extends CrossPluginResolver {
  _Matcher(PluginService s) : super(pluginService: s);
  final asked = <List<String>>[];

  @override
  Future<List<ScoredTrackCandidate>> resolveTrack({
    required TrackMatchTarget target,
    required List<String> pluginIds,
    int limit = 5,
    double minConfidence = 0.45,
    double earlyAcceptThreshold = 0.93,
    bool sequential = false,
    Set<String> excludeTrackIds = const {},
    ContentSearchFilter searchFilter = ContentSearchFilter.track,
    List<String>? queries,
  }) async {
    asked.add(pluginIds);
    final p = pluginIds.first;
    return [
      ScoredTrackCandidate(
        track: tr(target.title.toLowerCase().replaceAll(' ', ''), target.title,
            target.primaryArtist, plugin: p, sec: 200),
        pluginId: p,
        confidence: 0.95,
      ),
    ];
  }
}

final _seed = tr('bl', 'Blinding Lights', 'The Weeknd', sec: 200);
final _syt = tr('syt', 'Save Your Tears', 'The Weeknd', sec: 215);
final _starboy = tr('starboy', 'Starboy', 'The Weeknd', sec: 230);
final _phys = tr('phys', 'Physical', 'Dua Lipa', sec: 194);
final _lev = tr('lev', 'Levitating', 'Dua Lipa', sec: 203, plugin: 'js');
final _shape = tr('shape', 'Shape of You', 'Ed Sheeran', sec: 233);

/// yt: radio (2 pages) and artist details; js: radio.
Future<PluginResponse> _plugins(String plugin, ContentResolverCommand cmd) async {
  if (cmd is ContentResolverCommand_GetRadioTracks) {
    if (plugin == 'js') return _radio([_lev]);
    return cmd.pageToken == null
        ? _radio([_syt, _shape], 'p2')
        : _radio([tr('p2a', 'Page Two', 'Someone', sec: 200)]);
  }
  if (cmd is ContentResolverCommand_GetArtistDetails) {
    return cmd.id == 'the weeknd'
        ? _artist('The Weeknd', [_starboy], ['Dua Lipa'])
        : _artist('Dua Lipa', [_phys], const []);
  }
  throw StateError('unexpected $cmd');
}

({FakePluginService svc, _Matcher matcher, CandidateGatherer gatherer})
    _gatherSetup({ResolverHandler? handler, List<String>? resolvers}) {
  final svc = FakePluginService(_noImporter,
      resolvers: resolvers ?? ['yt', 'js'], onResolver: handler ?? _plugins);
  final matcher = _Matcher(svc);
  return (
    svc: svc,
    matcher: matcher,
    gatherer: CandidateGatherer(svc, matcher,
        timeout: const Duration(milliseconds: 200)),
  );
}

/// Scripted gatherer for manager tests: counts calls.
class _ScriptedGatherer extends CandidateGatherer {
  _ScriptedGatherer(this.first, [this.pages = const {}])
      : super(PluginService(), CrossPluginResolver(pluginService: PluginService()));
  final GatherResult first;
  final Map<String, GatherResult> pages;
  final seeds = <String>[];
  final pageCalls = <String>[];

  @override
  Future<GatherResult> gather(Track seed, {String? radioPage}) async {
    if (radioPage == null) {
      seeds.add(seed.title);
      return first;
    }
    pageCalls.add(radioPage);
    return pages[radioPage] ?? GatherResult.empty;
  }
}

RelatedSongsManager _manager(CandidateGatherer g, {bool autoPlay = true}) {
  final plugins = PluginService();
  return RelatedSongsManager(
    plugins,
    gatherer: g,
    ranker: RecommendationRanker(CrossPluginResolver(pluginService: plugins)),
    loadTaste: (_) async => UserTaste.empty,
    autoPlayEnabled: () async => autoPlay,
  );
}

void main() {
  group('CandidateGatherer', () {
    test('first call: radio, artist, other plugin, related, in that order',
        () async {
      final s = _gatherSetup();
      final r = await s.gatherer.gather(_seed);
      expect([for (final c in r.candidates) '${c.source.name}:${c.track.title}'], [
        'radio:Save Your Tears',
        'radio:Shape of You',
        'seedArtist:Starboy',
        'otherPlugin:Levitating',
        'relatedArtist:Physical',
      ]);
      expect(r.nextRadioPage, 'p2');
      // Budget: 4 plugin calls here + 1 match on the other plugin.
      expect(s.svc.calls, unorderedEquals([
        'yt:radio', 'yt:artist:the weeknd', 'yt:artist:dua lipa', 'js:radio',
      ]));
      expect(s.matcher.asked, [
        ['js']
      ]);
    });

    test('later pages fetch only the radio', () async {
      final s = _gatherSetup();
      final r = await s.gatherer.gather(_seed, radioPage: 'p2');
      expect(r.candidates.single.track.title, 'Page Two');
      expect(r.nextRadioPage, isNull);
      expect(s.svc.calls, ['yt:radio']);
    });

    test('a song from this device is matched to a plugin first', () async {
      final s = _gatherSetup();
      final local = tr('42', 'Blinding Lights', 'The Weeknd', plugin: 'local');
      final r = await s.gatherer.gather(local);
      expect(s.matcher.asked.first, ['yt', 'js']);
      expect(r.candidates, isNotEmpty);
      expect(s.svc.calls, contains('yt:radio'));
    });

    test('a failing or hanging source just adds nothing', () async {
      final s = _gatherSetup(handler: (plugin, cmd) {
        if (cmd is ContentResolverCommand_GetArtistDetails) {
          return Completer<PluginResponse>().future; // hangs past the timeout
        }
        if (plugin == 'js') throw StateError('plugin crashed');
        return _plugins(plugin, cmd);
      });
      final r = await s.gatherer.gather(_seed);
      expect([for (final c in r.candidates) c.track.title],
          ['Save Your Tears', 'Shape of You']);
    });

    test('no loaded source plugin: nothing, and no calls', () async {
      final s = _gatherSetup(resolvers: []);
      expect((await s.gatherer.gather(_seed)).candidates, isEmpty);
      expect(s.svc.calls, isEmpty);
    });
  });

  group('RelatedSongsManager', () {
    final pool = GatherResult([
      ...from(RecSource.radio, [
        _syt,
        _shape,
        tr('a', 'Track A', 'Artist A', sec: 200),
        tr('b', 'Track B', 'Artist B', sec: 200),
        tr('c', 'Track C', 'Artist C', sec: 200),
        tr('d', 'Track D', 'Artist D', sec: 200),
        tr('e', 'Track E', 'Artist E', sec: 200),
        tr('f', 'Track F', 'Artist F', sec: 200),
      ]),
    ], 'p2');

    Future<List<Track>> refill(RelatedSongsManager m, List<Track> queue) async {
      final added = <Track>[];
      m.onAddQueueItems = (items, {bool atLast = false}) {
        expect(atLast, isTrue);
        added.addAll(items);
      };
      await m.checkForRelatedSongs(
        currentMedia: queue.last,
        queue: queue,
        currentPlayingIdx: queue.length - 1,
        loopMode: LoopMode.off,
      );
      return added;
    }

    test('queues a batch of 5 with a reason for each', () async {
      final m = _manager(_ScriptedGatherer(pool));
      final added = await refill(m, [_seed]);
      expect(added, hasLength(kRecommendationBatch));
      expect(m.reasons.value.keys.toSet(), {for (final t in added) t.id});
    });

    test('does nothing with autoplay off, a long queue or loop-all', () async {
      final g = _ScriptedGatherer(pool);
      expect(await refill(_manager(g, autoPlay: false), [_seed]), isEmpty);

      final m = _manager(g);
      var added = 0;
      m.onAddQueueItems = (items, {bool atLast = false}) => added++;
      await m.checkForRelatedSongs(
          currentMedia: _seed,
          queue: [_seed, _syt, _shape],
          currentPlayingIdx: 0,
          loopMode: LoopMode.off);
      await m.checkForRelatedSongs(
          currentMedia: _seed,
          queue: [_seed],
          currentPlayingIdx: 0,
          loopMode: LoopMode.all);
      expect(added, 0);
      expect(g.seeds, isEmpty);
    });

    test('stays anchored to the user\'s track and never repeats itself',
        () async {
      final g = _ScriptedGatherer(pool, {
        'p2': GatherResult(
            from(RecSource.radio, [
              for (var i = 0; i < 6; i++)
                tr('n$i', 'Next $i', 'Artist N$i', sec: 200),
            ]),
            null),
      });
      final m = _manager(g);
      final queue = [_seed];
      queue.addAll(await refill(m, queue));
      // Now playing the last auto-queued track: still seeded by Blinding Lights.
      queue.addAll(await refill(m, queue));
      queue.addAll(await refill(m, queue));

      expect(g.seeds, ['Blinding Lights']); // gathered once for the seed
      expect(g.pageCalls, ['p2']); // the pool ran short once
      final ids = [for (final t in queue) t.id];
      expect(ids.toSet(), hasLength(ids.length), reason: '$ids');
    });

    test('clearing forgets reasons and the seed', () async {
      final g = _ScriptedGatherer(pool);
      final m = _manager(g);
      await refill(m, [_seed]);
      m.clearRelatedSongs();
      expect(m.reasons.value, isEmpty);
      await refill(m, [_starboy]);
      expect(g.seeds, ['Blinding Lights', 'Starboy']);
    });
  });
}
