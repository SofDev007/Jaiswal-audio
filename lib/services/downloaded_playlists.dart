import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';

/// Playlists the user downloaded with "Download all", so the Offline tab can
/// show them as playlists instead of mixing their songs in with songs
/// downloaded one by one. Kept as a small JSON setting: playlist title and
/// the track ids in playlist order.
class DownloadedPlaylists {
  static const _key = 'downloadedPlaylists';

  /// Bumped when a playlist is recorded, so Offline shows it right away.
  static final changes = ValueNotifier<int>(0);

  static Future<List<({String title, List<String> ids})>> load() async {
    try {
      final raw = await SettingsDAO(DBProvider.db).getSettingStr(_key);
      if (raw == null) return [];
      return [
        for (final e in jsonDecode(raw) as List)
          (
            title: e['title'] as String,
            ids: [for (final id in e['ids'] as List) id as String],
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Remembers [tracks] as playlist [title]; downloading the same playlist
  /// again replaces its entry (it may have new songs).
  static Future<void> add(String title, List<Track> tracks) async {
    final all = [
      for (final p in await load())
        if (p.title != title) p,
      (title: title, ids: [for (final t in tracks) t.id]),
    ];
    await SettingsDAO(DBProvider.db).putSettingStr(
        _key,
        jsonEncode([
          for (final p in all) {'title': p.title, 'ids': p.ids}
        ]));
    changes.value++;
  }

  /// Splits [downloaded] into playlists (only songs actually downloaded, in
  /// playlist order; empty playlists left out) and the remaining singles.
  static ({
    List<({String title, List<Track> tracks})> playlists,
    List<Track> singles
  }) group(
      List<Track> downloaded, List<({String title, List<String> ids})> saved) {
    final byId = {for (final t in downloaded) t.id: t};
    final inPlaylist = <String>{};
    final playlists = <({String title, List<Track> tracks})>[];
    for (final p in saved.reversed) {
      final tracks = [
        for (final id in p.ids)
          if (byId[id] != null) byId[id]!,
      ];
      if (tracks.isEmpty) continue;
      inPlaylist.addAll(tracks.map((t) => t.id));
      playlists.add((title: p.title, tracks: tracks));
    }
    return (
      playlists: playlists,
      singles: [
        for (final t in downloaded)
          if (!inPlaylist.contains(t.id)) t,
      ],
    );
  }

  // ── Songs added later, and songs that failed ───────────────────────────

  /// Set by the downloader: downloads [track], just added to the downloaded
  /// playlist [title].
  static void Function(String title, Track track)? autoDownload;

  /// [track] was added to playlist [title]: if that playlist was downloaded
  /// with "Download all", record the song and download it too.
  static Future<void> songAdded(String title, Track track) async {
    final saved = await load();
    final p = saved.where((p) => p.title == title).firstOrNull;
    if (p == null) return;
    if (!p.ids.contains(track.id)) {
      final all = [
        for (final q in saved)
          q.title == title ? (title: q.title, ids: [...q.ids, track.id]) : q,
      ];
      await SettingsDAO(DBProvider.db).putSettingStr(
          _key,
          jsonEncode([
            for (final q in all) {'title': q.title, 'ids': q.ids}
          ]));
      changes.value++;
    }
    autoDownload?.call(title, track);
  }

  static const _failedKey = 'downloadedPlaylistsFailed';

  /// Playlist title -> ids of its songs whose download failed last time.
  static Future<Map<String, List<String>>> loadFailed() async {
    try {
      final raw = await SettingsDAO(DBProvider.db).getSettingStr(_failedKey);
      if (raw == null) return {};
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          e.key as String: [for (final id in e.value as List) id as String],
      };
    } catch (_) {
      return {};
    }
  }

  /// Records the songs of [title] that failed ([ids] empty clears it).
  static Future<void> setFailed(String title, List<String> ids) async {
    final all = await loadFailed();
    if (ids.isEmpty) {
      if (all.remove(title) == null) return;
    } else {
      all[title] = ids;
    }
    await SettingsDAO(DBProvider.db)
        .putSettingStr(_failedKey, jsonEncode(all));
    changes.value++;
  }
}
