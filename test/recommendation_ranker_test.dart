// Recommendations v1: ranking quality against today's behaviour, and each
// rule on its own (duplicates, versions, diversity, personalization, skips,
// missing metadata, cold start, script, explanations).
//
// Run with: flutter test test/recommendation_ranker_test.dart

import 'package:Bloomee/core/models/track_signal.dart';
import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/plugin/plugin_service.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/recs_dataset.dart';

final ranker =
    RecommendationRanker(CrossPluginResolver(pluginService: PluginService()));

List<Recommendation> rankScenario(RecScenario s, {int take = 5}) => ranker.rank(
      seed: s.seed,
      candidates: s.pool,
      taste: s.taste(ranker),
      take: take,
    );

double precision(List<Track> picked, Set<String> relevant) => picked.isEmpty
    ? 0
    : picked.where((t) => relevant.contains(t.id)).length / picked.length;

int traps(List<Track> picked, Set<String> traps) =>
    picked.where((t) => traps.contains(t.id)).length;

int maxPerArtist(List<Track> picked) {
  final n = <String, int>{};
  for (final t in picked) {
    if (t.artists.isEmpty) continue;
    final k = artistKeyOf(t.artists.first.name);
    n[k] = (n[k] ?? 0) + 1;
  }
  return n.values.fold(0, (a, b) => a > b ? a : b);
}

List<String> titles(List<Recommendation> r) => [for (final x in r) x.track.title];

