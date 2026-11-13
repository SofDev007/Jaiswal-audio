// Keeps the user's music the same on every phone they sign in on:
// playlists + Liked, the 50 latest plays, what JARX learned (taste), and each
// phone's listening time. Runs after sign-in, 5 s after a change, and every
// 30 min while JARX is open. The rules for combining copies are in
// sync_merge.dart; downloads and local music files never sync.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' show gzip;

import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/plugins/utils/media_id.dart' show isLocalMediaId;
import 'package:Bloomee/services/account/account.dart';
import 'package:Bloomee/services/account/sync_log.dart';
import 'package:Bloomee/services/account/sync_merge.dart';
import 'package:Bloomee/services/db/dao/history_dao.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/db/global_db.dart';
import 'package:Bloomee/services/db/mappers/media_item_mapper.dart';
import 'package:Bloomee/services/player/listening_time.dart';
import 'package:Bloomee/services/plugin_cache_codec.dart';
import 'package:Bloomee/services/recommendations/taste_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';

class Sync {
  Sync._();
  static final instance = Sync._();

  final lastSynced = ValueNotifier<DateTime?>(null);
  final busy = ValueNotifier(false);

  static const _seenKey = 'syncSeen1', _sentKey = 'syncSent1';
  static const _lastKey = 'syncLast1';

  bool _started = false, _again = false;
  Timer? _debounce, _timer;
  final _subs = <StreamSubscription>[];

  /// Per kind: the server's time of the copy this phone has merged, and a
  /// fingerprint of what it last uploaded (so unchanged data isn't sent).
  Map<String, dynamic> _seen = {}, _sent = {};

