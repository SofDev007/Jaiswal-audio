// Lyrics "Adjust delay": tap a line when it's heard → the delay, and how
// the delay reads. Positive = lyrics shown earlier, negative = later.
//
// Run with: flutter test test/lyrics_sync_test.dart

import 'package:Bloomee/screens/screen/player_views/fullscreen_lyrics_view.dart';
import 'package:flutter_test/flutter_test.dart';

Duration s(double sec) => Duration(milliseconds: (sec * 1000).round());

void main() {
  test('line sung later than the lyrics say: lyrics move later', () {
    // Line at 0:10 in the lyrics, heard (tapped) at 0:12.15.
    final d = lyricsSyncOffset(s(10), s(12.15));
    expect(d, s(-2));
    expect(lyricsDelayLabel(d), 'Lyrics 2.0 s later');
  });

  test('line sung earlier than the lyrics say: lyrics move earlier', () {
    final d = lyricsSyncOffset(s(30), s(26.65));
    expect(d, s(3.5));
    expect(lyricsDelayLabel(d), 'Lyrics 3.5 s earlier');
  });

  test('a tap right on time (after reaction) means in time', () {
    final d = lyricsSyncOffset(s(5), s(5) + lyricsTapReaction);
    expect(d, Duration.zero);
    expect(lyricsDelayLabel(d), 'Lyrics in time');
  });

  test('labels', () {
    expect(lyricsDelayLabel(s(0.03)), 'Lyrics in time');
    expect(lyricsDelayLabel(s(-0.1)), 'Lyrics 0.1 s later');
    expect(lyricsDelayLabel(s(12)), 'Lyrics 12 s earlier');
  });
}
