// Offline tab: songs downloaded with "Download all" show as their playlist,
// not mixed in with songs downloaded one by one.

import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/downloaded_playlists.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String id) => Track(
      id: id,
      title: id,
      artists: const [],
      thumbnail: const Artwork(url: '', layout: ImageLayout.square),
      isExplicit: false,
    );

void main() {
  test('playlist songs group under the playlist, the rest stay singles', () {
    final downloaded = [_t('a'), _t('b'), _t('c'), _t('d')];
    final g = DownloadedPlaylists.group(downloaded, [
      (title: 'Soothing', ids: ['c', 'a', 'x']), // x not downloaded (yet)
      (title: 'Deleted all', ids: ['y']),
    ]);
    expect(g.playlists, hasLength(1));
    expect(g.playlists.single.title, 'Soothing');
    expect([for (final t in g.playlists.single.tracks) t.id], ['c', 'a']);
    expect([for (final t in g.singles) t.id], ['b', 'd']);
  });
}
