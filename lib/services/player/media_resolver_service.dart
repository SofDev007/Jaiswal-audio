import 'dart:developer';

import 'package:Bloomee/services/player/song_cache.dart';

import 'package:Bloomee/core/events/global_event_bus.dart';
import 'package:Bloomee/core/constants/setting_keys.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/plugins/errors/plugin_exceptions.dart';
import 'package:Bloomee/plugins/utils/media_id.dart';
import 'package:Bloomee/services/db/dao/download_dao.dart';
import 'package:Bloomee/services/download_crypto.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/plugin/plugin_service.dart';
import 'package:Bloomee/services/player/stream_quality_selector.dart';
import 'package:Bloomee/utils/friendly_error.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart';

class ResolvedMediaSource {
  final Uri uri;
  final bool isOffline;
  final Map<String, String>? headers;

  /// When [uri] goes through the song cache: the stream itself, to play
  /// directly if the player can't use the cache on this phone.
  final ResolvedMediaSource? direct;

  const ResolvedMediaSource({
    required this.uri,
    required this.isOffline,
    this.headers,
    this.direct,
  });
}

/// Resolves a [Track] into a playable [Uri].
///
/// Resolution order:
/// 1. Local downloaded file (offline).
/// 2. Plugin system — asks the owning plugin for stream URIs via [GetStreams].
class MediaResolverService {
  final DownloadDAO _downloadDao;
  final SettingsDAO _settingsDao;
  final PluginService _pluginService;

  MediaResolverService({
    required DownloadDAO downloadDao,
    required SettingsDAO settingsDao,
    required PluginService pluginService,
  })  : _downloadDao = downloadDao,
        _settingsDao = settingsDao,
        _pluginService = pluginService;

  /// Factory that creates its own DAO instances from [DBProvider.db].
  factory MediaResolverService.create(PluginService pluginService) {
    final trackDao = TrackDAO(DBProvider.db);
    final playlistDao = PlaylistDAO(DBProvider.db, trackDao);
    return MediaResolverService(
      downloadDao: DownloadDAO(DBProvider.db, trackDao, playlistDao),
      settingsDao: SettingsDAO(DBProvider.db),
      pluginService: pluginService,
    );
  }

