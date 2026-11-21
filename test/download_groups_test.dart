import 'package:Bloomee/screens/screen/offline_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active downloads group under their "Download all" playlist', () {
    const saved = [
      (title: 'Soothing', ids: ['a', 'b', 'c']),
      (title: 'Empty now', ids: ['z']),
      (title: 'Gym', ids: ['c', 'd']),
    ];
    // Rows are song ids; 'x' was downloaded on its own.
    final g = groupActiveDownloads<String>(['d', 'x', 'b', 'c'], (r) => r, saved);

    expect(g.playlists.map((p) => p.title), ['Soothing', 'Gym'],
        reason: 'saved order; a playlist with nothing downloading is left out');
    expect(g.playlists[0].rows, ['b', 'c']);
    expect(g.playlists[1].rows, ['d'],
        reason: "'c' is shown once, in the first playlist that has it");
    expect(g.singles, ['x']);
  });

  test('nothing saved: every download is a single', () {
    final g = groupActiveDownloads<String>(['a', 'b'], (r) => r, const []);
    expect(g.playlists, isEmpty);
    expect(g.singles, ['a', 'b']);
  });
}
