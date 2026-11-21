// Listening time, for V2's "Your corner": how long the listener has played
// music in total, per artist and per song, and how many times each song was
// played. Only time actually played counts: jumps (seeks) and pauses don't.
// Saved every 15 s and on each song change, in one small setting on the phone.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/core/models/track_signal.dart' show artistKeyOf;
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/player/player_engine.dart';

typedef SongStat = ({String title, String artist, int plays, int ms});

/// "2026-11" for any day in November 2026: the key of a month's counts.
String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Months of counts kept (enough for a whole year's recap, and the year
/// before it); older months are dropped when a new one starts.
const keptMonths = 24;

/// What was counted since [since]: total, per artist and per song, and the
/// same per calendar month in [months]. The maps are hash maps keyed by
/// artist key / song id / month, so adding to a count is instant at any
/// size; top-N lists just sort the values.
class ListeningStats {
  ListeningStats(this.since, this.totalMs, this.artists,
      [Map<String, SongStat>? songs, Map<String, ListeningStats>? months])
      : songs = songs ?? {},
        months = months ?? {};
  final DateTime since;
  int totalMs;

  /// Month key ([monthKey]) -> that month's counts (their own [months] is
  /// empty).
  final Map<String, ListeningStats> months;

  /// Artist key -> (name, ms).
  final Map<String, ({String name, int ms})> artists;

  /// Song id -> (title, artist, plays, ms).
  final Map<String, SongStat> songs;

  Map<String, dynamic> toJson() => {
        'since': since.toIso8601String(),
        'totalMs': totalMs,
        'artists': {
          for (final e in artists.entries)
            e.key: {'n': e.value.name, 'ms': e.value.ms}
        },
        'songs': {
          for (final e in songs.entries)
            e.key: {
              't': e.value.title,
              'a': e.value.artist,
              'p': e.value.plays,
              'ms': e.value.ms,
            }
        },
        if (months.isNotEmpty)
          'months': {for (final e in months.entries) e.key: e.value.toJson()},
      };

  static int _int(Object? v) => (v as num? ?? 0).toInt();

  static ListeningStats fromJson(Map j) {
    final stats = _fromJson(j);
    final months = j['months'];
    if (months is Map) {
      for (final e in months.entries) {
        if (e.value is Map) stats.months['${e.key}'] = _fromJson(e.value);
      }
    } else if (stats.totalMs > 0) {
      // Saved before months were kept (builds 34-41, from 13 Nov 2026):
      // everything so far goes to the month counting started in.
      stats.months[monthKey(stats.since)] = _fromJson(j);
    }
    return stats;
  }

  static ListeningStats _fromJson(Map j) => ListeningStats(
        DateTime.tryParse(j['since']?.toString() ?? '') ?? DateTime.now(),
        _int(j['totalMs']),
        {
          for (final e in (j['artists'] as Map? ?? const {}).entries)
            e.key as String: (
              name: (e.value as Map)['n']?.toString() ?? '',
              ms: _int((e.value as Map)['ms']),
            ),
        },
        {
          for (final e in (j['songs'] as Map? ?? const {}).entries)
            e.key as String: (
              title: (e.value as Map)['t']?.toString() ?? '',
              artist: (e.value as Map)['a']?.toString() ?? '',
              plays: _int((e.value as Map)['p']),
              ms: _int((e.value as Map)['ms']),
            ),
        },
      );

  /// Adds [o] (another phone's counts) into this record.
  void add(ListeningStats o) {
    for (final e in o.months.entries) {
      (months[e.key] ??= ListeningStats(e.value.since, 0, {})).add(e.value);
    }
    totalMs += o.totalMs;
    for (final e in o.artists.entries) {
      final mine = artists[e.key];
      artists[e.key] =
          (name: e.value.name, ms: (mine?.ms ?? 0) + e.value.ms);
    }
    for (final e in o.songs.entries) {
      final mine = songs[e.key];
      songs[e.key] = (
        title: e.value.title,
        artist: e.value.artist,
        plays: (mine?.plays ?? 0) + e.value.plays,
        ms: (mine?.ms ?? 0) + e.value.ms,
      );
    }
  }

  /// Counts [ms] and [plays] of [track] by [artist] here.
  void count(String trackId, String title, String artist, int ms, int plays) {
    totalMs += ms;
    final key = artistKeyOf(artist);
    if (key.isNotEmpty) {
      final old = artists[key];
      artists[key] = (name: artist, ms: (old?.ms ?? 0) + ms);
    }
    final song = songs[trackId];
    songs[trackId] = (
      title: title,
      artist: artist,
      plays: (song?.plays ?? 0) + plays,
      ms: (song?.ms ?? 0) + ms,
    );
  }

  /// Counts into the totals and into [now]'s month; months beyond
  /// [keptMonths] are dropped, oldest first.
  void countNow(DateTime now, String trackId, String title, String artist,
      int ms, int plays) {
    count(trackId, title, artist, ms, plays);
    final month = monthKey(now);
    (months[month] ??= ListeningStats(DateTime(now.year, now.month), 0, {}))
        .count(trackId, title, artist, ms, plays);
    if (months.length > keptMonths) {
      final keys = months.keys.toList()..sort();
      for (final k in keys.take(months.length - keptMonths)) {
        months.remove(k);
      }
    }
  }

  /// The [n] artists listened to longest.
  List<({String name, int ms})> topArtists(int n) =>
      (artists.values.toList()..sort((x, y) => y.ms.compareTo(x.ms)))
          .take(n)
          .toList();

  /// The [n] songs played most (by plays, then by time).
  List<SongStat> topSongs(int n) {
    final all = songs.values.toList()
      ..sort((x, y) => y.plays != x.plays
          ? y.plays.compareTo(x.plays)
          : y.ms.compareTo(x.ms));
    return all.take(n).toList();
  }
}

/// How much of the gap between two position updates was really played:
/// the position moved forward by about the time that passed. A bigger jump
/// is a seek, a backwards move is a replay/seek: neither counts.
int playedBetween(int lastPosMs, int posMs, int wallMs) {
  final moved = posMs - lastPosMs;
  if (moved <= 0 || moved > wallMs + 1000) return 0;
  return moved;
}

/// A song counts as played once 30 s of it were really heard, or half of it
/// when it is shorter than a minute.
bool countsAsPlay(int heardMs, int? durationMs) {
  final need = (durationMs == null || durationMs <= 0)
      ? 30000
      : (durationMs ~/ 2).clamp(1, 30000);
  return heardMs >= need;
}

/// The song started again from the beginning (repeat-one, or replayed by
/// hand): the position fell back near the start from well into the song.
bool restarted(int lastPosMs, int posMs) => posMs < 3000 && lastPosMs > 10000;

class ListeningTime {
  ListeningTime(this._engine, this._currentTrack) {
    _sub = _engine.positionStream.listen(_tick);
  }

  static const _key = 'listeningTime1';
  static const _flushEveryMs = 15000;

  final PlayerEngine _engine;
  final Track? Function() _currentTrack;
  StreamSubscription<Duration>? _sub;

  String? _trackId;
  Track? _track;
  int? _lastPos;
  int? _lastWall;
  int _pendingMs = 0;

  /// Time heard of the current play of this song, and whether that play
  /// was counted yet (and is waiting to be saved).
  int _heardMs = 0;
  bool _counted = false;
  int _pendingPlays = 0;

  void _startPlay() {
    _heardMs = 0;
    _counted = false;
  }

  void _tick(Duration position) {
    final track = _currentTrack();
    final now = DateTime.now().millisecondsSinceEpoch;
    final pos = position.inMilliseconds;
    if (track == null || !_engine.playing) {
      _lastPos = null;
      return;
    }
    if (track.id != _trackId) {
      unawaited(_flush());
      _trackId = track.id;
      _track = track;
      _startPlay();
      _lastPos = pos;
      _lastWall = now;
      return;
    }
    if (_lastPos != null && _lastWall != null) {
      if (restarted(_lastPos!, pos)) _startPlay();
      final played = playedBetween(_lastPos!, pos, now - _lastWall!);
      _pendingMs += played;
      _heardMs += played;
      if (!_counted && countsAsPlay(_heardMs, track.durationMs?.toInt())) {
        _counted = true;
        _pendingPlays++;
      }
    }
    _lastPos = pos;
    _lastWall = now;
    if (_pendingMs >= _flushEveryMs) unawaited(_flush());
  }

  Future<void> _flush() async {
    final ms = _pendingMs;
    final plays = _pendingPlays;
    final track = _track;
    _pendingMs = 0;
    _pendingPlays = 0;
    if ((ms <= 0 && plays <= 0) || track == null) return;
    try {
      final stats = await load();
      final artist =
          track.artists.isEmpty ? '' : track.artists.first.name.trim();
      stats.countNow(DateTime.now(), track.id, track.title, artist, ms, plays);
      await SettingsDAO(DBProvider.db)
          .putSettingStr(_key, jsonEncode(stats.toJson()));
    } catch (e) {
      log('Saving listening time failed: $e', name: 'ListeningTime');
    }
  }

  /// The user's other phones' records (sync), by phone.
  static const _othersKey = 'listeningOthers1';

  static Future<Map<String, dynamic>> otherPhones() async {
    try {
      final raw = await SettingsDAO(DBProvider.db).getSettingStr(_othersKey);
      if (raw != null) return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {}
    return {};
  }

  static Future<void> saveOtherPhones(Map<String, dynamic> others) =>
      SettingsDAO(DBProvider.db).putSettingStr(_othersKey, jsonEncode(others));

  /// This phone's counts plus the user's other phones'.
  static Future<ListeningStats> loadAllPhones() async {
    final all = await load();
    for (final o in (await otherPhones()).values) {
      try {
        all.add(ListeningStats.fromJson(o as Map));
      } catch (_) {}
    }
    return all;
  }

  /// Everything counted so far (an empty record from today when nothing).
  static Future<ListeningStats> load() async {
    try {
      final raw = await SettingsDAO(DBProvider.db).getSettingStr(_key);
      if (raw != null) return ListeningStats.fromJson(jsonDecode(raw) as Map);
    } catch (_) {}
    return ListeningStats(DateTime.now(), 0, {});
  }

  Future<void> dispose() async {
    await _flush();
    await _sub?.cancel();
  }
}