  SettingsDAO get _settings => SettingsDAO(DBProvider.db);
  PlaylistDAO get _playlists =>
      PlaylistDAO(DBProvider.db, TrackDAO(DBProvider.db));

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _seen = await _readMap(_seenKey);
    _sent = await _readMap(_sentKey);
    final last = int.tryParse(await _settings.getSettingStr(_lastKey) ?? '');
    if (last != null) {
      lastSynced.value = DateTime.fromMillisecondsSinceEpoch(last);
    }
    final isar = await DBProvider.db;
    for (final changes in [
      isar.playlistDBs.watchLazy(),
      isar.playlistEntryDBs.watchLazy(),
      isar.playbackHistoryDBs.watchLazy(),
    ]) {
      _subs.add(changes.listen((_) => schedule()));
    }
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => syncNow());
    unawaited(syncNow());
  }

  /// Signed out: stop, and forget which copies were seen (the next account
  /// starts with a full merge).
  Future<void> stop() async {
    _started = false;
    _debounce?.cancel();
    _timer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _seen = {};
    _sent = {};
    await _settings.putSettingStr(_seenKey, '{}');
    await _settings.putSettingStr(_sentKey, '{}');
  }

  void schedule() {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), syncNow);
  }

  /// Returns a message when it failed.
  Future<String?> syncNow() async {
    if (busy.value) {
      _again = true;
      return null;
    }
    if (!Account.instance.signedIn) return 'Not signed in.';
    busy.value = true;
    try {
      return await _sync();
    } catch (e, st) {
      log('Sync failed: $e\n$st', name: 'Sync');
      return 'Sync failed. It will try again.';
    } finally {
      busy.value = false;
      if (_again) {
        _again = false;
        schedule();
      }
    }
  }

  Future<String?> _sync() async {
    final res = await Account.instance.api('GET', '/sync',
        query: {for (final e in _seen.entries) e.key: '${e.value}'});
    if (res == null || res.statusCode != 200) {
      return 'The JARX server was not reached. It will try again.';
    }
    final remote = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    Object? dataOf(String kind) {
      final r = remote[kind];
      return r is Map && r.containsKey('data') ? unpackSyncData(r['data']) : null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final up = <String, dynamic>{};

    // Playlists + Liked.
    var library = await _readLibrary();
    final remoteLibrary = dataOf('library');
    if (remoteLibrary is Map) {
      library = mergeLibrary(library, remoteLibrary, now);
      await _applyLibrary(library);
    }
    _offer(up, 'library', library, now);

    // The 50 latest plays.
    final localHistory = await _readHistory();
    var history = localHistory;
    final remoteHistory = dataOf('history');
    if (remoteHistory is List) {
      history = mergeHistory(localHistory, remoteHistory);
      await _applyHistory(history, localHistory);
    }
    _offer(up, 'history', history, now);

    // Taste: the copy that learned more wins.
    final remoteTaste = dataOf('taste');
    final localTaste = await TasteModel.savedJson();
    final localAmount = localTaste == null ? -1 : TasteModel.amountOf(localTaste);
    if (remoteTaste is Map && TasteModel.amountOf(remoteTaste) > localAmount) {
      await TasteModel.adopt(remoteTaste);
    } else if (localTaste != null) {
      _offer(up, 'taste', localTaste, now);
    }

    // Listening time: this phone's own row; the others' are kept for totals.
    final mine = 'listening:${await Account.deviceId()}';
    final others = await ListeningTime.otherPhones();
    var othersChanged = false;
    for (final kind in remote.keys) {
      final data = dataOf(kind);
      if (kind.startsWith('listening:') && kind != mine && data is Map) {
        others[kind] = data;
        othersChanged = true;
      }
    }
    if (othersChanged) await ListeningTime.saveOtherPhones(others);
    _offer(up, mine, (await ListeningTime.load()).toJson(), now);

    // Remember the server copies merged above.
    for (final kind in remote.keys) {
      if (dataOf(kind) != null) _seen[kind] = (remote[kind] as Map)['updatedAt'];
    }

    if (up.isNotEmpty) {
      final put = await Account.instance.api('PUT', '/sync', body: up);
      if (put == null || put.statusCode != 200) {
        await _saveState();
        return 'Uploading to the JARX server failed. It will try again.';
      }
      final times = (jsonDecode(put.body) as Map)['updatedAt'] as Map;
      for (final kind in up.keys) {
        _sent[kind] = _offered.remove(kind);
        // Ours is the server's copy now (unless another phone was quicker:
        // then the next sync downloads and merges theirs).
        if (times[kind] == up[kind]['updatedAt']) _seen[kind] = times[kind];
      }
    }
    lastSynced.value = DateTime.now();
    await _settings.putSettingStr(
        _lastKey, '${lastSynced.value!.millisecondsSinceEpoch}');
    await _saveState();
    log('Synced; sent ${up.keys.toList()}', name: 'Sync');
    return null;
  }

  /// Fingerprints of what is being uploaded, until the server took it.
  final _offered = <String, String>{};

  void _offer(Map<String, dynamic> up, String kind, Object data, int now) {
    final fp = _fingerprint(data);
    if (_sent[kind] == fp) return;
    _offered[kind] = fp;
    up[kind] = {'data': packSyncData(data), 'updatedAt': now};
  }

  static String _fingerprint(Object? data) =>
      sha1.convert(utf8.encode(jsonEncode(data))).toString();

  Future<void> _saveState() async {
    await _settings.putSettingStr(_seenKey, jsonEncode(_seen));
    await _settings.putSettingStr(_sentKey, jsonEncode(_sent));
  }

  Future<Map<String, dynamic>> _readMap(String key) async {
    try {
      final raw = await _settings.getSettingStr(key);
      if (raw != null) return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {}
    return {};
  }

  static Map<String, dynamic> _trackJson(Track t) =>
      trackToJson(t)..remove('lyrics'); // lyrics are fetched again anyway

  // ── Playlists ──────────────────────────────────────────────────────────────

  Future<List<PlaylistDB>> _syncedPlaylists() async {
    final isar = await DBProvider.db;
    final all = await isar.playlistDBs
        .filter()
        .typeEqualTo(PlaylistTypeDB.userPlaylist)
        .findAll();
    return all.where((p) => SyncLog.syncs(p.name)).toList();
  }

  Future<Map<String, dynamic>> _readLibrary() async {
    final playlists = <String, dynamic>{};
    for (final p in await _syncedPlaylists()) {
      final tracks = await _playlists.getPlaylistTracks(p.id);
      playlists[p.name] = {
        'u': p.updatedAt.millisecondsSinceEpoch,
        if (p.description != null) 'd': p.description,
        if (p.thumbnail != null) 'img': p.thumbnail!.url,
        't': [
          for (final t in tracks)
            if (!isLocalMediaId(t.mediaId)) _trackJson(trackDBToTrack(t)),
        ],
      };
    }
    return {'p': playlists, ...await SyncLog.read()};
  }

  Future<void> _applyLibrary(Map<String, dynamic> library) async {
    final dao = _playlists;
    final wanted = library['p'] as Map;
    SyncLog.muted = true;
    try {
      final deleted = library['x'] as Map;
      for (final p in await _syncedPlaylists()) {
        if (!wanted.containsKey(p.name) && deleted.containsKey(p.name)) {
          await dao.deletePlaylist(p.id);
        }
      }
      for (final e in wanted.entries) {
        final name = e.key as String, copy = e.value as Map;
        final tracks = [
          for (final t in copy['t'] as List)
            trackFromJson((t as Map).cast<String, dynamic>())
        ];
        final existing = await dao.getPlaylistByName(name);
        final id = existing?.id ??
            await dao.createPlaylist(name, description: copy['d'] as String?);
        if (id == null) continue;

        final current =
            existing == null ? <TrackDB>[] : await dao.getPlaylistTracks(id);
        final result = keepLocalFiles(
            tracks, [for (final t in current) trackDBToTrack(t)]);
        if (!listEquals([for (final t in result) t.id],
            [for (final t in current) t.mediaId])) {
          await dao.setPlaylistTracks(id, result);
        }
        if (existing != null &&
            copy['d'] != null &&
            copy['d'] != existing.description) {
          await dao.updatePlaylistMeta(id, description: copy['d'] as String);
        }
        final img = copy['img'] as String?;
        if (img != null && img != existing?.thumbnail?.url) {
          await dao.updatePlaylistThumbnail(id, img);
        }
        await dao.setUpdatedAt(
            id, DateTime.fromMillisecondsSinceEpoch((copy['u'] as num).toInt()));
      }
      await SyncLog.write({
        'x': library['x'],
        'r': library['r'],
        'a': library['a'],
      });
    } finally {
      SyncLog.muted = false;
    }
  }

  // ── History ────────────────────────────────────────────────────────────────

  HistoryDAO get _historyDao =>
      HistoryDAO(DBProvider.db, TrackDAO(DBProvider.db));

  Future<List<Map>> _readHistory() async {
    final rows = await _historyDao.getRawHistory(limit: historySyncSize);
    return [
      for (final r in rows)
        if (r.track.value != null && !isLocalMediaId(r.track.value!.mediaId))
          {
            'at': r.playedAt.millisecondsSinceEpoch,
            't': _trackJson(trackDBToTrack(r.track.value!)),
          }
    ];
  }

  Future<void> _applyHistory(List<Map> merged, List<Map> local) async {
    final have = {for (final e in local) '${(e['t'] as Map)['id']}@${e['at']}'};
    for (final e in merged.reversed) {
      if (have.contains('${(e['t'] as Map)['id']}@${e['at']}')) continue;
      await _historyDao.recordPlay(
          trackFromJson((e['t'] as Map).cast<String, dynamic>()),
          at: DateTime.fromMillisecondsSinceEpoch((e['at'] as num).toInt()));
    }
  }
}

/// Songs repeat long cover links and plugin names, so a big library is
/// gzipped before upload (about 8x smaller; the server keeps 1.9 MB per kind).
Object packSyncData(Object data) =>
    {'gz': base64.encode(gzip.encode(utf8.encode(jsonEncode(data))))};

/// Reads packed data, and older unpacked data as it is.
Object? unpackSyncData(Object? data) => data is Map && data['gz'] is String
    ? jsonDecode(utf8.decode(gzip.decode(base64.decode(data['gz'] as String))))
    : data;

/// [synced] in its order, with this phone's local-file songs (which never
/// sync) kept right after the song they followed before.
List<Track> keepLocalFiles(List<Track> synced, List<Track> current) {
  final after = <String?, List<Track>>{};
  String? previous;
  for (final t in current) {
    if (isLocalMediaId(t.id)) {
      (after[previous] ??= []).add(t);
    } else {
      previous = t.id;
    }
  }
  final result = [...?after.remove(null)];
  for (final t in synced) {
    result.add(t);
    result.addAll(after.remove(t.id) ?? const []);
  }
  for (final rest in after.values) {
    result.addAll(rest); // the song they followed is gone
  }
  return result;
}
