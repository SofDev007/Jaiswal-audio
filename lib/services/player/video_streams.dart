// Music videos for songs from the YouTube Video plugin (only those; songs
// from YouTube Music or other sources don't offer the video).
//
// The plugin (v6 and later) answers "<videoId>#video" with YouTube's HLS
// playlist: the picture alone, 144p to 1080p, for the whole video. Older
// plugins, and videos without that playlist, give the 360p file with sound.

import 'dart:convert';
import 'dart:math' as math;

import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/plugins/errors/plugin_exceptions.dart';
import 'package:Bloomee/plugins/utils/media_id.dart';
import 'package:Bloomee/services/player/stream_quality_selector.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart' show Caption, WebVTTCaptionFile;

const ytVideoPlugin = 'content-resolver.bloomfactory.ytvideo';

class VideoStream {
  const VideoStream(
    this.url,
    this.headers,
    this.height, {
    this.hls = false,
    this.codecs = '',
    this.resolution = '',
    this.bandwidth = 0,
    this.fps = 0,
  });

  /// The file, or for HLS the playlist of this one quality.
  final Uri url;
  final Map<String, String>? headers;

  /// The picture's shorter side: a vertical 1080x1920 video is "1080p".
  final int height;

  /// One quality of the HLS playlist (picture only).
  final bool hls;

  /// HLS: the picture's codec (e.g. avc1.640028), its size (1920x1080),
  /// bits per second (picture and sound) and frames per second.
  final String codecs;
  final String resolution;
  final int bandwidth;
  final int fps;

  String get label => '${height}p';
}

/// Whether [track] offers "Play video": only songs found with the YouTube
/// Video plugin (the user's rule), not YouTube Music or any other source.
bool hasVideo(Track track) =>
    tryParseMediaId(track.id)?.pluginId == ytVideoPlugin;

/// YouTube's format codes (itag) with a picture, by height.
const _itagHeight = {
  17: 144, 160: 144, 278: 144, 394: 144,
  133: 240, 242: 240, 395: 240,
  18: 360, 134: 360, 243: 360, 396: 360,
  135: 480, 244: 480, 397: 480,
  22: 720, 136: 720, 247: 720, 298: 720, 302: 720, 398: 720,
  137: 1080, 248: 1080, 299: 1080, 303: 1080, 399: 1080,
};

/// The video files among the plugin's streams, lowest first, one per
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

/// The H.264 qualities of a YouTube HLS master playlist up to 1080p, one
/// per height, lowest first. VP9 and 1440p/4K are left out: every phone
/// decodes H.264 in hardware, many older ones can't do VP9 smoothly, and
/// above 1080p is more than a phone screen shows.
List<VideoStream> hlsVariantsOf(String master, Uri base) {
  final lines = master.split(RegExp(r'\r?\n'));
  final byHeight = <int, VideoStream>{};
  for (var i = 0; i + 1 < lines.length; i++) {
    final tag = lines[i];
    if (!tag.startsWith('#EXT-X-STREAM-INF:')) continue;
    String? attr(String name) {
      final m = RegExp('[:,]$name=(?:"([^"]*)"|([^,]*))').firstMatch(tag);
      return m?.group(1) ?? m?.group(2);
    }

    final video = (attr('CODECS') ?? '')
        .split(',')
        .map((c) => c.trim())
        .firstWhere((c) => c.startsWith('avc1'), orElse: () => '');
    final size = RegExp(r'^(\d+)x(\d+)$').firstMatch(attr('RESOLUTION') ?? '');
    final uri = lines[i + 1].trim();
    if (video.isEmpty || size == null || uri.isEmpty || uri.startsWith('#')) {
      continue;
    }
    final height = math.min(int.parse(size[1]!), int.parse(size[2]!));
    if (height > 1080) continue;
    byHeight.putIfAbsent(
      height,
      () => VideoStream(
        base.resolve(uri),
        null,
        height,
        hls: true,
        codecs: video,
        resolution: size[0]!,
        bandwidth: int.tryParse(attr('BANDWIDTH') ?? '') ?? 0,
        fps: (double.tryParse(attr('FRAME-RATE') ?? '') ?? 0).round(),
      ),
    );
  }
  return byHeight.values.toList()..sort((a, b) => a.height - b.height);
}

/// A master playlist with only [variants]: one for a chosen quality, all
/// for "Auto" (the player picks by connection speed). Picture only: the
/// sound and subtitle tracks are left out, so they aren't downloaded or
/// decoded (JARX's own player plays the song).
String hlsMasterOf(Iterable<VideoStream> variants) => [
      '#EXTM3U',
      '#EXT-X-INDEPENDENT-SEGMENTS',
      for (final v in variants) ...[
        '#EXT-X-STREAM-INF:BANDWIDTH=${math.max(v.bandwidth, 1)},'
            'CODECS="${v.codecs}",RESOLUTION=${v.resolution}'
            '${v.fps > 0 ? ',FRAME-RATE=${v.fps}' : ''}',
        v.url.toString(),
      ],
      '',
    ].join('\n');

/// What to play for [want] (0 = Auto) from [streams] (lowest first): for
/// Auto every HLS quality (the player picks) or the best file; else the
/// chosen height, or the nearest lower one this video has.
List<VideoStream> videoQualityFor(List<VideoStream> streams, int want) {
  if (want == 0) return streams.first.hls ? streams : [streams.last];
  return [
    streams.lastWhere((s) => s.height <= want, orElse: () => streams.first)
  ];
}

