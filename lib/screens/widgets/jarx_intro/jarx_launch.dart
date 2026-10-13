import 'dart:async';
import 'dart:developer';

import 'package:Bloomee/screens/widgets/jarx_intro/jarx_intro_painter.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// Device-verification switches, off (and compiled out) unless set with
// --dart-define. See docs/device-test-jarx-launch.md.

/// `JARX_INTRO_TIMINGS=true`: print the intro's frame times to logcat.
const bool _kLogTimings = bool.fromEnvironment('JARX_INTRO_TIMINGS');

/// `JARX_SIMULATE_STARTUP_ERROR=true`: fail start-up on purpose, before
/// anything is opened or written, to check the error screen on a device.
const bool _kSimulateStartupError =
    bool.fromEnvironment('JARX_SIMULATE_STARTUP_ERROR');

/// One line summarising [frames]: count, build and raster time percentiles,
/// and how many frames missed a 60 Hz deadline.
String introTimingSummary(List<FrameTiming> frames) {
  if (frames.isEmpty) return 'JARX intro timings: no frames';
  String stats(List<Duration> d) {
    final ms = d.map((x) => x.inMicroseconds / 1000).toList()..sort();
    double pct(double p) => ms[((ms.length - 1) * p).round()];
    String f(double v) => v.toStringAsFixed(1);
    return 'p50 ${f(pct(.5))} p90 ${f(pct(.9))} p99 ${f(pct(.99))} '
        'max ${f(ms.last)} ms';
  }

  const budget = Duration(microseconds: 16667);
  final slow = frames
      .where((f) => f.buildDuration > budget || f.rasterDuration > budget)
      .length;
  return 'JARX intro timings: ${frames.length} frames | '
      'build ${stats([for (final f in frames) f.buildDuration])} | '
      'raster ${stats([for (final f in frames) f.rasterDuration])} | '
      'over 16.7 ms: $slow';
}

/// Root of the app on a cold start: plays the JARX intro while [init] runs,
/// then cross-fades into [app].
///
/// - [init] starts right after the intro's first frame, so its blocking parts
///   (opening the database) happen while the screen is still plain ink.
/// - The animation never waits for [init]; if [init] is still running at the
///   end, the last frame holds until it finishes.
/// - A tap anywhere skips to the end.
/// - With the system's "remove animations" on, the last frame shows for
///   300 ms without motion.
/// - Warm resumes keep the running app, so the intro only plays when the
///   process starts.
class JarxLaunch extends StatefulWidget {
  const JarxLaunch({super.key, required this.init, required this.app});

  final Future<void> Function() init;
  final WidgetBuilder app;

  @override
  State<JarxLaunch> createState() => _JarxLaunchState();
}

const Duration _kCrossFade = Duration(milliseconds: 200);
const Duration _kReducedMotionHold = Duration(milliseconds: 300);

class _JarxLaunchState extends State<JarxLaunch> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: kJarxIntroDuration);
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: _kCrossFade);
  final JarxIntroText _text = JarxIntroText();

  bool _initDone = false;
  Object? _initError;
  bool _introDone = false;
  bool _showApp = false;
  bool _introGone = false;
  bool _started = false;
  final List<FrameTiming> _timings = [];

  void _collectTimings(List<FrameTiming> t) => _timings.addAll(t);

  @override
  void initState() {
    super.initState();
    if (_kLogTimings) {
      SchedulerBinding.instance.addTimingsCallback(_collectTimings);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _startInit());
    _fade.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      setState(() => _introGone = true);
      if (_kLogTimings) {
        SchedulerBinding.instance.removeTimingsCallback(_collectTimings);
        debugPrint(introTimingSummary(_timings));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // The app root sits above any MediaQuery, so fall back to the platform.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    if (reduceMotion) {
      _intro.value = 1;
      Future<void>.delayed(_kReducedMotionHold, _finishIntro);
    } else {
      _intro.forward().whenComplete(_finishIntro);
    }
  }

  void _startInit() {
    final init = _kSimulateStartupError
        ? Future<void>.error(StateError('Simulated start-up error'))
        : widget.init();
    init.then((_) {
      _initDone = true;
      _maybeReveal();
    }, onError: (Object e, StackTrace s) {
      log('App start-up failed', error: e, stackTrace: s, name: 'JarxLaunch');
      if (mounted) setState(() => _initError = e);
    });
  }

  void _skip() {
    if (_introDone) return;
    _intro.stop();
    _intro.value = 1;
    _finishIntro();
  }

  void _finishIntro() {
    if (_introDone || !mounted) return;
    _introDone = true;
    _maybeReveal();
  }

  void _maybeReveal() {
    if (!mounted || !_introDone || !_initDone || _showApp) return;
    setState(() => _showApp = true);
    _fade.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _fade.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intro = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: CustomPaint(
        size: Size.infinite,
        painter: JarxIntroPainter(text: _text, progress: _intro),
        child: _initError == null
            ? null
            : Align(
                alignment: const Alignment(0, 0.75),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'JARX could not start.\n$_initError',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kJarxPaper, fontSize: 14),
                  ),
                ),
              ),
      ),
    );
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        if (_showApp) widget.app(context),
        if (!_introGone)
          IgnorePointer(
            ignoring: _showApp,
            child: FadeTransition(
              opacity: ReverseAnimation(_fade),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: intro,
              ),
            ),
          ),
      ],
    );
  }
}
