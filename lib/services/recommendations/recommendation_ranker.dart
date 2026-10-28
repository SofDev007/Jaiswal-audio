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

  const Recommendation(this.track, this.score, this.reason, this.parts);

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
  });

  static const empty = UserTaste();
}

// Weights of the score parts. They sum to 1 before the skip penalty.
const double _wSource = 0.30;
const double _wAffinity = 0.25;
const double _wSeedLink = 0.15;
const double _wDuration = 0.10;
const double _wScript = 0.10;
const double _wNovelty = 0.10;

const int kMaxPerArtist = 2;
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

  /// Same song across plugins and versions: simplified title + primary artist.
  String songKey(Track t) {
    final artist = t.artists.isEmpty ? '' : t.artists.first.name;
    return '${matcher.simplifyTitle(t.title)}|${matcher.normalized(artist)}';
  }

  /// [signals] from TrackSignalDAO, [liked] tracks, [history] newest first,
  /// [blocked] song keys from the never-suggest list.
  UserTaste buildTaste({
    required List<TrackSignal> signals,
    required List<Track> liked,
    required List<Track> history,
    Set<String> blocked = const {},
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

    return UserTaste(
      artistAffinity: affinity,
      artistSkipPenalty: penalty,
      dislikedIds: disliked,
      blockedSongKeys: blocked,
      recentIds: {for (final t in recent) t.id},
      recentSongKeys: {for (final t in recent) songKey(t)},
      heardIds: {...heardIds, for (final t in history) t.id},
      heardSongKeys: {for (final t in history) songKey(t)},
      dominantScript: dominant,
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
  }) {
    final seedKey = songKey(seed);
    final seedArtists = {for (final a in seed.artists) artistKeyOf(a.name)}
      ..remove('');
    final seedArtistName = seed.artists.isEmpty ? '' : seed.artists.first.name;
    final seedVersions = _versions(seed);
    final seedTitle = matcher.simplifyTitle(seed.title);

    // Merge the same song from several sources, keeping first-seen order.
    final merged = <String, _Merged>{}; // insertion-ordered
    for (final c in candidates) {
      if (c.track.title.trim().isEmpty) continue;
      final key = songKey(c.track);
      final m = merged[key];
      if (m == null) {
        merged[key] = _Merged(c.track, key)..add(c);
      } else {
        m.add(c);
      }
    }

    final scored = <_Scored>[];
    for (final m in merged.values) {
      final t = m.track;
      if (m.key == seedKey ||
          excludeIds.contains(t.id) ||
          excludeSongKeys.contains(m.key) ||
          taste.recentIds.contains(t.id) ||
          taste.recentSongKeys.contains(m.key) ||
          taste.dislikedIds.contains(t.id) ||
          taste.blockedSongKeys.contains(m.key) ||
          _versions(t).difference(seedVersions).isNotEmpty) {
        continue;
      }

      final artists = {for (final a in t.artists) artistKeyOf(a.name)}
        ..remove('');
      final primary =
          t.artists.isEmpty ? '' : artistKeyOf(t.artists.first.name);
      final sharesSeedArtist = artists.intersection(seedArtists).isNotEmpty;
      // The seed's title by none of its artists: an unlabeled cover.
      if (!sharesSeedArtist &&
          matcher.simplifyTitle(t.title) == seedTitle &&
          seedTitle.isNotEmpty) {
        continue;
      }

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
      final dominant = taste.dominantScript;
      final script = scriptOf(t.title);
      final scriptPart = dominant == null || script == null
          ? 0.5
          : (script == dominant ? 1.0 : 0.0);
      final novelty =
          taste.heardIds.contains(t.id) || taste.heardSongKeys.contains(m.key)
              ? 0.0
              : 1.0;
      final penalty = taste.artistSkipPenalty[primary] ?? 0.0;

      final parts = {
        'source': _wSource * source,
        'affinity': _wAffinity * affinity,
        'seedLink': _wSeedLink * seedLink,
        'duration': _wDuration * duration,
        'script': _wScript * scriptPart,
        'novelty': _wNovelty * novelty,
        'skipPenalty': -penalty,
      };
      final score = parts.values.fold<double>(0, (a, b) => a + b);

      final RecReason reason;
      if (affinity >= 0.5) {
        reason = RecReason(RecReasonKind.youOftenPlay, t.artists.first.name);
      } else if (sharesSeedArtist) {
        reason = RecReason(RecReasonKind.moreFrom, seedArtistName);
      } else if (m.sources.contains(RecSource.relatedArtist) &&
          seedArtistName.isNotEmpty) {
        reason = RecReason(RecReasonKind.similarTo, seedArtistName);
      } else if (m.sources.length >= 2) {
        reason = RecReason(RecReasonKind.foundOnSources, '${m.sources.length}');
      } else {
        reason = RecReason(RecReasonKind.becausePlaying, seed.title);
      }

      scored.add(_Scored(Recommendation(t, score, reason, parts), primary));
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

  /// At most [kMaxPerArtist] per artist per batch, and not the same artist
  /// twice in a row unless nothing else is left.
  List<Recommendation> _diversify(
      List<_Scored> remaining, int take, String? previousArtistKey) {
    final picked = <Recommendation>[];
    final perArtist = <String, int>{};
    var prev = previousArtistKey;
    bool underCap(_Scored s) =>
        s.artist.isEmpty || (perArtist[s.artist] ?? 0) < kMaxPerArtist;

    while (picked.length < take && remaining.isNotEmpty) {
      var i = remaining.indexWhere(
          (s) => underCap(s) && (s.artist.isEmpty || s.artist != prev));
      if (i < 0) i = remaining.indexWhere(underCap);
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

class _Merged {
  final Track track;
  final String key;
  final Set<RecSource> sources = {};
  int bestRank = 1 << 30;

  _Merged(this.track, this.key);

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
