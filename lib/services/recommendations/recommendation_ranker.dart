/// On-device ranking for "what plays next": merges candidates from several
/// sources, drops ones that shouldn't be suggested, scores the rest from
/// metadata and the user's own listening, and keeps the batch varied.
///
/// Pure: no plugin calls, no database. See candidate_gatherer.dart for where
/// candidates come from and RelatedSongsManager for how batches are queued.
library recommendation_ranker;

import 'dart:math' as math;

import 'package:Bloomee/core/models/track_signal.dart';
import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/recommendations/song_card.dart';
import 'package:Bloomee/services/recommendations/taste_model.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';

/// Where a candidate came from.
enum RecSource {
  /// The seed's radio on its own plugin.
  radio,

  /// Top tracks of the seed's primary artist.
  seedArtist,

  /// Top tracks of an artist the plugin lists as related to the seed's.
  relatedArtist,

  /// Radio for the same song on another loaded plugin.
  otherPlugin,

  /// The user's own liked and playlist songs: the fallback when every
  /// plugin source failed, so autoplay never just stops.
  library,
}

class RecCandidate {
  final Track track;
  final RecSource source;

  /// Position within its source's list, 0 first.
  final int rank;

  const RecCandidate(this.track, this.source, this.rank);
}

enum RecReasonKind {
  becausePlaying,
  moreFrom,
  similarTo,
  youOftenPlay,
  foundOnSources,
  // Layer 2: shown when that part of the score mattered most.
  inLanguage, // subject: language name
  sameMood, // subject: mood name
  timeOfDay, // subject: mood name
}

/// Why a track was suggested; [subject] is the track title, artist name or
/// source count the reason refers to.
class RecReason {
  final RecReasonKind kind;
  final String subject;
  const RecReason(this.kind, this.subject);

  @override
  bool operator ==(Object other) =>
      other is RecReason && other.kind == kind && other.subject == subject;

  @override
  int get hashCode => Object.hash(kind, subject);

  @override
  String toString() => 'RecReason($kind, $subject)';
}

class Recommendation {
  final Track track;
  final double score;
  final RecReason reason;

  /// The weighted parts of [score], by name, for tests and debugging.
  final Map<String, double> parts;

  /// The unweighted parts: what [TasteModel] learns from.
  final Map<String, double> features;

  const Recommendation(this.track, this.score, this.reason, this.parts,
      [this.features = const {}]);

  @override
  String toString() =>
      'Recommendation(${track.title}, ${score.toStringAsFixed(3)}, $reason)';
}

/// What the ranker knows about the user, built from on-device data only.
class UserTaste {
  /// Artist key → 0..1, from plays, completions and likes, recent ones
  /// counting more.
  final Map<String, double> artistAffinity;

  /// Artist key → 0..0.3, from repeated early skips across several tracks.
  final Map<String, double> artistSkipPenalty;

  /// Tracks skipped early at least twice and more often than played.
  final Set<String> dislikedIds;

  /// Song keys the user marked "never suggest" (the minus button).
  final Set<String> blockedSongKeys;

  /// The last 50 plays: not suggested again yet.
  final Set<String> recentIds;
  final Set<String> recentSongKeys;

  /// Everything played before, for the "new to you" part.
  final Set<String> heardIds;
  final Set<String> heardSongKeys;

  /// The writing system of at least 70% of recent titles (min. 5), if any.
  final String? dominantScript;

  /// Languages learned from what the user plays; empty = no preference
  /// (script is used).
  final Set<SongLanguage> languages;

  /// Share of each language in the user's songs (developer page).
  final Map<SongLanguage, double> languageShares;

  /// Language and mood of a track (see song_card.dart).
  final SongCardReader? cards;

  /// The user plays devotional songs themselves, so they may be suggested
  /// after other songs too.
  final bool devotionalOk;

  /// Liked songs, then the user's playlists: autoplay's last resort.
  final List<Track> library;

  /// Weights learned from this listener (Layer 2); null = Layer 1's.
  final TasteModel? model;

  const UserTaste({
    this.artistAffinity = const {},
    this.artistSkipPenalty = const {},
    this.dislikedIds = const {},
    this.blockedSongKeys = const {},
    this.recentIds = const {},
    this.recentSongKeys = const {},
    this.heardIds = const {},
    this.heardSongKeys = const {},
    this.dominantScript,
    this.languages = const {},
    this.languageShares = const {},
    this.cards,
    this.devotionalOk = false,
    this.library = const [],
    this.model,
  });

  static const empty = UserTaste();
}

