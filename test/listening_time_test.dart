// Listening time counts only what was really played: not seeks or pauses.

import 'package:Bloomee/services/player/listening_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal playback counts', () {
    expect(playedBetween(10000, 10500, 500), 500);
    expect(playedBetween(10000, 11200, 500), 1200); // small jitter is fine
  });

  test('seeks and going back do not count', () {
    expect(playedBetween(10000, 60000, 500), 0); // jumped ahead
    expect(playedBetween(60000, 10000, 500), 0); // jumped back / replay
    expect(playedBetween(10000, 10000, 5000), 0); // paused
  });

  test('stats survive a save and load', () {
    final s = ListeningStats(DateTime(2026, 11, 13), 90000,
        {'arijit singh': (name: 'Arijit Singh', ms: 60000)});
    final back = ListeningStats.fromJson(s.toJson());
    expect(back.totalMs, 90000);
    expect(back.artists['arijit singh']?.name, 'Arijit Singh');
    expect(back.since, DateTime(2026, 11, 13));
  });

  test('a play counts after 30 s, or half a short song', () {
    expect(countsAsPlay(29000, 240000), isFalse);
    expect(countsAsPlay(30000, 240000), isTrue);
    expect(countsAsPlay(20000, 40000), isTrue); // half of a 40 s song
    expect(countsAsPlay(19000, 40000), isFalse);
    expect(countsAsPlay(30000, null), isTrue); // length unknown
  });

  test('starting a song over is a new play, a small seek back is not', () {
    expect(restarted(200000, 500), isTrue);
    expect(restarted(8000, 500), isFalse);
    expect(restarted(200000, 150000), isFalse);
  });

  test('song counts survive a save and load and rank by plays', () {
    final s = ListeningStats(DateTime(2026, 11, 13), 0, {}, {
      'a': (title: 'Tum Hi Ho', artist: 'Arijit Singh', plays: 3, ms: 600000),
      'b': (title: 'Kesariya', artist: 'Arijit Singh', plays: 5, ms: 900000),
      'c': (title: 'Ilahi', artist: 'Arijit Singh', plays: 5, ms: 950000),
    });
    final back = ListeningStats.fromJson(s.toJson());
    expect(back.songs['b']?.plays, 5);
    expect(back.topSongs(2).map((t) => t.title), ['Ilahi', 'Kesariya']);
    // A record saved before song counts existed still loads.
    final old = ListeningStats.fromJson({'totalMs': 5, 'artists': {}});
    expect(old.songs, isEmpty);
  });
}
