// One local space (its own database file) per Google account on this phone,
// so signing in on someone else's phone never mixes their music into your
// account. Plugins, settings and setup are copied into a new space; the
// personal music (playlists, Liked, history, downloads list, taste, listening
// time) starts empty there and comes from the account by sync.
//
// spaces.json: {"active": "dbv3", "spaces": {"dbv3": {"user": {...}},
//                                             "u_<id>": {"user": {...}}}}
// A space without "user" belongs to nobody yet (music made before sign-in).

import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:Bloomee/services/account/account.dart' show JarxUser;
import 'package:Bloomee/services/app_restart.dart';
import 'package:Bloomee/services/db/global_db.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

class Spaces {
  Spaces._();

  /// The space that existed before accounts had spaces.
  static const first = 'dbv3';

  static String _dir = '';
  static Map<String, dynamic> _spaces = {};
  static String active = first;

  static File get _file => File(p.join(_dir, 'spaces.json'));

  /// Reads which space to open. Before [DBProvider.openDB].
  static void load(String dir) {
    _dir = dir;
    try {
      final j = jsonDecode(_file.readAsStringSync()) as Map;
      _spaces = (j['spaces'] as Map).cast<String, dynamic>();
      final a = j['active'] as String;
      active = _spaces.containsKey(a) ? a : first;
      _spaces.putIfAbsent(first, () => <String, dynamic>{});
    } catch (_) {
      _spaces = {first: <String, dynamic>{}};
      active = first;
    }
  }

  static void _save() => _file.writeAsStringSync(
      jsonEncode({'active': active, 'spaces': _spaces}),
      flush: true);

  static JarxUser? ownerOf(String space) {
    final u = (_spaces[space] as Map?)?['user'];
    return u is Map ? JarxUser.fromJson(u) : null;
  }

  /// Spaces with an owner, as (space, owner).
  static List<(String, JarxUser)> get accounts => [
        for (final s in _spaces.keys)
          if (ownerOf(s) case final u?) (s, u),
      ];

  static String? spaceOf(String userId) {
    for (final (s, u) in accounts) {
      if (u.id == userId) return s;
    }
    return null;
  }

  /// Gives the active space to [user] (null: to nobody).
  static void own(JarxUser? user) {
    _spaces[active] = {if (user != null) 'user': user.toJson()};
    _save();
  }

  /// A secure-storage key of [space] (the first space keeps the old names).
  static String key(String name, [String? space]) {
    space ??= active;
    return space == first ? name : '$name@$space';
  }

  /// A new space for [user]: a copy of the open database, emptied of the
  /// personal music when it is first opened.
  static Future<String> create(Isar open, JarxUser user) async {
    final space = 'u_${user.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}';
    final file = File(p.join(_dir, '$space.isar'));
    if (file.existsSync()) file.deleteSync();
    await open.copyToFile(file.path);
    _spaces[space] = {'user': user.toJson(), 'fresh': true};
    _save();
    return space;
  }

  /// Restarts JARX into [space].
  static Future<void> switchTo(String space) async {
    active = space;
    _save();
    await AppRestart.restart();
  }

  /// Forgets a space that isn't open, and deletes its database.
  static void remove(String space) {
    if (space == active) return;
    _spaces.remove(space);
    _save();
    for (final f in [
      File(p.join(_dir, '$space.isar')),
      File(p.join(_dir, '$space.isar.lock')),
    ]) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (e) {
        log('Removing $f failed: $e', name: 'Spaces');
      }
    }
  }

  /// Settings that are about the person, not the phone.
  static const _personal = [
    'listeningTime1', 'listeningOthers1', 'recTasteModel1', 'recHealth',
    'syncLog1', 'syncSeen1', 'syncSent1', 'syncLast1', 'lastQueueState',
    'downloadedPlaylists', 'downloadedPlaylistsFailed', 'blockedSuggestions',
    'streamSwaps2', 'lastBackupTimestamp',
  ];

  /// Empties a new space of the music copied from the space it was made in.
  /// Liked and Downloads come back empty at startup (ensurePlaylist).
  static void clearIfFresh(Isar isar) {
    final s = _spaces[active] as Map?;
    if (s?['fresh'] != true) return;
    // ponytail: downloaded files are shared on disk; a space only forgets
    // its list, so a song downloaded in two spaces and deleted in one
    // goes missing in the other.
    isar.writeTxnSync(() {
      isar.playlistEntryDBs
          .filter()
          .not()
          .playlist((q) => q.nameEqualTo('_LOCAL_MUSIC'))
          .deleteAllSync();
      isar.playlistDBs
          .filter()
          .not()
          .nameEqualTo('_LOCAL_MUSIC')
          .deleteAllSync();
      isar.playbackHistoryDBs.clearSync();
      isar.trackSignalDBs.clearSync();
      isar.searchHistoryDBs.clearSync();
      isar.downloadDBs.clearSync();
      isar.cacheEntryDBs.clearSync();
      isar.appSettingsStrDBs.deleteAllBySettingNameSync(_personal);
    });
    s!.remove('fresh');
    _save();
    log('New space $active emptied', name: 'Spaces');
  }

  /// How much music the open space holds: user playlists (Liked not
  /// counted), Liked songs, plays.
  static Future<(int, int, int)> music(Isar isar) async {
    final lists = await isar.playlistDBs
        .filter()
        .typeEqualTo(PlaylistTypeDB.userPlaylist)
        .not()
        .nameEqualTo('Liked')
        .count();
    final liked = await isar.playlistEntryDBs
        .filter()
        .playlist((q) => q.nameEqualTo('Liked'))
        .count();
    return (lists, liked, await isar.playbackHistoryDBs.count());
  }
}
