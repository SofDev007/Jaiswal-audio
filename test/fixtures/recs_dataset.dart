// Representative recommendation scenarios for the ranker tests.
//
// Each scenario is a seed track, the candidate pool the plugins would return
// (radio first, in plugin order, then the other sources), the listener's
// on-device history, and hand labels:
//   relevant: a good next track for this listener
//   traps:    must never be suggested (the seed again under another ID or
//             version, unrequested remix/karaoke/sped-up, unlabeled covers,
//             something played in the last 50 plays)
// Synthetic: these check the ranking logic on known situations; they are not
// a measurement of real-world taste.

import 'package:Bloomee/core/models/track_signal.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';

Track tr(String id, String title, String artist,
    {int? sec, String plugin = 'yt', List<String>? artists}) {
  final names = artists ?? (artist.isEmpty ? <String>[] : [artist]);
  return Track(
    id: '$plugin::$id',
    title: title,
    artists: [
      for (final a in names)
        ArtistSummary(id: '$plugin::${a.toLowerCase()}', name: a),
    ],
    durationMs: sec == null ? null : BigInt.from(sec * 1000),
    thumbnail: const Artwork(url: '', layout: ImageLayout.square),
    isExplicit: false,
  );
}

List<RecCandidate> from(RecSource source, List<Track> tracks) =>
    [for (var i = 0; i < tracks.length; i++) RecCandidate(tracks[i], source, i)];

class RecScenario {
  final String name;
  final Track seed;
  final List<RecCandidate> pool;
  final Set<String> relevant;
  final Set<String> traps;
  final List<TrackSignal> signals;
  final List<Track> liked;

  /// Newest first.
  final List<Track> history;

  const RecScenario({
    required this.name,
    required this.seed,
    required this.pool,
    required this.relevant,
    required this.traps,
    this.signals = const [],
    this.liked = const [],
    this.history = const [],
  });

  UserTaste taste(RecommendationRanker r) =>
      r.buildTaste(signals: signals, liked: liked, history: history, now: now);

  /// Today's behaviour: the radio page in plugin order (the whole page was
  /// appended, so these are the next five to play).
  List<Track> baseline([int take = 5]) => [
        for (final c in pool)
          if (c.source == RecSource.radio && c.track.id != seed.id) c.track,
      ].take(take).toList();
}

final now = DateTime(2026, 10, 13, 12);

// ── English pop, cold start ───────────────────────────────────────────────

final _bl = tr('bl', 'Blinding Lights', 'The Weeknd', sec: 200);
final _syt = tr('syt', 'Save Your Tears', 'The Weeknd', sec: 215);
final _starboy = tr('starboy', 'Starboy', 'The Weeknd',
    sec: 230, artists: ['The Weeknd', 'Daft Punk']);
final _hills = tr('hills', 'The Hills', 'The Weeknd', sec: 242);
final _afterHours = tr('ah', 'After Hours', 'The Weeknd', sec: 361);
final _dfy = tr('dfy', 'Die For You', 'The Weeknd', sec: 260);
final _levitating = tr('lev', 'Levitating', 'Dua Lipa', sec: 203);
final _shape = tr('shape', 'Shape of You', 'Ed Sheeran', sec: 233);
final _rain = tr('rain', 'Lofi Rain Sounds', 'Sleep Channel', sec: 3600);

final pop = RecScenario(
  name: 'English pop (cold start)',
  seed: _bl,
  pool: [
    ...from(RecSource.radio, [
      tr('bl_live', 'Blinding Lights (Live)', 'The Weeknd', sec: 230),
      tr('bl_sped', 'Blinding Lights - Sped Up', 'The Weeknd', sec: 160),
      tr('bl_cover', 'Blinding Lights', 'Cover Nation', sec: 199),
      _syt,
      _starboy,
      _hills,
      _afterHours,
      _dfy,
      _levitating,
      tr('bl_karaoke', 'Blinding Lights (Karaoke Version)', 'Sing King',
          sec: 200),
      _shape,
      _rain,
    ]),
    ...from(RecSource.seedArtist, [_starboy, _syt]),
    ...from(RecSource.otherPlugin, [
      tr('lev', 'Levitating', 'Dua Lipa', sec: 203, plugin: 'js'),
      tr('dsn', "Don't Start Now", 'Dua Lipa', sec: 183, plugin: 'js'),
      tr('bl', 'Blinding Lights', 'The Weeknd', sec: 200, plugin: 'js'),
    ]),
    ...from(RecSource.relatedArtist, [tr('phys', 'Physical', 'Dua Lipa', sec: 194)]),
  ],
  relevant: {
    'yt::syt', 'yt::starboy', 'yt::hills', 'yt::ah', 'yt::dfy', 'yt::lev',
    'js::lev', 'js::dsn', 'yt::shape', 'yt::phys',
  },
  traps: {'yt::bl_live', 'yt::bl_sped', 'yt::bl_cover', 'yt::bl_karaoke', 'js::bl'},
);

