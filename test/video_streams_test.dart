// Video mode: YouTube's HLS playlist (via the YouTube Video plugin v6) →
// the H.264 qualities up to 1080p, the picture-only playlist JARX plays,
// and which quality a choice plays.
//
// Run with: flutter test test/video_streams_test.dart

import 'package:Bloomee/services/player/video_streams.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart' show WebVTTCaptionFile;

import 'fixtures/recs_dataset.dart';

String link(int itag, String mime) =>
    'https://rr1.googlevideo.com/videoplayback?expire=1&itag=$itag'
    '&mime=${Uri.encodeQueryComponent(mime)}&id=abc';

// The shape YouTube sends (visionos client, Nov 2026), links shortened.
const _master = '''#EXTM3U
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:URI="https://m/audio/233",TYPE=AUDIO,GROUP-ID="233",NAME="Default",DEFAULT=YES,AUTOSELECT=YES
#EXT-X-MEDIA:URI="https://m/audio/234",TYPE=AUDIO,GROUP-ID="234",NAME="Default",DEFAULT=YES,AUTOSELECT=YES
#EXT-X-STREAM-INF:BANDWIDTH=268103,CODECS="avc1.4D4015,mp4a.40.5",RESOLUTION=426x240,FRAME-RATE=24,VIDEO-RANGE=SDR,AUDIO="233",SUBTITLES="vtt",CLOSED-CAPTIONS=NONE
https://m/itag/229/a233/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=352523,CODECS="avc1.4D4015,mp4a.40.2",RESOLUTION=426x240,FRAME-RATE=24,VIDEO-RANGE=SDR,AUDIO="234",SUBTITLES="vtt",CLOSED-CAPTIONS=NONE
https://m/itag/229/a234/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=503043,CODECS="avc1.4D401E,mp4a.40.2",RESOLUTION=640x360,FRAME-RATE=24,VIDEO-RANGE=SDR,AUDIO="234",SUBTITLES="vtt",CLOSED-CAPTIONS=NONE
https://m/itag/230/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1262262,CODECS="avc1.4D401F,mp4a.40.2",RESOLUTION=1280x720,FRAME-RATE=24,VIDEO-RANGE=SDR,AUDIO="234",SUBTITLES="vtt",CLOSED-CAPTIONS=NONE
https://m/itag/232/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=159618,CODECS="avc1.4D400C,mp4a.40.5",RESOLUTION=256x144,FRAME-RATE=24,VIDEO-RANGE=SDR,AUDIO="233",SUBTITLES="vtt",CLOSED-CAPTIONS=NONE
https://m/itag/269/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3116363,CODECS="avc1.640028,mp4a.40.2",RESOLUTION=1920x1080,FRAME-RATE=24,VIDEO-RANGE=SDR,AUDIO="234",SUBTITLES="vtt",CLOSED-CAPTIONS=NONE
https://m/itag/270/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2326635,CODECS="vp09.00.40.08,mp4a.40.2",RESOLUTION=1920x1080,FRAME-RATE=24,VIDEO-RANGE=SDR,AUDIO="234",SUBTITLES="vtt",CLOSED-CAPTIONS=NONE
https://m/itag/614/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=18636855,CODECS="vp09.00.50.08,mp4a.40.2",RESOLUTION=3840x2160,FRAME-RATE=24,VIDEO-RANGE=SDR,AUDIO="234",SUBTITLES="vtt",CLOSED-CAPTIONS=NONE
https://m/itag/625/index.m3u8
''';

final _u = Uri.parse('https://m/cc');

final _base = Uri.parse('https://manifest.googlevideo.com/api/manifest/hls_variant/x/file/index.m3u8');

