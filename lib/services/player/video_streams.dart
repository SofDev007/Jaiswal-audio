// Music videos for YouTube songs, from the YouTube Video plugin. YouTube
// Music and YouTube Video songs share YouTube's video id, so any song from
// either plugin can show its video.

import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/plugins/utils/media_id.dart';
import 'package:Bloomee/services/player/stream_quality_selector.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart';

const ytVideoPlugin = 'content-resolver.bloomfactory.ytvideo';

class VideoStream {
  const VideoStream(this.url, this.headers, this.height);
  final Uri url;
  final Map<String, String>? headers;
  final int height;

  String get label => '${height}p';
}

/// Whether [track] comes from YouTube (so it has a video).
bool hasVideo(Track track) {
  final plugin = tryParseMediaId(track.id)?.pluginId ?? '';
  return plugin.contains('ytmusic') || plugin.contains('ytvideo');
}

/// YouTube's format codes (itag) with a picture, by height.
const _itagHeight = {
  17: 144, 160: 144, 278: 144, 394: 144,
  133: 240, 242: 240, 395: 240,
  18: 360, 134: 360, 243: 360, 396: 360,
  135: 480, 244: 480, 397: 480,
  22: 720, 136: 720, 247: 720, 298: 720, 302: 720, 398: 720,
  137: 1080, 248: 1080, 299: 1080, 303: 1080, 399: 1080,
};

/// The video streams among the plugin's streams, lowest first, one per
/// height. The plugin labels a stream by its sound ("aac"), so the picture
/// is told by YouTube's own `mime` and `itag` in the link.
List<VideoStream> videoStreamsOf(Iterable<(String url, Map<String, String>?)> s) {
  final byHeight = <int, VideoStream>{};
  for (final (url, headers) in s) {
    final uri = Uri.tryParse(url);
    if (uri == null) continue;
    final mime = uri.queryParameters['mime'] ?? '';
    final height = _itagHeight[int.tryParse(uri.queryParameters['itag'] ?? '')];
    if (!mime.startsWith('video/') || height == null) continue;
    byHeight.putIfAbsent(height, () => VideoStream(uri, headers, height));
  }
  return byHeight.values.toList()..sort((a, b) => a.height - b.height);
}

/// [track]'s video streams; throws when the YouTube Video plugin isn't
/// installed or YouTube refused.
Future<List<VideoStream>> videoStreamsFor(Track track) async {
  final id = tryParseMediaId(track.id)!.localId;
  final res = await ServiceLocator.pluginService.execute(
    pluginId: ytVideoPlugin,
    request: PluginRequest.contentResolver(
        ContentResolverCommand.getStreams(id: id)),
  );
  return res.maybeWhen(
    streams: (streams) => videoStreamsOf(
        streams.map((s) => (s.url, streamHeadersToMap(s.headers)))),
    orElse: () => const [],
  );
}