// ── Hindi, with a listening history ───────────────────────────────────────

final _kesariya = tr('kes', 'Kesariya', 'Arijit Singh', sec: 268);
final _tumHiHo = tr('thh', 'Tum Hi Ho', 'Arijit Singh', sec: 262);
final _lover = tr('lover', 'Lover', 'Diljit Dosanjh', sec: 190);
final _born = tr('born', 'Born to Shine', 'Diljit Dosanjh', sec: 180);
final _shreya1 = tr('sg1', 'Teri Ore', 'Shreya Ghoshal', sec: 300);
final _shreya2 = tr('sg2', 'Sun Raha Hai', 'Shreya Ghoshal', sec: 330);
final _shreya3 = tr('sg3', 'Agar Tum Mil Jao', 'Shreya Ghoshal', sec: 320);

final hindi = RecScenario(
  name: 'Hindi (history: loves Atif, liked Shreya, skips Diljit)',
  seed: _kesariya,
  pool: from(RecSource.radio, [
    tr('pas', 'Pasoori', 'Ali Sethi', sec: 224),
    _lover,
    tr('rl', 'Raataan Lambiyan', 'Jubin Nautiyal', sec: 230),
    _born,
    _tumHiHo,
    tr('tkcl', 'Tujhe Kitna Chahne Lage', 'Arijit Singh', sec: 285),
    tr('jlh', 'Jeene Laga Hoon', 'Atif Aslam', sec: 230),
    tr('gmp', 'Ghar More Pardesiya', 'Shreya Ghoshal', sec: 370),
    tr('kes_rmx', 'Kesariya (Remix)', 'DJ Remixer', sec: 240),
    tr('kes2', 'Kesariya (From "Brahmastra")', 'Arijit Singh', sec: 268),
  ]),
  relevant: {'yt::pas', 'yt::rl', 'yt::tkcl', 'yt::jlh', 'yt::gmp'},
  traps: {'yt::thh', 'yt::kes_rmx', 'yt::kes2'},
  signals: [
    TrackSignal(
        mediaId: 'yt::atif1',
        artistKey: artistKeyOf('Atif Aslam'),
        artistName: 'Atif Aslam',
        plays: 12,
        completions: 10,
        lastPlayedAt: now.subtract(const Duration(days: 2))),
    TrackSignal(
        mediaId: 'yt::lover',
        artistKey: artistKeyOf('Diljit Dosanjh'),
        artistName: 'Diljit Dosanjh',
        earlySkips: 2),
    TrackSignal(
        mediaId: 'yt::other_diljit',
        artistKey: artistKeyOf('Diljit Dosanjh'),
        artistName: 'Diljit Dosanjh',
        earlySkips: 2),
  ],
  liked: [_shreya1, _shreya2, _shreya3],
  history: [_tumHiHo],
);

// ── K-pop, one artist floods the radio ────────────────────────────────────

final kpop = RecScenario(
  name: 'K-pop (artist flood)',
  seed: tr('dyn', 'Dynamite', 'BTS', sec: 199),
  pool: [
    ...from(RecSource.radio, [
      tr('butter', 'Butter', 'BTS', sec: 164),
      tr('ptd', 'Permission to Dance', 'BTS', sec: 187),
      tr('lgo', 'Life Goes On', 'BTS', sec: 207),
      tr('dyn_inst', 'Dynamite (Instrumental)', 'BTS', sec: 199),
      tr('dyn_rmx', 'Dynamite (Acoustic Remix)', 'BTS', sec: 200),
      tr('hylt', 'How You Like That', 'BLACKPINK', sec: 182),
      tr('iu', '좋은 날', 'IU', sec: 234),
      tr('nl', 'Next Level', 'aespa', sec: 221),
    ]),
    ...from(RecSource.otherPlugin,
        [tr('butter', 'Butter', 'BTS', sec: 164, plugin: 'js')]),
  ],
  relevant: {'yt::butter', 'js::butter', 'yt::ptd', 'yt::lgo', 'yt::hylt', 'yt::iu', 'yt::nl'},
  traps: {'yt::dyn_inst', 'yt::dyn_rmx'},
);

// ── Lo-fi with gaps in the metadata ───────────────────────────────────────

final lofi = RecScenario(
  name: 'Lo-fi (missing metadata)',
  seed: tr('lofi', 'lofi hip hop radio', 'Lofi Girl'),
  pool: from(RecSource.radio, [
    tr('snow', 'Snowman', ''),
    tr('blank', '   ', 'Lofi Girl'),
    tr('cafe', 'Cafe Study', 'Lofi Girl'),
    tr('rainy', 'Rainy Days', ''),
    tr('night', 'Night Walk', 'Chillhop', sec: 150),
    _rain,
  ]),
  relevant: {'yt::snow', 'yt::cafe', 'yt::rainy', 'yt::night', 'yt::rain'},
  traps: {'yt::blank'},
);

final scenarios = [pop, hindi, kpop, lofi];
