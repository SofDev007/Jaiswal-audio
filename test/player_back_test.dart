// Back press while the player is open: sub-screen, then Up Next, then the
// player itself; the page under the player is never popped.

import 'package:Bloomee/blocs/player_overlay/player_overlay_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('back order with the player open', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester
        .pumpWidget(MaterialApp(navigatorKey: nav, home: const Text('page')));
    final cubit = PlayerOverlayCubit();
    var upNextExpanded = true;
    cubit.registerUpNextPanelCollapse(() {
      final was = upNextExpanded;
      upNextExpanded = false;
      return was;
    });

    // Player closed: not handled, so the caller navigates pages.
    expect(cubit.handleBack(nav.currentState!), isFalse);

    cubit.showPlayer();
    nav.currentState!
        .push(MaterialPageRoute(builder: (_) => const Text('lyrics')));
    await tester.pumpAndSettle();

    // 1. The screen opened from the player closes; the player stays open.
    expect(cubit.handleBack(nav.currentState!), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('lyrics'), findsNothing);
    expect(cubit.state, isTrue);

    // 2. Up Next collapses.
    expect(cubit.handleBack(nav.currentState!), isTrue);
    expect(upNextExpanded, isFalse);
    expect(cubit.state, isTrue);

    // 3. The player slides down; the page underneath is still there.
    expect(cubit.handleBack(nav.currentState!), isTrue);
    expect(cubit.state, isFalse);
    expect(find.text('page'), findsOneWidget);

    // 4. Player closed again: back goes to page navigation.
    expect(cubit.handleBack(nav.currentState!), isFalse);
    await cubit.close();
  });
}
