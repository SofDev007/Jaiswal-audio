// Recommendations Layer 2: JARX learns how much each part of a suggestion's
// score matters to THIS listener, from what they do with suggestions.
//
// A small logistic model over the ranker's score parts (source, artist
// affinity, link to the seed, duration, language, mood, newness, ...),
// updated after every suggested song: played past 20 s or to the end = good,
// skipped in the first 20 s = bad, liked = very good, "Do not suggest" =
// very bad. It starts at Layer 1's fixed weights, so a new listener gets
// Layer 1 exactly, and is gently pulled back towards them so a handful of
// odd skips can't swing it. It also learns which moods the listener plays at
// each time of day (and weekends), as one more score part.
//
// Everything stays on the device (one setting, a few hundred bytes).

import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/recommendations/song_card.dart';

class TasteModel {
  TasteModel._(this.weights, this.bias, this.updates, this.slotMoods);

  /// Layer 1's weights (they summed to 1). Skip penalty and foreign are raw
  /// amounts subtracted from the score.
  static const Map<String, double> prior = {
    'source': 0.27,
    'affinity': 0.22,
    'seedLink': 0.14,
    'duration': 0.08,
    'language': 0.15,
    'mood': 0.07,
    'novelty': 0.07,
    'timeMood': 0.05,
    'skipPenalty': -1.0,
    'foreign': -0.12,
  };

  /// Score parts on Layer 1's scale times this = the model's logit.
  static const double _scale = 6;
  static const double _rate = 0.02;

  /// Pull towards [prior] each update; keeps the model sane on few samples.
  static const double _toPrior = 0.05;

  final Map<String, double> weights; // on the score scale (like [prior])
  double bias;
  int updates;

  /// Time slot (see [_slot]) -> mood name -> plays.
  final Map<int, Map<String, int>> slotMoods;

  static const _key = 'recTasteModel1';
  static TasteModel? _instance;

  /// Features of queued suggestions, until we know how they went.
  static final Map<String, Map<String, double>> _pending = {};

  static Future<TasteModel> load() async {
    final cached = _instance;
    if (cached != null) return cached;
    TasteModel m;
    try {
      final raw = await SettingsDAO(DBProvider.db).getSettingStr(_key);
      m = raw == null ? _fresh() : _decode(jsonDecode(raw) as Map);
    } catch (e) {
      log('Taste model unreadable, starting fresh: $e', name: 'TasteModel');
      m = _fresh();
    }
    return _instance = m;
  }

  /// How much this model has learned: suggestions judged plus plays noted.
  /// Sync keeps the copy (this phone's or the account's) that learned more.
  static int amountOf(Map j) =>
      (j['n'] as num? ?? 0).toInt() +
      [
        for (final slot in (j['t'] as Map? ?? const {}).values)
          for (final n in (slot as Map).values) (n as num).toInt()
      ].fold(0, (a, b) => a + b);

  /// The saved model as JSON (null when nothing learned yet).
  static Future<Map?> savedJson() async {
    final raw = await SettingsDAO(DBProvider.db).getSettingStr(_key);
    return raw == null ? null : jsonDecode(raw) as Map;
  }

  /// Use another phone's model (it learned more than this one).
  static Future<void> adopt(Map j) async {
    await SettingsDAO(DBProvider.db).putSettingStr(_key, jsonEncode(j));
    _instance = null;
  }

  static TasteModel _fresh() =>
      TasteModel._(Map.of(prior), 0, 0, <int, Map<String, int>>{});

  /// For tests.
  static TasteModel fresh() => _fresh();

  /// The weight of score part [name].
  double weight(String name) => weights[name] ?? prior[name] ?? 0;

  /// Chance (0..1) the listener keeps this suggestion playing.
  double predict(Map<String, double> x) => _sigmoid(_logit(x));

  double _logit(Map<String, double> x) {
    var z = bias;
    for (final e in x.entries) {
      z += _scale * weight(e.key) * e.value;
    }
    // Centre: a Layer 1 score of ~0.5 is a coin flip at the start.
    return z - _scale * 0.5;
  }

  /// One outcome: [good] or not, [strength] 1 for a play/skip, more for a
  /// like or "Do not suggest".
  void learn(Map<String, double> x, {required bool good, double strength = 1}) {
    final err = (good ? 1.0 : 0.0) - predict(x);
    for (final k in prior.keys) {
      final w = weight(k);
      weights[k] = (w +
              _rate * (strength * err * (x[k] ?? 0) - _toPrior * (w - prior[k]!)))
          .clamp(-1.0, 1.0);
    }
    bias = (bias + _rate * strength * err).clamp(-2.0, 2.0);
    updates++;
  }

  // ── Time of day ─────────────────────────────────────────────────────────

