import 'package:Bloomee/screens/widgets/like_widget.dart';
import 'package:Bloomee/screens/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('like button: tap likes (with burst), tap again unlikes',
      (tester) async {
    var liked = 0, unliked = 0;
    Widget build(bool isLiked) => MaterialApp(
          home: Scaffold(
            body: LikeBtnWidget(
              isLiked: isLiked,
              onLiked: () => liked++,
              onDisliked: () => unliked++,
            ),
          ),
        );

    await tester.pumpWidget(build(false));
    await tester.tap(find.byType(IconButton));
    await tester.pump(const Duration(milliseconds: 200)); // mid-burst
    expect(liked, 1);
    await tester.pumpAndSettle();

    await tester.pumpWidget(build(true));
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(unliked, 1);
    expect(liked, 1);
  });

  testWidgets('skeleton list shows the requested rows and animates',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SkeletonSongList(count: 3)),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.byType(Row), findsNWidgets(3));
  });
}