/// Roughly how much data an hour of [v] uses, e.g. "1.4 GB" or "230 MB".
String dataPerHour(VideoStream v) {
  final mb = v.bandwidth * 3600 / 8 / 1e6;
  if (mb <= 0) return '';
  return mb >= 1000
      ? '${(mb / 1000).toStringAsFixed(1)} GB'
      : '${(mb / 10).round() * 10} MB';
}

/// One of the video's caption tracks (YouTube's own, from the HLS playlist).
class CaptionTrack {
  const CaptionTrack(this.language, this.name, this.url);

  /// e.g. "en", "hi", "hi-Latn".
  final String language;

  /// As YouTube names it, e.g. "English", "हिन्दी", "Hindi (Latin)".
  final String name;

  /// The track's playlist.
  final Uri url;
}

/// The caption tracks listed in a YouTube HLS master playlist.
List<CaptionTrack> hlsCaptionsOf(String master, Uri base) => [
      for (final line in master.split(RegExp(r'\r?\n')))
        if (line.startsWith('#EXT-X-MEDIA:') && line.contains('TYPE=SUBTITLES'))
          if (RegExp(r'URI="([^"]+)"').firstMatch(line) case final uri?)
            CaptionTrack(
              RegExp(r'LANGUAGE="([^"]*)"').firstMatch(line)?.group(1) ?? '',
              RegExp(r'NAME="([^"]*)"').firstMatch(line)?.group(1) ?? '',
              base.resolve(uri[1]!),
            ),
    ];

/// The track to show: the language the user picked last ([preferred]),
/// else English, else Hindi, else the first; none when captions are off.
CaptionTrack? captionTrackFor(List<CaptionTrack> tracks, String? preferred) {
  if (tracks.isEmpty || preferred == captionsOff) return null;
  for (final want in [
    if (preferred != null && preferred.isNotEmpty) preferred,
    'en',
    'hi',
  ]) {
    for (final t in tracks) {
      if (t.language == want) return t;
    }
    for (final t in tracks) {
      if (t.language.startsWith('$want-')) return t;
    }
  }
  return tracks.first;
}

/// The saved caption choice meaning "captions off".
const captionsOff = 'off';

/// [track]'s captions: its playlist names the caption file(s) (YouTube:
/// one WebVTT file for the whole video).
Future<List<Caption>> captionsFor(CaptionTrack track) async {
  final list = await http.get(track.url).timeout(const Duration(seconds: 15));
  if (list.statusCode != 200) return const [];
  final files = [
    for (final l in utf8
        .decode(list.bodyBytes, allowMalformed: true)
        .split(RegExp(r'\r?\n')))
      if (l.trim().isNotEmpty && !l.startsWith('#')) track.url.resolve(l.trim()),
  ];
  final parts = await Future.wait(files.map(
      (u) => http.get(u).timeout(const Duration(seconds: 15)).then((r) =>
          r.statusCode == 200
              ? utf8.decode(r.bodyBytes, allowMalformed: true)
              : '')));
  return WebVTTCaptionFile(parts.join('\n\n')).captions;
}

/// The caption showing at [at], if any.
String captionAt(List<Caption> captions, Duration at) {
  for (final c in captions) {
    if (at < c.start) break;
    if (at <= c.end) return c.text;
  }
  return '';
}

/// "Play video" for a song: the qualities (HLS, or the files) and the
/// video's caption tracks.
class VideoSource {
  const VideoSource(this.streams, [this.captions = const []]);
  final List<VideoStream> streams;
  final List<CaptionTrack> captions;
}

Future<List<StreamSource>> _streams(String id) async {
  final res = await ServiceLocator.pluginService.execute(
    pluginId: ytVideoPlugin,
    request:
        PluginRequest.contentResolver(ContentResolverCommand.getStreams(id: id)),
  );
  return res.maybeWhen(streams: (s) => s, orElse: () => const []);
}

/// [track]'s video: the HLS qualities (and captions) when there are any,
/// else the files. Throws when the YouTube Video plugin isn't installed or
/// YouTube refused.
Future<VideoSource> videoSourceFor(Track track) async {
  final id = tryParseMediaId(track.id)!.localId;
  List<StreamSource> streams;
  try {
    streams = await _streams('$id#video');
  } on PluginNotLoadedException {
    rethrow;
  } catch (_) {
    streams = await _streams(id); // a plugin older than v6
  }

  final hls = streams.where((s) => s.format == 'hls').firstOrNull;
  if (hls != null) {
    try {
      final url = Uri.parse(hls.url);
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        // UTF-8 always: YouTube sends no charset, and the http package's
        // Latin-1 default garbles names like "हिन्दी".
        final master = utf8.decode(res.bodyBytes, allowMalformed: true);
        final variants = hlsVariantsOf(master, url);
        if (variants.isNotEmpty) {
          return VideoSource(variants, hlsCaptionsOf(master, url));
        }
      }
    } catch (_) {
      // The files below.
    }
  }
  return VideoSource(videoStreamsOf(
      streams.map((s) => (s.url, streamHeadersToMap(s.headers)))));
}
