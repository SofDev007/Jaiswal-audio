// Picking the music video out of the YouTube Video plugin's streams.
//
// Run with: flutter test test/video_streams_test.dart

import 'package:Bloomee/services/player/video_streams.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/recs_dataset.dart';

String link(int itag, String mime) =>
    'https://rr1.googlevideo.com/videoplayback?expire=1&itag=$itag'
    '&mime=${Uri.encodeQueryComponent(mime)}&id=abc';

void main() {
  test('only streams with a picture, lowest first, one per height', () {
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

  test('YouTube songs have videos, others don\'t', () {
    bool from(String plugin) => hasVideo(tr('abc', 'Song', 'A', plugin: plugin));
    expect(from('content-resolver.bloomfactory.ytmusic'), isTrue);
    expect(from('content-resolver.bloomfactory.ytvideo'), isTrue);
    expect(from('content-resolver.bloomfactory.jiosaavn'), isFalse);
    expect(from('local'), isFalse);
  });
}
