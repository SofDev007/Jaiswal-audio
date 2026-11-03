import 'dart:convert';

import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';

/// Counters that show whether recommendations work, kept on the phone and
/// shown in Settings > Recommendations, so each build can be compared with
/// the last one.
class RecHealth {
  static const _key = 'recHealth';

  /// Autoplay tried to queue a batch.
  static const refills = 'refills';

  /// ...and nothing came back from any plugin, so the library was used.
  static const libraryRefills = 'libraryRefills';

  /// ...and there was nothing to queue at all.
  static const emptyRefills = 'emptyRefills';

  /// First gathers for a seed, and their total time.
  static const gathers = 'gathers';
  static const gatherMs = 'gatherMs';

  /// Recommended songs that started playing, and those skipped early.
  static const recStarts = 'recStarts';
  static const recEarlySkips = 'recEarlySkips';

  static Future<void> _last = Future.value();

  /// Adds [by] to [counter]. Writes run one after another, so none is lost.
  static Future<void> add(String counter, [int by = 1]) =>
      _last = _last.then((_) async {
        final c = await load();
        c[counter] = (c[counter] ?? 0) + by;
        await SettingsDAO(DBProvider.db).putSettingStr(_key, jsonEncode(c));
      }).catchError((_) {});

  static Future<Map<String, int>> load() async {
    try {
      final raw = await SettingsDAO(DBProvider.db).getSettingStr(_key);
      if (raw == null) return {};
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          e.key as String: (e.value as num).toInt(),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> reset() => _last = _last.then(
      (_) => SettingsDAO(DBProvider.db).putSettingStr(_key, jsonEncode({})));
}
