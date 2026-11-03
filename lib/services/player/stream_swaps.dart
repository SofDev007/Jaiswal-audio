import 'dart:convert';

import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';

/// Songs whose stream broke on their own source (YouTube now cuts some off,
/// e.g. "Mauja Hi Mauja") and played fine from another one. Remembered so the
/// next play goes straight to the working source: no error, no wait.
///
/// Kept for 30 days per song, then the original source is tried again. The
/// replacement's details are stored here, so nothing else has to have it.
class StreamSwaps {
  static const _key = 'streamSwaps2';
  static const _keep = Duration(days: 30);
  static const _max = 500;

  static Map<String, Map<String, dynamic>>? _cache;

  static Future<Map<String, Map<String, dynamic>>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final raw = await SettingsDAO(DBProvider.db).getSettingStr(_key);
      _cache = raw == null
          ? {}
          : {
              for (final e in (jsonDecode(raw) as Map).entries)
                e.key as String: Map<String, dynamic>.from(e.value as Map),
            };
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  /// The working replacement for [original], if one is remembered.
  static Future<Track?> lookup(Track original) async {
    final e = (await _load())[original.id];
    if (e == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(e['at'] as int);
    if (DateTime.now().difference(at) > _keep) return null;
    return _decode(e['track'] as Map);
  }

  static Future<void> remember(Track original, Track replacement) async {
    final swaps = await _load();
    swaps[original.id] = {
      'at': DateTime.now().millisecondsSinceEpoch,
      'track': _encode(replacement),
    };
    if (swaps.length > _max) {
      final oldest = swaps.entries.toList()
        ..sort(
            (a, b) => (a.value['at'] as int).compareTo(b.value['at'] as int));
      for (final e in oldest.take(swaps.length - _max)) {
        swaps.remove(e.key);
      }
    }
    await SettingsDAO(DBProvider.db).putSettingStr(_key, jsonEncode(swaps));
  }

  static Map<String, dynamic> _encode(Track t) => {
        'id': t.id,
        'title': t.title,
        'artists': [
          for (final a in t.artists) {'id': a.id, 'name': a.name}
        ],
        if (t.album != null)
          'album': {'id': t.album!.id, 'title': t.album!.title},
        if (t.durationMs != null) 'ms': t.durationMs!.toInt(),
        'thumb': t.thumbnail.url,
        if (t.thumbnail.urlHigh != null) 'thumbHigh': t.thumbnail.urlHigh,
        if (t.url != null) 'url': t.url,
        'explicit': t.isExplicit,
      };

  static Track _decode(Map m) => Track(
        id: m['id'] as String,
        title: m['title'] as String,
        artists: [
          for (final a in m['artists'] as List)
            ArtistSummary(id: a['id'] as String, name: a['name'] as String),
        ],
        album: m['album'] == null
            ? null
            : AlbumSummary(
                id: m['album']['id'] as String,
                title: m['album']['title'] as String,
                artists: const []),
        durationMs: m['ms'] == null ? null : BigInt.from(m['ms'] as int),
        thumbnail: Artwork(
            url: m['thumb'] as String? ?? '',
            urlHigh: m['thumbHigh'] as String?,
            layout: ImageLayout.square),
        url: m['url'] as String?,
        isExplicit: m['explicit'] as bool? ?? false,
      );
}
