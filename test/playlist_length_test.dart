// The playlist's total length, shown like Spotify ("4h 36min").

import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/screens/screen/library_views/playlist_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(int seconds) => Track(
      id: 'x$seconds',
      title: 't',
      artists: const [],
      durationMs: BigInt.from(seconds * 1000),
      thumbnail: const Artwork(url: '', layout: ImageLayout.square),
      isExplicit: false,
    );

void main() {
  test('hours and minutes, minutes alone, or nothing', () {
    expect(playlistLength([_t(4 * 3600), _t(36 * 60)]), '4h 36min');
    expect(playlistLength([_t(45 * 60)]), '45 min');
    expect(playlistLength([_t(20)]), '1 min');
    expect(
        playlistLength([
          Track(
              id: 'n',
              title: 'n',
              artists: const [],
              thumbnail: const Artwork(url: '', layout: ImageLayout.square),
              isExplicit: false)
        ]),
        isNull);
  });
}
