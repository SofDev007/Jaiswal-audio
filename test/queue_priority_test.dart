// "Add to queue" order: now playing → the user's queue (first in, first
// out) → rest of the playlist → recommendations.
//
// Run with: flutter test test/queue_priority_test.dart

import 'package:Bloomee/services/player/queue_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/recs_dataset.dart';

final _p = [for (var i = 0; i < 4; i++) tr('p$i', 'Playlist $i', 'A$i')];
final _q1 = tr('q1', 'Queued 1', 'Q');
final _q2 = tr('q2', 'Queued 2', 'Q');
final _r = [for (var i = 0; i < 2; i++) tr('r$i', 'Rec $i', 'R$i')];

List<String> _order(QueueManager m) {
  String id(QueueManager m) => m.currentTrack!.id.split('::').last;
  final out = [id(m)];
  while (m.advanceToNext()) {
    out.add(id(m));
  }
  return out;
}

void main() {
  test('single song: queued songs play before recommendations', () {
    final m = QueueManager()..loadTracks([_p[0]]);
    m.addTracks(_r, atLast: true); // autoplay batch
    m.addTrack(_q1);
    m.addTrack(_q2);
    expect(_order(m), ['p0', 'q1', 'q2', 'r0', 'r1']);
  });

  test('playlist: queued songs jump ahead of the rest of the playlist', () {
    final m = QueueManager()..loadTracks(_p, idx: 1);
    m.addTrack(_q1);
    m.addTrack(_q2);
    expect(_order(m), ['p1', 'q1', 'q2', 'p2', 'p3']);
  });

  test('a song queued while a queued song plays goes after the others', () {
    final m = QueueManager()..loadTracks(_p);
    m.addTrack(_q1);
    m.addTrack(_q2);
    m.advanceToNext(); // now playing q1
    m.addTrack(tr('q3', 'Queued 3', 'Q'));
    expect(_order(m), ['q1', 'q2', 'q3', 'p1', 'p2', 'p3']);
  });

  test('shuffled playlist: queued songs still come next, in order', () {
    final m = QueueManager()..loadTracks(_p, shuffling: true);
    final first = m.currentTrack!.id.split('::').last;
    m.addTrack(_q1);
    m.addTrack(_q2);
    final order = _order(m);
    expect(order.take(3), [first, 'q1', 'q2']);
    expect(order.toSet(), hasLength(6));
  });

  test('a new playlist forgets the old queue marks', () {
    final m = QueueManager()..loadTracks([_p[0]]);
    m.addTrack(_q1);
    m.loadTracks([_q1, _p[1], _p[2]]);
    m.addTrack(_q2);
    expect(_order(m), ['q1', 'q2', 'p1', 'p2']);
  });

  group('smart shuffle', () {
    final list = [for (var i = 0; i < 7; i++) tr('s$i', 'Song $i', 'S$i')];
    final picks = [for (var i = 0; i < 3; i++) tr('x$i', 'Pick $i', 'X$i')];

    test('one pick after every 3 songs', () {
      final m = QueueManager()..loadTracks(list);
      m.insertEvery(3, picks);
      expect(_order(m),
          ['s0', 's1', 's2', 'x0', 's3', 's4', 's5', 'x1', 's6']);
    });

    test('never behind the song playing now', () {
      final m = QueueManager()..loadTracks(list, idx: 4);
      m.insertEvery(3, picks);
      expect(_order(m), ['s4', 's5', 'x0', 's6']);
    });

    test('skipped while shuffle is on', () {
      final m = QueueManager()..loadTracks(list, shuffling: true);
      m.insertEvery(3, picks);
      expect(_order(m), hasLength(7));
    });
  });
}