// The weights of the score parts are TasteModel.prior until the listener's
// own are learned (taste.model).

const int kMaxPerArtist = 2;

/// When the pool can't fill a batch at [kMaxPerArtist] (e.g. a JioSaavn
/// radio that is mostly one composer), allow this many rather than starve.
const int kMaxPerArtistThin = 3;
const int kRecentPlays = 50;
const Duration _affinityHalfLife = Duration(days: 30);

// Versions only suggested when the seed is that version too.
const _unwantedTags = {
  'live',
  'karaoke',
  'instrumental',
  'remix',
  'cover',
  'demo'
};
final _alteredAudio = RegExp(
    r'\b(sped up|speed up|slowed|reverb|nightcore|8d audio|8d)\b',
    caseSensitive: false);

class RecommendationRanker {
  /// Supplies text normalization, version tags and duration similarity.
  final CrossPluginResolver matcher;

  const RecommendationRanker(this.matcher);

  static final _dashSuffix = RegExp(r'\s[-\u2013\u2014]\s.*$');

  /// The title without version noise: "(From ...)", "feat.", and anything
  /// after " - " ("Tera Mera Rishta - New Version").
  String titleKey(Track t) =>
      matcher.simplifyTitle(t.title.replaceFirst(_dashSuffix, ''));

  /// Same song across plugins and versions: simplified title + primary artist.
  String songKey(Track t) {
    final artist = t.artists.isEmpty ? '' : t.artists.first.name;
    return '${matcher.simplifyTitle(t.title)}|${matcher.normalized(artist)}';
  }

