// First-time tips: a bubble that points at a button the first time it
// matters. Rules: each tip shows once, one at a time, at most 3 a day, and
// only for people who set JARX up with the first-run flow (build 42+).
// Which tip, where: [tipTexts]; the widgets are in tip_overlay.dart.

import 'dart:convert';

import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';

/// Tip id -> text, in priority order (when two could show, the earlier).
const tipTexts = <String, String>{
  'T14':
      "Tap your photo for Your corner: your top 5 artists this month and how long you've listened.",
  'A1': 'Tap ⊖ on a song to never see it again.',
  'T16': 'Updates and news land here. JARX installs updates for you.',
  'A2': "Try Smart shuffle: your playlist plus new songs you'll like.",
  'T10': 'Download the whole playlist and listen without internet.',
  'T11':
      'Saving mobile data? Set downloads to Wi-Fi only in Settings › Downloads.',
  'T9':
      'Searching YouTube Music. Switch to YouTube Video for songs with music videos.',
  'A3': 'Swipe a song to queue it.',
  'T6': 'Tap ⋮ for more: play next, add to a playlist, download and more.',
  'T7': 'Queued songs play right after this one, in the order you added them.',
  'T8':
      'Not your vibe? Tap ⊖ and JARX learns. It never plays that song for you again.',
  'A4': 'Play video is here. Watch the music video right in the player.',
  'T2': 'Falling asleep to music? Set a sleep timer and JARX stops by itself.',
  'T4':
      'Lyrics running late? Tap ⋮ › Sync lyrics, then tap a line the moment you hear it.',
  'T5': 'Captions are here. Pick the language and size in settings.',
  'T17': 'Bored of Home? Switch to another layout here.',
};

/// Tips that wait until something happened N times (e.g. T2: the second
/// time the full player opens).
const tipNeeds = <String, (String, int)>{'T2': ('player', 2)};

const tipsPerDay = 3;

/// What the user has seen; saved as one small setting.
class TipBook {
  TipBook({
    this.enabled = false,
    Set<String>? shown,
    this.day = '',
    this.today = 0,
    Map<String, int>? counts,
  })  : shown = shown ?? {},
        counts = counts ?? {};

  /// Only new users (set by the first-run flow, or "Show tips again").
  bool enabled;
  final Set<String> shown;
  String day;
  int today;
  final Map<String, int> counts;

  static String dayOf(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// The tip to show now out of [offered], or null.
  String? pick(Iterable<String> offered, DateTime now) {
    if (!enabled) return null;
    if (day == dayOf(now) && today >= tipsPerDay) return null;
    for (final id in tipTexts.keys) {
      if (!offered.contains(id) || shown.contains(id)) continue;
      final need = tipNeeds[id];
      if (need != null && (counts[need.$1] ?? 0) < need.$2) continue;
      return id;
    }
    return null;
  }

  void markShown(String id, DateTime now) {
    shown.add(id);
    final d = dayOf(now);
    if (day != d) {
      day = d;
      today = 0;
    }
    today++;
  }

  Map<String, dynamic> toJson() => {
        'on': enabled,
        'shown': shown.toList(),
        'day': day,
        'today': today,
        'counts': counts,
      };

  static TipBook fromJson(Map j) => TipBook(
        enabled: j['on'] == true,
        shown: {for (final s in j['shown'] as List? ?? const []) '$s'},
        day: '${j['day'] ?? ''}',
        today: (j['today'] as num? ?? 0).toInt(),
        counts: {
          for (final e in (j['counts'] as Map? ?? const {}).entries)
            '${e.key}': (e.value as num).toInt()
        },
      );
}

class TipStore {
  static const _key = 'tips1';
  static TipBook? _book;

  static Future<TipBook> load() async {
    if (_book != null) return _book!;
    try {
      final raw = await SettingsDAO(DBProvider.db).getSettingStr(_key);
      if (raw != null) return _book = TipBook.fromJson(jsonDecode(raw) as Map);
    } catch (_) {}
    return _book = TipBook();
  }

  static Future<void> save() async {
    final b = _book;
    if (b == null) return;
    await SettingsDAO(DBProvider.db)
        .putSettingStr(_key, jsonEncode(b.toJson()));
  }

  /// [what] happened once more (e.g. 'player' opened).
  static Future<void> bump(String what) async {
    final b = await load();
    b.counts[what] = (b.counts[what] ?? 0) + 1;
    await save();
  }

  /// Turns tips on from the start (first-run done, or "Show tips again").
  static Future<void> startOver() async {
    _book = TipBook(enabled: true);
    await save();
  }
}
