// How two copies of the user's music are combined (this phone's and the
// account's). Plain maps, so the rules are easy to test and to send as JSON.
//
// Library: {'p': {name: {'u': updatedMs, 'd': description, 'img': coverUrl,
//                        't': [track json...]}},
//           'x': {name: deletedMs},              // deleted playlists
//           'r': {name: {trackId: removedMs}},   // songs taken out
//           'a': {name: {trackId: addedMs}}}     // songs put in
// History: [{'at': playedMs, 't': track json}], newest first.
//
// Rules: nothing is lost (songs from both copies are kept), a deletion or a
// removal spreads unless the song/playlist was added again after it, and a
// playlist's order comes from the copy changed last. Deletion records are
// kept for 30 days.

const syncKeepMs = 30 * 24 * 3600 * 1000;
const historySyncSize = 50;

Map<String, int> _maxMap(Object? a, Object? b, int oldest) {
  final out = <String, int>{};
  for (final m in [a, b]) {
    if (m is! Map) continue;
    for (final e in m.entries) {
      final t = (e.value as num).toInt();
      if (t < oldest) continue;
      final k = e.key as String;
      if ((out[k] ?? -1) < t) out[k] = t;
    }
  }
  return out;
}

Map<String, Map<String, int>> _nested(Object? a, Object? b, int oldest) {
  final names = {
    if (a is Map) ...a.keys.cast<String>(),
    if (b is Map) ...b.keys.cast<String>(),
  };
  final out = <String, Map<String, int>>{};
  for (final n in names) {
    final m = _maxMap(a is Map ? a[n] : null, b is Map ? b[n] : null, oldest);
    if (m.isNotEmpty) out[n] = m;
  }
  return out;
}

Map<String, dynamic> mergeLibrary(Map a, Map b, int nowMs) {
  final oldest = nowMs - syncKeepMs;
  final deleted = _maxMap(a['x'], b['x'], oldest);
  final removed = _nested(a['r'], b['r'], oldest);
  final added = _nested(a['a'], b['a'], oldest);
  final pa = a['p'] as Map? ?? const {};
  final pb = b['p'] as Map? ?? const {};

  final playlists = <String, dynamic>{};
  for (final name in {...pa.keys, ...pb.keys}.cast<String>()) {
    final p1 = pa[name] as Map?, p2 = pb[name] as Map?;
    final aNewer = p2 == null ||
        (p1 != null && (p1['u'] as num) >= (p2['u'] as num));
    final newer = (aNewer ? p1 : p2)!;
    final older = aNewer ? p2 : p1;
    final u = (newer['u'] as num).toInt();
    final gone = deleted[name];
    if (gone != null && gone >= u) continue; // deleted after its last change

    final out = removed[name] ?? const {}, put = added[name] ?? const {};
    bool keep(String id) {
      final r = out[id];
      return r == null || (put[id] ?? -1) > r;
    }

    final seen = <String>{};
    final tracks = [
      for (final t in [...newer['t'] as List, ...?(older?['t'] as List?)])
        if (seen.add((t as Map)['id'] as String) && keep(t['id'] as String)) t,
    ];
    playlists[name] = {
      'u': u,
      if (newer['d'] != null) 'd': newer['d'],
      if (newer['img'] != null) 'img': newer['img'],
      't': tracks,
    };
  }
  return {'p': playlists, 'x': deleted, 'r': removed, 'a': added};
}

/// The [historySyncSize] newest plays of both copies, without doubles.
List<Map> mergeHistory(List a, List b) {
  final seen = <String>{};
  final all = <Map>[
    for (final e in [...a, ...b].cast<Map>())
      if (seen.add('${(e['t'] as Map)['id']}@${e['at']}')) e,
  ]..sort((x, y) => (y['at'] as num).compareTo(x['at'] as num));
  return all.take(historySyncSize).toList();
}