void main() {
  test('files: only streams with a picture, lowest first, one per height', () {
    final got = videoStreamsOf([
      (link(140, 'audio/mp4'), null), // sound only
      (link(251, 'audio/webm'), null),
      (link(22, 'video/mp4'), {'User-Agent': 'x'}),
      (link(18, 'video/mp4'), null),
      (link(134, 'video/mp4'), null), // another 360p: the first one stays
      (link(999, 'video/mp4'), null), // unknown format code
      ('not a link', null),
    ]);
    expect(got.map((s) => s.label), ['360p', '720p']);
    expect(got.first.url.queryParameters['itag'], '18');
    expect(got.last.headers, {'User-Agent': 'x'});
  });

  test('only YouTube Video songs offer the video', () {
    bool from(String plugin) => hasVideo(tr('abc', 'Song', 'A', plugin: plugin));
    expect(from('content-resolver.bloomfactory.ytmusic'), isFalse);
    expect(from('content-resolver.bloomfactory.ytvideo'), isTrue);
    expect(from('content-resolver.bloomfactory.jiosaavn'), isFalse);
    expect(from('local'), isFalse);
  });

  test('H.264 qualities up to 1080p, one each, lowest first', () {
    final v = hlsVariantsOf(_master, _base);
    expect([for (final s in v) s.height], [144, 240, 360, 720, 1080]);
    expect(v.every((s) => s.hls && s.codecs.startsWith('avc1')), isTrue);
    final hd = v.last;
    expect(hd.url.toString(), 'https://m/itag/270/index.m3u8');
    expect(hd.codecs, 'avc1.640028');
    expect(hd.resolution, '1920x1080');
    expect(hd.bandwidth, 3116363);
    expect(hd.fps, 24);
    expect(v[1].url.toString(), contains('/a233/'), reason: 'first 240p kept');
  });

  test('a vertical video is named by its shorter side', () {
    const short = '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=900000,CODECS="avc1.640028,mp4a.40.2",RESOLUTION=1080x1920\n'
        'https://m/short/index.m3u8\n';
    final v = hlsVariantsOf(short, _base);
    expect(v.single.height, 1080);
    expect(v.single.label, '1080p');
  });

  test('the playlist JARX plays has the picture only', () {
    final v = hlsVariantsOf(_master, _base);
    final m = hlsMasterOf(v.where((s) => s.height >= 720));
    expect(m, startsWith('#EXTM3U\n'));
    expect('#EXT-X-STREAM-INF'.allMatches(m), hasLength(2));
    expect(m, contains('CODECS="avc1.640028",RESOLUTION=1920x1080,FRAME-RATE=24'));
    expect(m, contains('https://m/itag/232/index.m3u8'));
    expect(m, isNot(contains('mp4a')));
    expect(m, isNot(contains('AUDIO=')));
    expect(m, isNot(contains('SUBTITLES')));
  });

  test('which quality a choice plays', () {
    final v = hlsVariantsOf(_master, _base);
    expect(videoQualityFor(v, 0), v, reason: 'Auto: all, the player picks');
    expect(videoQualityFor(v, 1080).single.height, 1080);
    expect(videoQualityFor(v, 480).single.height, 360, reason: 'nearest lower');
    expect(videoQualityFor(v, 100).single.height, 144);
    final short = v.where((s) => s.height <= 720).toList();
    expect(videoQualityFor(short, 1080).single.height, 720);
  });

  test('an older plugin still gives the 360p file', () {
    final files = videoStreamsOf([
      ('https://rr4.googlevideo.com/videoplayback?itag=18&mime=video%2Fmp4', null),
      ('https://rr4.googlevideo.com/videoplayback?itag=140&mime=audio%2Fmp4', null),
    ]);
    expect(files.single.height, 360);
    expect(files.single.hls, isFalse);
    expect(videoQualityFor(files, 0).single.height, 360);
    expect(videoQualityFor(files, 1080).single.height, 360);
  });

  test('caption tracks come from the same playlist', () {
    const master = '#EXTM3U\n'
        '#EXT-X-MEDIA:URI="https://m/cc/en",TYPE=SUBTITLES,GROUP-ID="vtt",LANGUAGE="en-IN",NAME="English (India)",DEFAULT=NO,AUTOSELECT=YES\n'
        '#EXT-X-MEDIA:URI="https://m/cc/hi",TYPE=SUBTITLES,GROUP-ID="vtt",LANGUAGE="hi",NAME="हिन्दी",DEFAULT=NO,AUTOSELECT=YES\n'
        '#EXT-X-MEDIA:URI="https://m/audio",TYPE=AUDIO,GROUP-ID="234",NAME="Default"\n';
    final t = hlsCaptionsOf(master, _base);
    expect([for (final c in t) c.language], ['en-IN', 'hi']);
    expect(t[1].name, 'हिन्दी');
    expect(t[0].url.toString(), 'https://m/cc/en');
  });

  test('which captions show', () {
    final en = CaptionTrack('en-IN', 'English (India)', _u);
    final hi = CaptionTrack('hi', 'हिन्दी', _u);
    final fil = CaptionTrack('fil', 'Filipino', _u);
    expect(captionTrackFor([fil, hi, en], ''), en, reason: 'English first');
    expect(captionTrackFor([fil, hi], ''), hi, reason: 'then Hindi');
    expect(captionTrackFor([fil], ''), fil, reason: 'then the first');
    expect(captionTrackFor([fil, hi, en], 'hi'), hi, reason: 'last pick');
    expect(captionTrackFor([fil, en], 'hi'), en, reason: 'pick not offered');
    expect(captionTrackFor([fil, hi, en], captionsOff), isNull);
    expect(captionTrackFor(const [], ''), isNull);
  });

  test('the caption line at a moment (YouTube WebVTT)', () {
    final captions = WebVTTCaptionFile('WEBVTT\nKind: captions\nLanguage: en\n\n'
            '00:00:15.766 --> 00:00:18.185\n♪ The club isn\'t the best place\nto find a lover ♪\n\n'
            '00:00:18.268 --> 00:00:20.103\n♪ So the bar is where I go ♪\n')
        .captions;
    expect(captions, hasLength(2));
    expect(captionAt(captions, const Duration(seconds: 10)), '');
    expect(captionAt(captions, const Duration(seconds: 16)),
        '♪ The club isn\'t the best place\nto find a lover ♪');
    expect(captionAt(captions, const Duration(milliseconds: 18220)), '');
    expect(captionAt(captions, const Duration(seconds: 19)),
        '♪ So the bar is where I go ♪');
    expect(captionAt(captions, const Duration(seconds: 30)), '');
  });

  test('data per hour', () {
    final hd = hlsVariantsOf(_master, _base).last;
    expect(dataPerHour(hd), '1.4 GB');
    expect(dataPerHour(hlsVariantsOf(_master, _base).first), '70 MB');
  });
}