  /// Resolve [track] into a playable URI.
  Future<ResolvedMediaSource> resolve(Track track) async {
    // 1. Check for an offline/downloaded version.
    try {
      final down = await _downloadDao.getDownloadRecord(track.id);
      if (down != null) {
        log('Playing Offline: ${track.title}', name: 'MediaResolverService');
        final file = '${down.filePath}/${down.fileName}';
        return ResolvedMediaSource(
          uri: Uri.file(DownloadCrypto.isEncrypted(down.fileName)
              ? await DownloadCrypto.playableCopy(file)
              : file),
          isOffline: true,
        );
      }
    } catch (e) {
      log('Download check failed: $e', name: 'MediaResolverService');
      // Non-fatal — continue to online resolution
    }

    // 1b. Streamed to the end before: from the phone, no data.
    if (!SongCache.disabled) {
      try {
        final cached = (await SongCache.instance).lookup(track.id);
        if (cached != null) {
          log('Playing from cache: ${track.title}',
              name: 'MediaResolverService');
          return ResolvedMediaSource(uri: Uri.file(cached.path), isOffline: true);
        }
      } catch (e) {
        log('Cache check failed: $e', name: 'MediaResolverService');
      }
    }

    // 2. Plugin-based stream resolution.
    final parts = tryParseMediaId(track.id);
    if (parts == null) {
      GlobalEventBus.instance.emitError(
        AppError.malformedMediaId(rawId: track.id),
      );
      throw Exception(
        'Cannot resolve stream for "${track.title}" — '
        'malformed media ID: "${track.id}"',
      );
    }

    if (parts.pluginId == 'local') {
      throw Exception(
        'Local file not found for "${track.title}" — '
        'it may have been deleted or moved.',
      );
    }

    log(
        'Resolving streams for "${track.title}" '
        '(plugin: ${parts.pluginId}, id: ${parts.localId})',
        name: 'MediaResolverService');

    PluginResponse response;
    try {
      response = await _pluginService.execute(
        pluginId: parts.pluginId,
        request: PluginRequest.contentResolver(
          ContentResolverCommand.getStreams(id: parts.localId),
        ),
      );
    } on PluginException catch (e) {
      log('getStreams failed: ${e.message}', name: 'MediaResolverService');
      if (e is PluginNotLoadedException) {
        GlobalEventBus.instance.emitError(
          AppError.pluginNotLoaded(pluginId: parts.pluginId, mediaId: track.id),
        );
      } else {
        GlobalEventBus.instance.emitError(
          AppError.pluginError(
            pluginId: parts.pluginId,
            // e.message is the source's raw reply; it stays in the log.
            message: friendlyError(e.message,
                fallback: "Couldn't play this song from its source right now. "
                    'Try again later.'),
          ),
        );
      }
      rethrow;
    }

    return response.when(
      streams: (streams) async {
        if (streams.isEmpty) {
          throw Exception('No streams returned for "${track.title}"');
        }

        final storedQuality = await _settingsDao.getSettingStr(
          SettingKeys.strmQuality,
        );
        final normalizedQuality = normalizeStoredStreamQualityLabel(
          storedQuality,
          fallback: AudioStreamQualityPreference.high.label,
        );
        if (storedQuality != normalizedQuality) {
          await _settingsDao.putSettingStr(
            SettingKeys.strmQuality,
            normalizedQuality,
          );
        }
        final preference = AudioStreamQualityPreferenceX.fromStored(
          normalizedQuality,
        );
        final selectedStream = StreamQualitySelector.selectPlaybackStream(
          streams,
          preference: preference,
        );
        final streamUrl = selectedStream?.url.trim();

        if (streamUrl == null || streamUrl.isEmpty) {
          throw Exception(
            'Streams returned for "${track.title}" contain no playable URL',
          );
        }

        final uri = Uri.tryParse(streamUrl);
        if (uri == null ||
            uri.scheme.isEmpty ||
            (uri.scheme != 'http' &&
                uri.scheme != 'https' &&
                uri.scheme != 'file')) {
          throw Exception(
            'Invalid stream URL for "${track.title}": $streamUrl',
          );
        }

        log('Resolved stream: $streamUrl', name: 'MediaResolverService');
        final source = ResolvedMediaSource(
          uri: uri,
          isOffline: false,
          headers: selectedStream == null
              ? null
              : streamHeadersToMap(selectedStream.headers),
        );
        if (SongCache.disabled || uri.scheme == 'file') return source;
        try {
          // Through the song cache, which keeps it if it plays to the end.
          return ResolvedMediaSource(
            uri: await (await SongCache.instance)
                .tee(track.id, uri, source.headers),
            isOffline: false,
            direct: source,
          );
        } catch (e) {
          log('Song cache unavailable: $e', name: 'MediaResolverService');
          return source;
        }
      },
      trackDetails: (_) =>
          throw Exception('Unexpected response type: trackDetails'),
      albumDetails: (_) =>
          throw Exception('Unexpected response type: albumDetails'),
      artistDetails: (_) =>
          throw Exception('Unexpected response type: artistDetails'),
      playlistDetails: (_) =>
          throw Exception('Unexpected response type: playlistDetails'),
      search: (_) => throw Exception('Unexpected response type: search'),
      moreTracks: (_) =>
          throw Exception('Unexpected response type: moreTracks'),
      moreAlbums: (_) =>
          throw Exception('Unexpected response type: moreAlbums'),
      homeSections: (_) =>
          throw Exception('Unexpected response type: homeSections'),
      loadMoreItems: (_) =>
          throw Exception('Unexpected response type: loadMoreItems'),
      charts: (_) => throw Exception('Unexpected response type: charts'),
      chartDetails: (_) =>
          throw Exception('Unexpected response type: chartDetails'),
      segments: (_) => throw Exception('Unexpected response type: segments'),
      lyricsResult: (_) =>
          throw Exception('Unexpected response type: lyricsResult'),
      lyricsSearchResults: (_) =>
          throw Exception('Unexpected response type: lyricsSearchResults'),
      lyricsById: (_, __) =>
          throw Exception('Unexpected response type: lyricsById'),
      suggestions: (_) =>
          throw Exception('Unexpected response type: suggestions'),
      canHandle: (_) => throw Exception('Unexpected response type: canHandle'),
      collectionInfo: (_) =>
          throw Exception('Unexpected response type: collectionInfo'),
      importTracks: (_) =>
          throw Exception('Unexpected response type: importTracks'),
      ack: () => throw Exception('Unexpected response type: ack'),
    );
  }
}
