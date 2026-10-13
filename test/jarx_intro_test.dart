// JARX launch animation (Option C "Flatline").
//
// - Golden of the final frame, plus a check that it matches the approved
//   reference video's last frame (docs/branding/jarx/final_animation/
//   jarx-splash-C-flatline.mp4, frame 167, saved as a fixture).
// - Launch behaviour: tap to skip, init in parallel, hold until init is done,
//   reduced motion, start-up errors.
//
// Run with: flutter test test/jarx_intro_test.dart
// Re-pin the golden after an intended change: add --update-goldens.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show FrameTiming;

import 'package:Bloomee/screens/widgets/jarx_intro/jarx_intro_painter.dart';
import 'package:Bloomee/screens/widgets/jarx_intro/jarx_launch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadPoppins() async {
  final loader = FontLoader('Poppins')
    ..addFont(rootBundle.load('assets/fonts/Poppins/Poppins-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Poppins/Poppins-Bold.ttf'));
  await loader.load();
}

Future<Uint8List> _rgba(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

const _home = Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: Text('HOME')),
);

Widget _launch(Future<void> Function() init, {bool reduceMotion = false}) {
  final launch = JarxLaunch(init: init, app: (_) => _home);
  return reduceMotion
      ? MediaQuery(
          data: const MediaQueryData(disableAnimations: true), child: launch)
      : launch;
}

bool _introVisible(WidgetTester tester) => find
    .byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is JarxIntroPainter)
    .evaluate()
    .isNotEmpty;

void main() {
  setUpAll(_loadPoppins);

  group('final frame', () {
    testWidgets('golden', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final text = JarxIntroText();
      addTearDown(text.dispose);
      await tester.pumpWidget(RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: JarxIntroPainter(text: text, t: 2.8),
        ),
      ));
      await expectLater(find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/jarx_intro_final.png'));
    });

    testWidgets('matches the approved reference video', (tester) async {
      await tester.runAsync(() async {
        final text = JarxIntroText();
        final rec = ui.PictureRecorder();
        JarxIntroPainter(text: text, t: 2.8)
            .paint(Canvas(rec), const Size(1080, 1920));
        final ours = await _rgba(await rec.endRecording().toImage(1080, 1920));
        text.dispose();

        final codec = await ui.instantiateImageCodec(
            File('test/goldens/jarx_intro_reference_final.png').readAsBytesSync());
        final ref = await _rgba((await codec.getNextFrame()).image);

        var sum = 0, off = 0;
        for (var i = 0; i < ours.length; i += 4) {
          var worst = 0;
          for (var c = 0; c < 3; c++) {
            final d = (ours[i + c] - ref[i + c]).abs();
            sum += d;
            if (d > worst) worst = d;
          }
          if (worst > 40) off++;
        }
        final meanDiff = sum / (ours.length / 4 * 3);
        final offShare = off / (ours.length / 4);
        // The reference is an H.264 frame, so allow compression noise.
        expect(meanDiff, lessThan(3.0));
        expect(offShare, lessThan(0.01));
      });
    });
  });

  test('timing summary', () {
    FrameTiming frame(int buildMs, int rasterMs) {
      final b = buildMs * 1000, r = rasterMs * 1000;
      return FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: b,
        rasterStart: b,
        rasterFinish: b + r,
        rasterFinishWallTime: b + r,
      );
    }

    final s = introTimingSummary([
      for (var i = 0; i < 98; i++) frame(4, 6),
      frame(20, 5), // slow build
      frame(3, 30), // slow raster
    ]);
    expect(s, contains('100 frames'));
    expect(s, contains('build p50 4.0'));
    expect(s, contains('raster p50 6.0'));
    expect(s, contains('max 30.0 ms'));
    expect(s, endsWith('over 16.7 ms: 2'));
    expect(introTimingSummary(const []), contains('no frames'));
  });

  group('launch', () {
    testWidgets('init starts right after the first frame, not after the intro',
        (tester) async {
      var started = false;
      await tester.pumpWidget(_launch(() async => started = true));
      await tester.pump();
      expect(started, isTrue);
      expect(_introVisible(tester), isTrue);
      await tester.pump(const Duration(seconds: 4)); // let timers finish
    });

    testWidgets('plays 2.8 s, then cross-fades into the app', (tester) async {
      await tester.pumpWidget(_launch(() async {}));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('HOME'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1300)); // 2.8 s
      await tester.pump(const Duration(milliseconds: 100)); // mid-fade
      expect(find.text('HOME'), findsOneWidget);
      expect(_introVisible(tester), isTrue);
      // The 200 ms fade starts on the frame after the intro ends.
      await tester.pump(const Duration(milliseconds: 250));
      expect(_introVisible(tester), isFalse);
    });

    testWidgets('a tap anywhere skips the intro', (tester) async {
      await tester.pumpWidget(_launch(() async {}));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('HOME'), findsOneWidget);
      expect(_introVisible(tester), isFalse);
    });

    testWidgets('holds the last frame until init finishes', (tester) async {
      final init = Completer<void>();
      await tester.pumpWidget(_launch(() => init.future));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('HOME'), findsNothing);
      expect(_introVisible(tester), isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse); // no busy repaint

      init.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('a skip before init finishes holds the last frame',
        (tester) async {
      final init = Completer<void>();
      await tester.pumpWidget(_launch(() => init.future));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('HOME'), findsNothing);
      init.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('remove-animations: last frame for 300 ms, no motion',
        (tester) async {
      await tester.pumpWidget(_launch(() async {}, reduceMotion: true));
      await tester.pump();
      final painter = tester
          .widget<CustomPaint>(find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is JarxIntroPainter))
          .painter as JarxIntroPainter;
      expect(painter.t, closeTo(2.8, 1e-9)); // already the last frame
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('HOME'), findsNothing);
      await tester.pump(const Duration(milliseconds: 60)); // 310 ms
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('a failed start-up says so instead of hanging', (tester) async {
      await tester.pumpWidget(_launch(() => Future.error(StateError('db'))));
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('JARX could not start.'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
    });
  });
}
