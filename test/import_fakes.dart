// Test doubles for ContentImportCubit: an importer plugin, loaded resolver
// plugins, a scripted matcher and a playlist store that records saves.

import 'dart:async';
import 'dart:math';

import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/global_db.dart';
import 'package:Bloomee/services/meta_resolver/cross_plugin_resolver.dart';
import 'package:Bloomee/services/plugin/plugin_service.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart';
import 'package:Bloomee/src/rust/api/plugin/manifest.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';
import 'package:Bloomee/src/rust/api/plugin/plugin_info.dart';
import 'package:Bloomee/src/rust/api/plugin/types.dart';
import 'package:isar_community/isar.dart';

typedef Handler = Future<PluginResponse> Function(ContentImporterCommand cmd);
typedef ResolverHandler = Future<PluginResponse> Function(
    String pluginId, ContentResolverCommand cmd);

/// Plays the importer plugin, and reports [resolvers] as loaded
/// content-resolver plugins.
class FakePluginService extends PluginService {
  FakePluginService(this.handler, {List<String>? resolvers, this.onResolver})
      : resolvers = resolvers ?? ['yt'];
  final Handler handler;

  /// Answers content-resolver requests (radio, artist details...).
  ResolverHandler? onResolver;
  List<String> resolvers;

  /// Thrown by the next resolver-plugin listing, then cleared.
  Object? listingError;

  /// 'check', 'info' or 'tracks', in the order calls started.
  final calls = <String>[];
  int _active = 0;
  int maxActive = 0;

  @override
  Future<PluginResponse> execute({
    required String pluginId,
    required PluginRequest request,
  }) async {
    if (request is PluginRequest_ContentResolver) {
      final c = request.field0;
      calls.add('$pluginId:${c is ContentResolverCommand_GetRadioTracks ? 'radio' : c is ContentResolverCommand_GetArtistDetails ? 'artist:${c.id}' : c is ContentResolverCommand_Search ? 'search' : 'other'}');
      return onResolver!(pluginId, request.field0);
    }
    final cmd = (request as PluginRequest_ContentImporter).field0;
    calls.add(cmd is ContentImporterCommand_GetTracks
        ? 'tracks'
        : cmd is ContentImporterCommand_GetCollectionInfo
            ? 'info'
            : 'check');
    maxActive = max(maxActive, ++_active);
    try {
      return await handler(cmd);
    } finally {
      _active--;
    }
  }

  @override
  Future<List<PluginInfo>> getAvailablePlugins() async {
    final e = listingError;
    if (e != null) {
      listingError = null;
      throw e;
    }
    return [for (final id in resolvers) _ResolverInfo(id)];
  }

  @override
  List<String> getLoadedPlugins() => resolvers;
}

class _ResolverInfo implements PluginInfo {
  _ResolverInfo(String id) : manifest = _Manifest(id);
  @override
  final Manifest manifest;
  @override
  PluginType get pluginType => PluginType.contentResolver;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manifest implements Manifest {
  _Manifest(this.id);
  @override
  final String id;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef MatchFn = FutureOr<List<ScoredTrackCandidate>> Function(
    TrackMatchTarget target);

/// Answers each lookup with [match]; records every title looked up.
class FakeResolver extends CrossPluginResolver {
  FakeResolver(PluginService service, [MatchFn? match])
      : match = match ?? ((_) => const []),
        super(pluginService: service);
  MatchFn match;
  final looked = <String>[];

  @override
  Future<List<ScoredTrackCandidate>> resolveTrack({
    required TrackMatchTarget target,
    required List<String> pluginIds,
    int limit = 5,
    double minConfidence = 0.45,
    double earlyAcceptThreshold = 0.93,
    bool sequential = false,
    Set<String> excludeTrackIds = const {},
    ContentSearchFilter searchFilter = ContentSearchFilter.track,
    List<String>? queries,
  }) async {
    looked.add(target.title);
    return match(target);
  }
}

/// A candidate track found on plugin "yt".
ScoredTrackCandidate candidate(String title, double confidence,
        {String artist = 'Artist'}) =>
    ScoredTrackCandidate(
      track: Track(
        id: 'yt::$title::$artist',
        title: title,
        artists: [ArtistSummary(id: artist, name: artist)],
        thumbnail: const Artwork(url: '', layout: ImageLayout.square),
        isExplicit: false,
      ),
      pluginId: 'yt',
      confidence: confidence,
    );

/// Records saves instead of writing to Isar; [fail] makes the next save throw.
class RecordingPlaylistDao extends PlaylistDAO {
  RecordingPlaylistDao() : this._(Completer<Isar>().future);
  RecordingPlaylistDao._(Future<Isar> db) : super(db, TrackDAO(db));

  bool fail = false;
  final saved = <String, List<String>>{};

  @override
  Future<int> ensurePlaylist(String name,
      {PlaylistTypeDB type = PlaylistTypeDB.userPlaylist}) async {
    if (fail) {
      fail = false;
      throw StateError('disk full');
    }
    saved.putIfAbsent(name, () => []);
    return saved.keys.toList().indexOf(name);
  }

  @override
  Future<void> updatePlaylistThumbnail(int playlistId, String thumbUrl) async {}

  @override
  Future<int?> addTrackToPlaylist(int playlistId, Track track) async {
    saved.values.elementAt(playlistId).add(track.id);
    return 0;
  }
}