  /// 0 night (0-5), 1 morning (5-12), 2 afternoon (12-17), 3 evening
  /// (17-24); +4 on weekends.
  static int _slot(DateTime t) {
    final h = t.hour;
    final part = h < 5
        ? 0
        : h < 12
            ? 1
            : h < 17
                ? 2
                : 3;
    final weekend =
        t.weekday == DateTime.saturday || t.weekday == DateTime.sunday;
    return part + (weekend ? 4 : 0);
  }

  void notePlayMoods(Set<Mood> moods, DateTime at) {
    if (moods.isEmpty) return;
    final m = slotMoods.putIfAbsent(_slot(at), () => {});
    for (final mood in moods) {
      m[mood.name] = (m[mood.name] ?? 0) + 1;
    }
  }

  /// How much [moods] are what the listener plays at [at]'s time of day:
  /// 0..1, 0.5 when there isn't enough to go on.
  double timeMood(Set<Mood> moods, DateTime at) {
    final m = slotMoods[_slot(at)];
    if (m == null || moods.isEmpty) return 0.5;
    final total = m.values.fold<int>(0, (a, b) => a + b);
    if (total < 10) return 0.5;
    final best = moods.map((x) => (m[x.name] ?? 0) / total).fold<double>(0, math.max);
    return math.min(1.0, 0.5 + best * 1.5);
  }

  /// Of [moods], the one the listener plays most at [at]'s time of day.
  Mood? slotMood(Set<Mood> moods, DateTime at) {
    final m = slotMoods[_slot(at)];
    if (m == null || moods.isEmpty) return null;
    return moods.reduce((a, b) => (m[b.name] ?? 0) > (m[a.name] ?? 0) ? b : a);
  }

  // ── Outcomes (called from the player and the menus) ─────────────────────

  /// Remember a queued suggestion's score parts until it is played.
  static void remember(String trackId, Map<String, double> features) {
    _pending[trackId] = features;
    if (_pending.length > 300) _pending.remove(_pending.keys.first);
  }

  /// What each suggestion has already taught, so nothing counts twice.
  static final Map<String, Set<String>> _taught = {};

  /// Learn from how suggestion [trackId] was played: kept past 20 s
  /// ([good]) or skipped early, once. Played again later = a replay, which
  /// counts like a like. Ignored for songs that weren't suggested.
  static Future<void> played(String trackId, {required bool good}) async {
    final x = _pending[trackId];
    if (x == null) return;
    final done = _taught.putIfAbsent(trackId, () => {});
    if (done.contains('kept')) {
      if (good && done.add('replayed')) await _learn(x, true, 2);
      return;
    }
    if (done.contains('skipped')) return;
    done.add(good ? 'kept' : 'skipped');
    await _learn(x, good, 1);
  }

  /// A strong signal about suggestion [trackId], each once: liked or added
  /// to a playlist ([good], strength 2), or "Do not suggest" (strength 3).
  static Future<void> judged(String trackId,
      {required bool good, String how = 'liked'}) async {
    final x = good ? _pending[trackId] : _pending.remove(trackId);
    if (x == null) return;
    final kind = good ? how : 'blocked';
    if (!_taught.putIfAbsent(trackId, () => {}).add(kind)) return;
    await _learn(x, good, good ? 2 : 3);
  }

  static Future<void> _learn(
      Map<String, double> x, bool good, double strength) async {
    final m = await load();
    m.learn(x, good: good, strength: strength);
    await m._save();
  }

  /// A song was played (any song): its moods count for this time slot.
  static Future<void> notePlay(Track t) async {
    final moods = moodsOfText('${t.title} ${t.album?.title ?? ''}');
    if (moods.isEmpty) return;
    final m = await load();
    m.notePlayMoods(moods, DateTime.now());
    await m._save();
  }

  Future<void> _save() async {
    try {
      await SettingsDAO(DBProvider.db).putSettingStr(_key, jsonEncode(_encode()));
    } catch (e) {
      log('Saving taste model failed: $e', name: 'TasteModel');
    }
  }

  Map<String, dynamic> _encode() => {
        'w': weights,
        'b': bias,
        'n': updates,
        't': {
          for (final e in slotMoods.entries) '${e.key}': e.value,
        },
      };

  static TasteModel _decode(Map j) => TasteModel._(
        {
          ...prior,
          for (final e in (j['w'] as Map? ?? const {}).entries)
            e.key as String: (e.value as num).toDouble(),
        },
        (j['b'] as num? ?? 0).toDouble(),
        j['n'] as int? ?? 0,
        {
          for (final e in (j['t'] as Map? ?? const {}).entries)
            int.parse(e.key as String): {
              for (final f in (e.value as Map).entries)
                f.key as String: f.value as int,
            },
        },
      );

  static double _sigmoid(double z) => 1 / (1 + math.exp(-z));
}
