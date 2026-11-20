// The compulsory-update tour: finds the bell, opens it, and the glow hints.
//
// Run with: flutter test test/update_tour_test.dart

import 'package:Bloomee/screens/widgets/update_tour.dart';
import 'package:Bloomee/services/app_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    UpdateGate.requiredBuild.value = 0;
    UpdateGate.showingTour.value = false;
  });

  testWidgets('spotlight on the bell; tapping it ends the tour',
      (tester) async {
    final nav = GlobalKey<NavigatorState>();
    var bellOpened = false;
    UpdateGate.requiredBuild.value = 40;
    UpdateGate.showTour();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      builder: (_, child) => Stack(fit: StackFit.expand, children: [
        child!,
        ValueListenableBuilder<bool>(
          valueListenable: UpdateGate.showingTour,
          builder: (_, on, __) =>
              on ? UpdateTour(navigatorKey: nav) : const SizedBox.shrink(),
        ),
      ]),
      home: Scaffold(
        appBar: AppBar(actions: [
          KeyedSubtree(
            key: updateBellKey,
            child: IconButton(
                onPressed: () => bellOpened = true,
                icon: const Icon(Icons.notifications)),
          ),
        ]),
      ),
    ));
    await tester.pump(); // measure the bell
    await tester.pump(const Duration(milliseconds: 1200)); // entry animation
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Open the bell'), findsOneWidget, reason: 'bell visible');
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    // A tap on the spotlight hole (the real bell is covered by the tour)
    // opens the bell screen. Not pumped: NotificationView needs the app's
    // blocs and translations.
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.notifications)));
    expect(UpdateGate.showingTour.value, isFalse);
    expect(bellOpened, isFalse);
    expect(nav.currentState!.canPop(), isTrue, reason: 'bell screen pushed');
  });

  testWidgets('glow hint only while an update is compulsory', (tester) async {
    Widget app() => MaterialApp(
        home: Scaffold(
            body: UpdateGlow(
                hint: 'Tap Download update',
                child: FilledButton(
                    onPressed: () {}, child: const Text('Download')))));
    await tester.pumpWidget(app());
    expect(find.text('Tap Download update'), findsNothing);

    UpdateGate.requiredBuild.value = 40;
    await tester.pumpWidget(Container());
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Tap Download update'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });
}
