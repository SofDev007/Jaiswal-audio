import 'package:Bloomee/core/models/lyrics_models.dart';
import 'package:Bloomee/screens/widgets/player_lyric_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('words get start times in order, inside the line', () {
    const start = Duration(seconds: 10), end = Duration(seconds: 14);
    final s = wordStarts(['Tum', 'hi', 'ho', 'zindagi'], start, end);
    expect(s.first, start);
    for (var i = 1; i < s.length; i++) {
      expect(s[i] > s[i - 1], isTrue);
    }
    expect(s.last < end, isTrue);
    // A longer word gets more time: 'zindagi' (to the end of the sung part,
    // 85% of the line) vs 'hi'.
    final sungEnd = start + const Duration(milliseconds: 3400);
    expect(sungEnd - s[3] > s[2] - s[1], isTrue);
  });

  test('the line being sung is found by position', () {
    final lines = [
      ParsedLyric(text: 'a', start: const Duration(seconds: 5)),
      ParsedLyric(text: 'b', start: const Duration(seconds: 9)),
      ParsedLyric(text: 'c', start: const Duration(seconds: 12)),
    ];
    expect(lyricIndexAt(lines, const Duration(seconds: 2)), -1);
    expect(lyricIndexAt(lines, const Duration(seconds: 5)), 0);
    expect(lyricIndexAt(lines, const Duration(seconds: 11)), 1);
    expect(lyricIndexAt(lines, const Duration(minutes: 3)), 2);
  });

  test('LRCLIB lyrics parse: no space after the tag, hundredths', () {
    final p = ParsedLyrics(
      syncedLyrics: '[00:11.20]Hum tere bin ab reh nahi sakte\n'
          '[00:15.55] Tere bina kya wajood mera\r\n'
          '[00:20.00]\n'
          '[01:02.345]Tum hi ho',
      duration: '261',
    );
    expect(p.lyrics.length, 4);
    expect(p.lyrics[0].text, 'Hum tere bin ab reh nahi sakte');
    expect(p.lyrics[0].start, const Duration(seconds: 11, milliseconds: 200));
    expect(p.lyrics[1].text, 'Tere bina kya wajood mera');
    expect(p.lyrics[2].text, '');
    expect(p.lyrics[3].start,
        const Duration(minutes: 1, seconds: 2, milliseconds: 345));
  });
}
