// JARX loading indicator: sizes like the Material spinner it replaces,
// animates, holds still when animations are off, and picks its colour.
//
// Run with: flutter test test/jarx_loading_indicator_test.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:Bloomee/screens/widgets/jarx_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

final _key = GlobalKey();

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(child: RepaintBoundary(key: _key, child: child)),
        ),
      ),
    );

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary =
      _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

void main() {
  testWidgets('unconstrained it is 36×36, like CircularProgressIndicator',
      (tester) async {
    await tester.pumpWidget(_host(const JarxLoadingIndicator()));
    expect(tester.getSize(find.byType(JarxLoadingIndicator)),
        const Size(36, 36));
  });

  testWidgets('fills the box it is given', (tester) async {
    await tester.pumpWidget(_host(const SizedBox(
        width: 16, height: 16, child: JarxLoadingIndicator())));
    expect(tester.getSize(find.byType(JarxLoadingIndicator)),
        const Size(16, 16));
  });

  testWidgets('the bars move over time', (tester) async {
    await tester.pumpWidget(_host(const SizedBox(
        width: 48, height: 48, child: JarxLoadingIndicator(color: Colors.red))));
    final a = await _pixels(tester);
    await tester.pump(const Duration(milliseconds: 150));
    final b = await _pixels(tester);
    expect(a, isNot(equals(b)));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('with animations turned off the bars hold still',
      (tester) async {
    await tester.pumpWidget(_host(
        const SizedBox(
            width: 48, height: 48, child: JarxLoadingIndicator(color: Colors.red)),
        reduceMotion: true));
    final a = await _pixels(tester);
    await tester.pump(const Duration(milliseconds: 150));
    final b = await _pixels(tester);
    expect(a, equals(b));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('colour: explicit, then valueColor, then the theme',
      (tester) async {
    Color painted() => (tester
            .widget<CustomPaint>(find.descendant(
                of: find.byType(JarxLoadingIndicator),
                matching: find.byType(CustomPaint)))
            .painter as dynamic)
        .color as Color;

    await tester.pumpWidget(_host(const JarxLoadingIndicator(color: Colors.red)));
    expect(painted(), Colors.red);

    await tester.pumpWidget(_host(const JarxLoadingIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue))));
    expect(painted(), Colors.blue);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          progressIndicatorTheme:
              const ProgressIndicatorThemeData(color: Colors.green)),
      home: const Scaffold(body: Center(child: JarxLoadingIndicator())),
    ));
    await tester.pump(const Duration(milliseconds: 300)); // theme cross-fade
    expect(painted(), Colors.green);
  });

  testWidgets('a semantics label is exposed when given', (tester) async {
    await tester.pumpWidget(
        _host(const JarxLoadingIndicator(semanticsLabel: 'Loading songs')));
    expect(find.bySemanticsLabel('Loading songs'), findsOneWidget);
  });
}