  /// [signals] from TrackSignalDAO, [liked] tracks, [history] newest first,
  /// [blocked] song keys from the never-suggest list, [playlists] the user's
  /// own playlists by name. [languages] is learned from all of these unless
  /// given (tests).
  UserTaste buildTaste({
    required List<TrackSignal> signals,
    required List<Track> liked,
    required List<Track> history,
    Set<String> blocked = const {},
    Set<SongLanguage> languages = const {},
    Map<String, List<Track>> playlists = const {},
    TasteModel? model,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    double decay(DateTime? t) {
      if (t == null) return 0.5;
      final age = at.difference(t).inHours / _affinityHalfLife.inHours;
      return math.pow(0.5, math.max(0, age)).toDouble();
    }

    final raw = <String, double>{};
    final skips = <String, int>{};
    final skippedTracks = <String, int>{};
    final disliked = <String>{};
    final heardIds = <String>{};
    for (final s in signals) {
      if (s.artistKey.isNotEmpty) {
        raw[s.artistKey] = (raw[s.artistKey] ?? 0) +
            (s.plays + 0.5 * s.completions) * decay(s.lastPlayedAt);
        if (s.earlySkips > 0) {
          skips[s.artistKey] = (skips[s.artistKey] ?? 0) + s.earlySkips;
          skippedTracks[s.artistKey] = (skippedTracks[s.artistKey] ?? 0) + 1;
        }
      }
      if (s.earlySkips >= 2 && s.earlySkips > s.plays) disliked.add(s.mediaId);
      if (s.plays > 0) heardIds.add(s.mediaId);
    }
    for (final t in liked) {
      for (final a in t.artists.take(1)) {
        final k = artistKeyOf(a.name);
        if (k.isNotEmpty) raw[k] = (raw[k] ?? 0) + 3;
      }
    }
    // Cold start: the artists the user put in their own playlists, so a new
    // install with imported playlists isn't a blank slate.
    for (final p in playlists.values) {
      for (final t in p) {
        for (final a in t.artists.take(1)) {
          final k = artistKeyOf(a.name);
          if (k.isNotEmpty) raw[k] = (raw[k] ?? 0) + 0.25;
        }
      }
    }

    final affinity = {
      for (final e in raw.entries) e.key: 1 - math.exp(-e.value / 6),
    };
    // One skip never counts against an artist; a pattern does, less so for
    // artists the user otherwise plays a lot.
    final penalty = <String, double>{};
    for (final e in skips.entries) {
      if (e.value >= 3 && (skippedTracks[e.key] ?? 0) >= 2) {
        penalty[e.key] =
            math.min(0.3, 0.05 * e.value) * (1 - (affinity[e.key] ?? 0));
      }
    }

    final recent = history.take(kRecentPlays);
    final scripts = <String, int>{};
    for (final t in history.take(200)) {
      final s = scriptOf(t.title);
      if (s != null) scripts[s] = (scripts[s] ?? 0) + 1;
    }
    final scriptTotal = scripts.values.fold<int>(0, (a, b) => a + b);
    String? dominant;
    if (scriptTotal >= 5) {
      final top = scripts.entries.reduce((a, b) => b.value > a.value ? b : a);
      if (top.value / scriptTotal >= 0.7) dominant = top.key;
    }

    // Songs inherit the moods of the playlists they are in.
    final playlistMoods = <String, Set<Mood>>{};
    for (final e in playlists.entries) {
      final moods = moodsOfPlaylistName(e.key);
      if (moods.isEmpty) continue;
      for (final t in e.value) {
        playlistMoods.putIfAbsent(songKey(t), () => {}).addAll(moods);
      }
    }
    final own = [
      ...history,
      ...liked,
      for (final p in playlists.values) ...p,
    ];
    final devotional = own
        .where((t) => moodsOfText('${t.title} ${t.album?.title ?? ''}')
            .contains(Mood.devotional))
        .length;

    final artistLanguages = learnArtistLanguages(own);
    // "Punjabi Hits": its artists are Punjabi, whatever their titles say.
    final strong = strongArtistLanguages(playlists);
    return UserTaste(
      languages: languages.isNotEmpty
          ? languages
          : learnUserLanguages(own, artistLanguages, strongArtists: strong),
      languageShares:
          languageShares(own, artistLanguages, strongArtists: strong).shares,
      cards: SongCardReader(
        artistLanguages: artistLanguages,
        strongArtists: strong,
        playlistMoods: playlistMoods,
        songKey: songKey,
      ),
      devotionalOk: devotional >= 3,
      library: [...liked, for (final p in playlists.values) ...p],
      artistAffinity: affinity,
      artistSkipPenalty: penalty,
      dislikedIds: disliked,
      blockedSongKeys: blocked,
      recentIds: {for (final t in recent) t.id},
      recentSongKeys: {for (final t in recent) songKey(t)},
      heardIds: {...heardIds, for (final t in history) t.id},
      heardSongKeys: {for (final t in history) songKey(t)},
      dominantScript: dominant,
      model: model,
    );
  }

  /// The best [take] candidates to queue after [seed], best first.
  ///
  /// [excludeIds]/[excludeSongKeys]: what's already queued.
  /// [previousArtistKey]: artist of the track the batch will follow, so the
  /// batch doesn't open with the same artist.
  List<Recommendation> rank({
    required Track seed,
    required List<RecCandidate> candidates,
    UserTaste taste = UserTaste.empty,
    Set<String> excludeIds = const {},
    Set<String> excludeSongKeys = const {},
    String? previousArtistKey,
    int take = 5,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    double w(String part) =>
        taste.model?.weight(part) ?? TasteModel.prior[part]!;
    final seedKey = songKey(seed);
    final seedArtists = _artistKeys(seed);
    final seedArtistName = seed.artists.isEmpty ? '' : seed.artists.first.name;
    final seedVersions = _versions(seed);
    final seedTitle = titleKey(seed);
    final seedCard = taste.cards?.read(seed);
    final languages = {
      ...taste.languages,
      if (taste.languages.isNotEmpty && seedCard?.language != null)
        seedCard!.language!,
    };
    final devotionalOk = taste.devotionalOk ||
        (seedCard?.moods.contains(Mood.devotional) ?? false);

    // Merge the same song from several sources, keeping first-seen order:
    // same title and at least one shared artist (re-releases list their
    // artists in a different order).
    final merged = <_Merged>[];
    final byTitle = <String, List<_Merged>>{};
    for (final c in candidates) {
      if (c.track.title.trim().isEmpty) continue;
      final artists = _artistKeys(c.track);
      final group = byTitle.putIfAbsent(titleKey(c.track), () => []);
      final m = group.firstWhere(
          (g) =>
              g.artists.isEmpty ||
              artists.isEmpty ||
              g.artists.intersection(artists).isNotEmpty, orElse: () {
        final n = _Merged(c.track, songKey(c.track), artists);
        group.add(n);
        merged.add(n);
        return n;
      });
      m.add(c);
    }

    final scored = <_Scored>[];
    for (final m in merged) {
      final t = m.track;
      final card = taste.cards?.read(t);
      if (m.key == seedKey ||
          // The seed's song again: a re-release, or a cover of it.
          (seedTitle.isNotEmpty && titleKey(t) == seedTitle) ||
          (!devotionalOk && (card?.moods.contains(Mood.devotional) ?? false)) ||
          excludeIds.contains(t.id) ||
          excludeSongKeys.contains(m.key) ||
          taste.recentIds.contains(t.id) ||
          taste.recentSongKeys.contains(m.key) ||
          taste.dislikedIds.contains(t.id) ||
          taste.blockedSongKeys.contains(m.key) ||
          _versions(t).difference(seedVersions).isNotEmpty) {
        continue;
      }

      final artists = m.artists;
      final primary =
          t.artists.isEmpty ? '' : artistKeyOf(t.artists.first.name);
      final sharesSeedArtist = artists.intersection(seedArtists).isNotEmpty;

      final positional = 1 - math.min(m.bestRank, 20) / 20;
      final source = 0.6 * positional + (m.sources.length >= 2 ? 0.4 : 0);
      final affinity = artists
          .map((a) => taste.artistAffinity[a] ?? 0.0)
          .fold<double>(0, math.max);
      final seedLink = sharesSeedArtist
          ? 1.0
          : m.sources.contains(RecSource.relatedArtist)
              ? 0.7
              : 0.5;
      final duration =
          matcher.durationSimilarity(seed.durationMs, t.durationMs);
      // Language: the listener's languages when set and known, else the
      // script of what they usually play.
      final lang = card?.language;
      final double languagePart;
      var foreign = 0.0;
      if (languages.isNotEmpty && lang != null) {
        // Same language: a little extra for the script they usually see
        // (a Devanagari reader gets "तेरी मिट्टी" before "Teri Mitti").
        final dominant = taste.dominantScript;
        final script = scriptOf(t.title);
        languagePart = !languages.contains(lang)
            ? 0.0
            : (dominant != null && script != null && script != dominant
                ? 0.9
                : 1.0);
        if (languagePart == 0) foreign = 1;
      } else {
        final dominant = taste.dominantScript;
        final script = scriptOf(t.title);
        languagePart = dominant == null || script == null
            ? 0.5
            : (script == dominant ? 1.0 : 0.0);
      }
      final seedMoods = seedCard?.moods ?? const <Mood>{};
      final moods = card?.moods ?? const <Mood>{};
      final moodPart = seedMoods.isEmpty || moods.isEmpty
          ? 0.5
          : (seedMoods.intersection(moods).isNotEmpty ? 1.0 : 0.2);
      final novelty =
          taste.heardIds.contains(t.id) || taste.heardSongKeys.contains(m.key)
              ? 0.0
              : 1.0;
      final penalty = taste.artistSkipPenalty[primary] ?? 0.0;
      final timeMood = taste.model?.timeMood(moods, at) ?? 0.5;

      final features = {
        'source': source,
        'affinity': affinity,
        'seedLink': seedLink,
        'duration': duration,
        'language': languagePart,
        'mood': moodPart,
        'novelty': novelty,
        'timeMood': timeMood,
        'skipPenalty': penalty,
        'foreign': foreign,
      };
      final parts = {
        for (final e in features.entries) e.key: w(e.key) * e.value,
      };
      final score = parts.values.fold<double>(0, (a, b) => a + b);

      // The reason shown is the part that lifted this song most, by the
      // listener's own (learned) weights, so it changes as JARX learns.
      final options = <(double, RecReason)>[
        if (affinity >= 0.3 && t.artists.isNotEmpty)
          (
            w('affinity') * affinity,
            RecReason(RecReasonKind.youOftenPlay, t.artists.first.name)
          ),
        if (sharesSeedArtist && seedArtistName.isNotEmpty)
          (
            w('seedLink') * 0.5,
            RecReason(RecReasonKind.moreFrom, seedArtistName)
          ),
        if (!sharesSeedArtist &&
            m.sources.contains(RecSource.relatedArtist) &&
            seedArtistName.isNotEmpty)
          (
            w('seedLink') * 0.2,
            RecReason(RecReasonKind.similarTo, seedArtistName)
          ),
        if (m.sources.length >= 2)
          (
            w('source') * 0.1,
            RecReason(RecReasonKind.foundOnSources, '${m.sources.length}')
          ),
        // Only worth saying when the listener plays several languages.
        if (taste.languages.length >= 2 &&
            lang != null &&
            lang != SongLanguage.other &&
            languagePart > 0.5)
          (
            w('language') * (languagePart - 0.5),
            RecReason(RecReasonKind.inLanguage, lang.name)
          ),
        if (moodPart == 1.0)
          (
            w('mood') * 0.5,
            RecReason(RecReasonKind.sameMood,
                seedMoods.intersection(moods).first.name)
          ),
        if (timeMood > 0.6)
          (
            w('timeMood') * (timeMood - 0.5),
            RecReason(RecReasonKind.timeOfDay,
                taste.model?.slotMood(moods, at)?.name ?? moods.first.name)
          ),
      ];
      final best = options.isEmpty
          ? null
          : options.reduce((a, b) => b.$1 > a.$1 ? b : a);
      final reason = best != null && best.$1 > 0.01
          ? best.$2
          : RecReason(RecReasonKind.becausePlaying, seed.title);

      scored.add(
          _Scored(Recommendation(t, score, reason, parts, features), primary));
    }

    // Stable sort: ties keep the sources' order.
    final order = List<int>.generate(scored.length, (i) => i)
      ..sort((a, b) {
        final c = scored[b].rec.score.compareTo(scored[a].rec.score);
        return c != 0 ? c : a.compareTo(b);
      });
    final remaining = [for (final i in order) scored[i]];
    return _diversify(remaining, take, previousArtistKey);
  }

  /// At most [kMaxPerArtist] per artist per batch ([kMaxPerArtistThin] when
  /// the pool can't fill it otherwise), and not the same artist twice in a
  /// row unless nothing else is left.
  List<Recommendation> _diversify(
      List<_Scored> remaining, int take, String? previousArtistKey) {
    final picked = <Recommendation>[];
    final perArtist = <String, int>{};
    var prev = previousArtistKey;
    var cap = kMaxPerArtist;
    bool underCap(_Scored s) =>
        s.artist.isEmpty || (perArtist[s.artist] ?? 0) < cap;

    while (picked.length < take && remaining.isNotEmpty) {
      var i = remaining.indexWhere(
          (s) => underCap(s) && (s.artist.isEmpty || s.artist != prev));
      if (i < 0) i = remaining.indexWhere(underCap);
      if (i < 0 && cap < kMaxPerArtistThin) {
        cap = kMaxPerArtistThin;
        continue;
      }
      if (i < 0) break;
      final s = remaining.removeAt(i);
      picked.add(s.rec);
      if (s.artist.isNotEmpty) {
        perArtist[s.artist] = (perArtist[s.artist] ?? 0) + 1;
      }
      prev = s.artist;
    }
    return picked;
  }

  Set<String> _versions(Track t) {
    final text = [t.title, t.album?.title ?? ''].join(' ');
    return {
      ...matcher.versionTags(text).intersection(_unwantedTags),
      if (_alteredAudio.hasMatch(text)) 'altered',
    };
  }
}

Set<String> _artistKeys(Track t) =>
    {for (final a in t.artists) artistKeyOf(a.name)}..remove('');

class _Merged {
  final Track track;
  final String key;
  final Set<String> artists;
  final Set<RecSource> sources = {};
  int bestRank = 1 << 30;

  _Merged(this.track, this.key, this.artists);

  void add(RecCandidate c) {
    sources.add(c.source);
    bestRank = math.min(bestRank, c.rank);
  }
}

class _Scored {
  final Recommendation rec;
  final String artist;
  const _Scored(this.rec, this.artist);
}

/// The main writing system of [text]'s letters, or null if it has none.
/// Han and kana count together as "cjk".
String? scriptOf(String text) {
  final counts = <String, int>{};
  for (final r in text.runes) {
    final s = _scriptOfRune(r);
    if (s != null) counts[s] = (counts[s] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

String? _scriptOfRune(int r) {
  if ((r >= 0x41 && r <= 0x5A) ||
      (r >= 0x61 && r <= 0x7A) ||
      (r >= 0xC0 && r <= 0x24F)) {
    return 'latin';
  }
  if (r >= 0x0400 && r <= 0x04FF) return 'cyrillic';
  if (r >= 0x0600 && r <= 0x06FF) return 'arabic';
  if (r >= 0x0900 && r <= 0x097F) return 'devanagari';
  if (r >= 0x0980 && r <= 0x09FF) return 'bengali';
  if (r >= 0x0A00 && r <= 0x0A7F) return 'gurmukhi';
  if (r >= 0x0A80 && r <= 0x0AFF) return 'gujarati';
  if (r >= 0x0B80 && r <= 0x0BFF) return 'tamil';
  if (r >= 0x0C00 && r <= 0x0C7F) return 'telugu';
  if (r >= 0x0C80 && r <= 0x0CFF) return 'kannada';
  if (r >= 0x0D00 && r <= 0x0D7F) return 'malayalam';
  if ((r >= 0xAC00 && r <= 0xD7AF) || (r >= 0x1100 && r <= 0x11FF)) {
    return 'hangul';
  }
  if ((r >= 0x3040 && r <= 0x30FF) || (r >= 0x4E00 && r <= 0x9FFF)) {
    return 'cjk';
  }
  return null;
}
