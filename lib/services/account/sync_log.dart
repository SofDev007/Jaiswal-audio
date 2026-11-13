// When songs were put into or taken out of playlists, and when playlists were
// deleted, on this phone. Sync needs these times so a removal on one phone
// isn't undone by the other phone's copy (see sync_merge.dart).

import 'dart:convert';
import 'dart:developer';

import 'package:Bloomee/plugins/utils/media_id.dart' show isLocalMediaId;
import 'package:Bloomee/services/account/sync_merge.dart' show syncKeepMs;
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';

class SyncLog {
  static const _key = 'syncLog1';

  /// Playlists that never sync: downloads, history, local files.
  static const _notSynced = {'_DOWNLOADS', 'recently_played', '_LOCAL_MUSIC'};
  static bool syncs(String name) =>
      name.trim().isNotEmpty && !_notSynced.contains(name);

  /// True while sync itself changes playlists: those aren't the user's edits.
  static bool muted = false;

  static Future<Map<String, dynamic>> read() async {
    try {
      final raw = await SettingsDAO(DBProvider.db).getSettingStr(_key);
      if (raw != null) return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (e) {
      log('Sync log unreadable: $e', name: 'SyncLog');
    }
    return {'x': {}, 'r': {}, 'a': {}};
  }

  static Future<void> write(Map<String, dynamic> logMap) =>
      SettingsDAO(DBProvider.db).putSettingStr(_key, jsonEncode(logMap));

  /// One write at a time, so quick edits don't overwrite each other's notes.
  static Future<void> _queue = Future.value();

  static Future<void> _note(String part, String name, Iterable<String> ids) {
    if (muted || !syncs(name)) return Future.value();
    final list = ids.toList();
    return _queue = _queue
        .then((_) => _write(part, name, list))
        .catchError((Object e) => log('Sync log: $e', name: 'SyncLog'));
  }

  static Future<void> _write(String part, String name, List<String> ids) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final logMap = await read();
    if (part == 'x') {
      (logMap['x'] as Map)[name] = now;
    } else {
      final m = ((logMap[part] as Map)[name] ??= <String, dynamic>{}) as Map;
      for (final id in ids) {
        if (!isLocalMediaId(id)) m[id] = now;
      }
    }
    // Forget what can no longer matter.
    final oldest = now - syncKeepMs;
    (logMap['x'] as Map).removeWhere((_, t) => (t as num) < oldest);
    for (final p in ['r', 'a']) {
      for (final m in (logMap[p] as Map).values) {
        (m as Map).removeWhere((_, t) => (t as num) < oldest);
      }
      (logMap[p] as Map).removeWhere((_, m) => (m as Map).isEmpty);
    }
    await write(logMap);
  }

  static Future<void> added(String playlist, Iterable<String> ids) =>
      _note('a', playlist, ids);
  static Future<void> removed(String playlist, Iterable<String> ids) =>
      _note('r', playlist, ids);
  static Future<void> deleted(String playlist) => _note('x', playlist, const []);
}
