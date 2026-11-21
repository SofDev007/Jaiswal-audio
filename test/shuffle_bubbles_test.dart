import 'package:Bloomee/screens/widgets/shuffle_bubbles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Build 41 bug: tapping a playlist's shuffle button did nothing. Opening
// wrapped the OverlayPortal in a BackButtonListener, which rebuilt it and
// detached its controller, so the bubbles never showed.
void main() {
  testWidgets('shuffle button opens the bubbles, every time', (tester) async {
    var shuffled = 0;
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: Center(
              child: ShuffleBubbles(
                button: (onTap) => IconButton(
                    key: const Key('shuffle'),
                    onPressed: onTap,
                    icon: const Icon(Icons.shuffle)),
                onShuffle: () => shuffled++,
                onSmartShuffle: () {},
              ),
            ),
          ),
        ),
      ]),
    ));

    for (var round = 1; round <= 2; round++) {
      await tester.tap(find.byKey(const Key('shuffle')));
      await tester.pumpAndSettle();
      expect(find.text('Smart shuffle'), findsOneWidget, reason: 'round $round');
      expect(find.text('Shuffle'), findsOneWidget, reason: 'round $round');

      await tester.tap(find.text('Shuffle'));
      await tester.pumpAndSettle();
      expect(shuffled, round);
      expect(find.text('Smart shuffle'), findsNothing);
    }
  });
}
