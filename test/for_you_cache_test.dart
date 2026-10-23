// The Home "For you" picks survive a save and load, and expire.

import 'package:Bloomee/screens/screen/home_views/home_rows.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 10, 23, 12);
  final picks = <ForYouPick>[
    (
      Track(
        id: 'yt::zara-sa',
        title: 'Zara Sa',
        artists: const [ArtistSummary(id: 'kk', name: 'KK')],
        thumbnail: const Artwork(
            url: 'https://img/1',
            urlHigh: 'https://img/1h',
            layout: ImageLayout.square),
        isExplicit: false,
        durationMs: BigInt.from(301000),
      ),
      const RecReason(RecReasonKind.similarTo, 'Mohit Chauhan'),
    ),
  ];

  test('round trip keeps what the cards show and play', () {
    final raw = encodeForYou('seed', at, picks);
    final back = decodeForYou(raw, 'seed', at.add(const Duration(hours: 1)))!;
    final (t, r) = back.single;
    expect(t.id, 'yt::zara-sa');
    expect(t.title, 'Zara Sa');
    expect(t.artists.single.name, 'KK');
    expect(t.thumbnail.urlHigh, 'https://img/1h');
    expect(t.thumbnail.layout, ImageLayout.square);
    expect(t.durationMs, BigInt.from(301000));
    expect(r, const RecReason(RecReasonKind.similarTo, 'Mohit Chauhan'));
  });

  test('another seed, an old save or bad data give null', () {
    final raw = encodeForYou('seed', at, picks);
    expect(decodeForYou(raw, 'other', at), isNull);
    expect(decodeForYou(raw, 'seed', at.add(const Duration(hours: 7))), isNull);
    expect(decodeForYou('not json', 'seed', at), isNull);
    expect(decodeForYou(null, 'seed', at), isNull);
  });
}