void main() {
  group('quality on the dataset (vs today\'s radio order)', () {
    test('precision@5 is higher, traps and repeats are gone', () {
      var newP = 0.0, oldP = 0.0, newTraps = 0, oldTraps = 0;
      final rows = <String>[];
      for (final s in [pop, hindi, kpop]) {
        final picked = [for (final r in rankScenario(s)) r.track];
        final base = s.baseline();
        final p = precision(picked, s.relevant);
        final b = precision(base, s.relevant);
        newP += p;
        oldP += b;
        newTraps += traps(picked, s.traps);
        oldTraps += traps(base, s.traps);
        rows.add('${s.name}: precision@5 ${b.toStringAsFixed(2)} → '
            '${p.toStringAsFixed(2)}, traps ${traps(base, s.traps)} → '
            '${traps(picked, s.traps)}, max/artist ${maxPerArtist(base)} → '
            '${maxPerArtist(picked)}');

        expect(picked, hasLength(5), reason: s.name);
        expect(traps(picked, s.traps), 0, reason: s.name);
        expect(maxPerArtist(picked), lessThanOrEqualTo(kMaxPerArtist),
            reason: s.name);
        final keys = picked.map(ranker.songKey).toSet();
        expect(keys, hasLength(picked.length), reason: '${s.name}: repeats');
      }
      newP /= 3;
      oldP /= 3;
      // ignore: avoid_print
      print([...rows,
        'mean precision@5 ${oldP.toStringAsFixed(2)} → ${newP.toStringAsFixed(2)}; '
            'traps $oldTraps → $newTraps'
      ].join('\n'));

      expect(newP, greaterThanOrEqualTo(0.9));
      expect(newP - oldP, greaterThanOrEqualTo(0.3));
      expect(oldTraps, greaterThan(0)); // the dataset does exercise the traps
      expect(newTraps, 0);
    });
  });

  group('duplicates and versions', () {
    test('the seed under another ID, version or plugin is never suggested',
        () {
      final picked = titles(rankScenario(pop, take: 20));
      expect(picked.where((t) => t.contains('Blinding Lights')), isEmpty);
    });

    test('the same song from two plugins appears once and ranks higher', () {
      final r = rankScenario(pop, take: 20);
      expect(r.where((x) => x.track.title == 'Levitating'), hasLength(1));
      final lev = r.firstWhere((x) => x.track.title == 'Levitating');
      final shape = r.firstWhere((x) => x.track.title == 'Shape of You');
      expect(lev.parts['source']!, greaterThan(shape.parts['source']!));
    });

    test('a remix is allowed when the seed is a remix', () {
      final seed = tr('s', 'Song (Remix)', 'A', sec: 200);
      final r = ranker.rank(seed: seed, candidates: from(RecSource.radio, [
        tr('x', 'Other Song (Remix)', 'B', sec: 200),
        tr('y', 'Other Song (Live)', 'C', sec: 200),
      ]));
      expect(titles(r), ['Other Song (Remix)']);
    });

    test('tracks already queued are excluded by ID and by song', () {
      final r = ranker.rank(
        seed: pop.seed,
        candidates: pop.pool,
        excludeIds: {'yt::syt'},
        excludeSongKeys: {ranker.songKey(tr('z', 'Starboy', 'The Weeknd'))},
        take: 20,
      );
      expect(titles(r), isNot(contains('Save Your Tears')));
      expect(titles(r), isNot(contains('Starboy')));
    });
  });

  group('diversity', () {
    test('at most two per artist, not twice in a row when avoidable', () {
      final r = rankScenario(kpop);
      final artists = [for (final x in r) x.track.artists.first.name];
      expect(artists.where((a) => a == 'BTS'), hasLength(2));
      for (var i = 1; i < artists.length; i++) {
        expect(artists[i], isNot(artists[i - 1]), reason: '$artists');
      }
    });

    test('the batch does not open with the artist just queued', () {
      final r = ranker.rank(
          seed: kpop.seed, candidates: kpop.pool, previousArtistKey: 'bts');
      expect(r.first.track.artists.first.name, isNot('BTS'));
    });

    test('a single-artist pool still fills up to the cap', () {
      final r = ranker.rank(
        seed: tr('s', 'Seed', 'Solo', sec: 200),
        candidates: from(RecSource.seedArtist, [
          for (var i = 0; i < 6; i++) tr('t$i', 'Song $i', 'Solo', sec: 200),
        ]),
      );
      expect(r, hasLength(kMaxPerArtist));
    });
  });

  group('personalization', () {
    test('liked and often-played artists rise; a skip pattern sinks', () {
      final r = rankScenario(hindi, take: 10);
      final order = titles(r);
      final atif = order.indexOf('Jeene Laga Hoon');
      final shreya = order.indexOf('Ghar More Pardesiya');
      final lover = order.indexOf('Lover');
      expect(atif, lessThan(2), reason: '$order');
      expect(shreya, lessThan(3), reason: '$order');
      expect(lover, anyOf(-1, greaterThan(atif)), reason: '$order');

      // Same pool, no history: radio order decides instead.
      final cold = ranker.rank(
          seed: hindi.seed, candidates: hindi.pool, take: 10);
      expect(titles(cold).indexOf('Jeene Laga Hoon'), greaterThan(atif));
    });

    test('recently played is excluded; heard long ago loses the new bonus', () {
      expect(titles(rankScenario(hindi, take: 10)), isNot(contains('Tum Hi Ho')));

      final old = tr('old', 'Old Favourite', 'X', sec: 200);
      final fresh = tr('fresh', 'Fresh One', 'Y', sec: 200);
      final history = [
        for (var i = 0; i < kRecentPlays; i++) tr('h$i', 'Filler $i', 'Z'),
        old, // play #51: no longer "recent"
      ];
      final taste =
          ranker.buildTaste(signals: const [], liked: const [], history: history);
      final r = ranker.rank(
          seed: tr('s', 'Seed', 'W', sec: 200),
          candidates: from(RecSource.radio, [old, fresh]),
          taste: taste);
      expect(titles(r), ['Fresh One', 'Old Favourite']);
      expect(r.last.parts['novelty'], 0);
    });

    test('a never-suggest song stays out, from any source or upload', () {
      final keep = tr('k', 'Keep Me', 'A', sec: 200);
      final blocked = tr('b1', 'Blocked Song', 'B', sec: 200);
      final reupload = tr('b2', 'Blocked Song (Official Audio)', 'B', sec: 200);
      final taste = ranker.buildTaste(
          signals: const [],
          liked: const [],
          history: const [],
          blocked: {ranker.songKey(blocked)});
      final r = ranker.rank(
          seed: tr('s', 'Seed', 'W', sec: 200),
          candidates: from(RecSource.radio, [keep, blocked, reupload]),
          taste: taste);
      expect(titles(r), ['Keep Me']);
    });

    test('one early skip never excludes a track; a repeated one does', () {
      final t = tr('t', 'Maybe', 'A', sec: 200);
      TrackSignal sig(int skips, {int plays = 0}) => TrackSignal(
          mediaId: t.id,
          artistKey: 'a',
          artistName: 'A',
          earlySkips: skips,
          plays: plays);
      List<String> run(List<TrackSignal> s) => titles(ranker.rank(
          seed: tr('s', 'Seed', 'B', sec: 200),
          candidates: from(RecSource.radio, [t]),
          taste: ranker.buildTaste(
              signals: s, liked: const [], history: const [], now: now)));

      expect(run([sig(1)]), ['Maybe']);
      expect(run([sig(2)]), isEmpty);
      expect(run([sig(2, plays: 5)]), ['Maybe']); // played more than skipped
    });

    test("a skip pattern sinks the artist's other tracks too", () {
      // Born to Shine itself was never skipped; Diljit's other tracks were.
      final r = rankScenario(hindi, take: 10);
      final born = r.firstWhere((x) => x.track.title == 'Born to Shine');
      expect(born.parts['skipPenalty']!, lessThan(0));

      final pool = from(RecSource.radio, [
        tr('d1', 'Diljit Song', 'Diljit Dosanjh', sec: 268),
        tr('o1', 'Other Song', 'Other Singer', sec: 268),
      ]);
      final withSkips = ranker.rank(
          seed: hindi.seed, candidates: pool, taste: hindi.taste(ranker));
      final without = ranker.rank(seed: hindi.seed, candidates: pool);
      expect(titles(without).first, 'Diljit Song'); // radio order
      expect(titles(withSkips).first, 'Other Song');
    });

    test('recently played on another plugin still counts as recent', () {
      final heardOnJs = tr('x', 'Same Song', 'Singer', plugin: 'js');
      final onYt = tr('x', 'Same Song', 'Singer', plugin: 'yt', sec: 200);
      final taste = ranker.buildTaste(
          signals: const [], liked: const [], history: [heardOnJs]);
      expect(
          ranker.rank(
              seed: tr('s', 'Seed', 'A', sec: 200),
              candidates: from(RecSource.radio, [onYt]),
              taste: taste),
          isEmpty);
    });

    test('artist skip penalty needs a pattern across tracks', () {
      TrackSignal s(String id, int skips) => TrackSignal(
          mediaId: id, artistKey: 'a', artistName: 'A', earlySkips: skips);
      final oneTrack = ranker.buildTaste(
          signals: [s('1', 3)], liked: const [], history: const []);
      final twoTracks = ranker.buildTaste(
          signals: [s('1', 2), s('2', 1)], liked: const [], history: const []);
      expect(oneTrack.artistSkipPenalty['a'], isNull);
      expect(twoTracks.artistSkipPenalty['a'], greaterThan(0));
    });

    test('older plays count less than recent ones', () {
      TrackSignal s(String artist, int daysAgo) => TrackSignal(
          mediaId: artist,
          artistKey: artist,
          artistName: artist,
          plays: 5,
          lastPlayedAt: now.subtract(Duration(days: daysAgo)));
      final t = ranker.buildTaste(
          signals: [s('recent', 1), s('old', 120)],
          liked: const [],
          history: const [],
          now: now);
      expect(t.artistAffinity['recent']!, greaterThan(t.artistAffinity['old']!));
    });
  });

  group('missing metadata and cold start', () {
    test('no artists, no duration, blank titles: no crash, blanks dropped', () {
      final r = rankScenario(lofi, take: 10);
      expect(titles(r), isNot(contains('   ')));
      expect(titles(r).toSet(),
          {'Snowman', 'Cafe Study', 'Rainy Days', 'Night Walk', 'Lofi Rain Sounds'});
    });

    test('artist-less tracks are not capped together', () {
      final r = ranker.rank(
        seed: tr('s', 'Seed', 'A'),
        candidates: from(RecSource.radio,
            [for (var i = 0; i < 4; i++) tr('n$i', 'Untitled $i', '')]),
      );
      expect(r, hasLength(4));
    });

    test('empty history keeps the plugin\'s order among valid tracks', () {
      final r = ranker.rank(
        seed: tr('s', 'Seed', 'A', sec: 200),
        candidates: from(RecSource.radio, [
          tr('1', 'One', 'B', sec: 200),
          tr('2', 'Two', 'C', sec: 200),
          tr('3', 'Three', 'D', sec: 200),
        ]),
      );
      expect(titles(r), ['One', 'Two', 'Three']);
    });

    test('nothing to rank gives nothing', () {
      expect(ranker.rank(seed: pop.seed, candidates: const []), isEmpty);
    });
  });

  group('script as a language hint', () {
    final hindiTitle = tr('d', 'तेरी मिट्टी', 'B', sec: 200);
    final latinTitle = tr('l', 'Teri Mitti', 'C', sec: 200);
    List<String> run(List<Track> history) => titles(ranker.rank(
          seed: tr('s', 'Seed', 'A', sec: 200),
          candidates: from(RecSource.radio, [latinTitle, hindiTitle]),
          taste: ranker.buildTaste(
              signals: const [], liked: const [], history: history),
        ));

    test('a mostly-Devanagari history prefers Devanagari titles', () {
      final history = [
        for (var i = 0; i < 8; i++) tr('h$i', 'गाना $i', 'X'),
        tr('e', 'English Song', 'Y'),
      ];
      expect(run(history).first, 'तेरी मिट्टी');
    });

    test('a mixed history leaves order alone', () {
      final history = [
        for (var i = 0; i < 4; i++) tr('h$i', 'गाना $i', 'X'),
        for (var i = 0; i < 4; i++) tr('e$i', 'Song $i', 'Y'),
      ];
      expect(run(history).first, 'Teri Mitti');
    });

    test('scriptOf', () {
      expect(scriptOf('Kesariya'), 'latin');
      expect(scriptOf('केसरिया'), 'devanagari');
      expect(scriptOf('좋은 날'), 'hangul');
      expect(scriptOf('夜に駆ける'), 'cjk');
      expect(scriptOf('123 !!'), isNull);
    });
  });

  group('explanations', () {
    test('every recommendation carries a reason', () {
      for (final s in scenarios) {
        for (final r in rankScenario(s)) {
          expect(r.reason.subject, isNotEmpty, reason: '${s.name}: $r');
        }
      }
    });

    test('reasons match why the track was picked', () {
      RecReason reasonOf(String title, List<Recommendation> r) =>
          r.firstWhere((x) => x.track.title == title).reason;
      final popR = rankScenario(pop, take: 20);
      expect(reasonOf('Save Your Tears', popR),
          const RecReason(RecReasonKind.moreFrom, 'The Weeknd'));
      expect(reasonOf('Physical', popR),
          const RecReason(RecReasonKind.similarTo, 'The Weeknd'));
      expect(reasonOf('Levitating', popR),
          const RecReason(RecReasonKind.foundOnSources, '2'));
      expect(reasonOf('Shape of You', popR),
          const RecReason(RecReasonKind.becausePlaying, 'Blinding Lights'));

      final hindiR = rankScenario(hindi, take: 10);
      expect(reasonOf('Jeene Laga Hoon', hindiR),
          const RecReason(RecReasonKind.youOftenPlay, 'Atif Aslam'));
    });
  });

  test('isEarlySkip', () {
    expect(isEarlySkip(const Duration(seconds: 10), 200000), isTrue);
    expect(isEarlySkip(const Duration(seconds: 40), 200000), isFalse);
    expect(isEarlySkip(const Duration(seconds: 20), 60000), isFalse); // >25%
    expect(isEarlySkip(const Duration(seconds: 20), null), isTrue);
  });
}
