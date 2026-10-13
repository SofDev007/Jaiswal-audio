/// JARX launch animation, Option C "Flatline": a native port of `opt_ekg()` in
/// docs/branding/jarx/final_animation/render.py, which is the source of truth
/// for every timing, easing and size below.
///
/// Everything is laid out on the 1080×1920 design frame and scaled to the
/// screen (by width on phones; to fit on wide windows), the frame centred.
library jarx_intro_painter;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The line under the wordmark. One place to change it.
const String kJarxTagline = 'JAISWAL AUDIO RESPONSE EXPERIENCE';

/// Length of the animation; after this the last frame holds.
const Duration kJarxIntroDuration = Duration(milliseconds: 2800);

const Color kJarxInk = Color(0xFF0E0E10);
const Color kJarxPulse = Color(0xFFFF4D2E);
const Color kJarxPaper = Color(0xFFF5F5F5);

// Design frame and mark placement (render.py: W, H, MARK_CY, MARK_S, STROKE).
const double _w = 1080, _h = 1920;
const double _markCx = 540, _markCy = 790, _unit = 5;
const double _stroke = 10 * _unit; // 50 px
const double _traceWidth = 7;
const double _glowSigma = 36; // render.py: blur radius 9 on a 1/4-size layer

Offset _xf(double x, double y) =>
    Offset(_markCx + (x - 60) * _unit, _markCy + (y - 60) * _unit);

// ── easing (render.py) ──────────────────────────────────────────────────────
double _clamp(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
double _seg(double t, double a, double b) => _clamp((t - a) / (b - a));
double _inOut3(double x) =>
    x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
double _out3(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _out5(double x) => 1 - math.pow(1 - x, 5).toDouble();
double _lerp(double a, double b, double x) => a + (b - a) * x;

/// The head's route: a flat lead-in from off-screen left along the mark's
/// y = 38, then the mark (M32 38 … A20 20 0 0 1 48 78).
class _Route {
  _Route() {
    const leadX0 = 60 - (_w / 2 + 80) / _unit; // render.py: lead_x0
    final full = Path()..moveTo(_xf(leadX0, 38).dx, _xf(leadX0, 38).dy);
    _lineTo(full, 32, 38);
    final mark = Path()..moveTo(_xf(32, 38).dx, _xf(32, 38).dy);
    for (final p in const [
      [46.0, 38.0], [53.0, 22.0], [62.0, 54.0], [68.0, 38.0], //
      [88.0, 38.0], [88.0, 78.0],
    ]) {
      _lineTo(full, p[0], p[1]);
      _lineTo(mark, p[0], p[1]);
    }
    for (final p in [full, mark]) {
      p.arcToPoint(_xf(48, 78),
          radius: const Radius.circular(20 * _unit), clockwise: true);
    }
    route = full.computeMetrics().single;
    this.mark = mark.computeMetrics().single;
    lead = (32 - leadX0) * _unit;
  }

  static void _lineTo(Path p, double x, double y) {
    final o = _xf(x, y);
    p.lineTo(o.dx, o.dy);
  }

  late final ui.PathMetric route;
  late final ui.PathMetric mark;
  late final double lead; // px from the route start to the mark start
}

final _Route _routeOnce = _Route();

/// Glyph painters for the wordmark and tagline, laid out once.
class JarxIntroText {
  JarxIntroText()
      : word = _glyphs('JARX', 150, FontWeight.w700),
        tagSize = _fitSize(kJarxTagline, 30, 0.2, 880) {
    tag = _glyphs(kJarxTagline, tagSize, FontWeight.w400);
  }

  final List<TextPainter> word;
  final double tagSize;
  late final List<TextPainter> tag;

  static TextPainter _glyph(String ch, double size, FontWeight weight) =>
      TextPainter(
        text: TextSpan(
          text: ch,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: size,
            fontWeight: weight,
            color: kJarxPaper,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  static List<TextPainter> _glyphs(String s, double size, FontWeight weight) =>
      [for (final ch in s.split('')) _glyph(ch, size, weight)];

  /// render.py fit_size: shrink from [size] until tracked width ≤ [maxW].
  static double _fitSize(String s, double size, double trackEm, double maxW) {
    while (size > 10) {
      final glyphs = _glyphs(s, size, FontWeight.w400);
      final w = glyphs.fold<double>(0, (a, g) => a + g.width) +
          trackEm * size * (s.length - 1);
      for (final g in glyphs) {
        g.dispose();
      }
      if (w <= maxW) return size;
      size -= 1;
    }
    return size;
  }

  void dispose() {
    for (final g in [...word, ...tag]) {
      g.dispose();
    }
  }
}

/// Paints the intro at time [t] seconds (or [progress] × duration).
class JarxIntroPainter extends CustomPainter {
  JarxIntroPainter({required this.text, this.progress, double? t})
      : _fixedT = t,
        super(repaint: progress);

  final JarxIntroText text;
  final Animation<double>? progress;
  final double? _fixedT;

  double get t =>
      _fixedT ??
      (progress?.value ?? 1) * kJarxIntroDuration.inMilliseconds / 1000;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kJarxInk);
    final k = math.min(size.width / _w, size.height / _h);
    canvas.save();
    canvas.translate((size.width - _w * k) / 2, (size.height - _h * k) / 2);
    canvas.scale(k);
    _paintDesign(canvas, t);
    canvas.restore();
  }

  void _paintDesign(Canvas canvas, double t) {
    final r = _routeOnce;
    final total = r.route.length;
    final p = _inOut3(_seg(t, 0.05, 1.5));
    final len = p * total;

    // 1–2. Lead-in trace: thin, fading with distance behind the head and,
    // from 0.85 s to 1.25 s, entirely.
    final fadeAll = 1 - _seg(t, 0.85, 1.25);
    final leadEnd = math.min(len, r.lead);
    if (fadeAll > 0 && leadEnd > 0) {
      final extra = math.max(0.0, len - r.lead) * 0.6; // px
      // render.py strokes the trace as 300 short round-capped segments that
      // overlap: each point is covered by (segment + cap) / segment of them,
      // which makes the trace denser than one segment's alpha.
      final segLen = r.lead / 300;
      final cover = (segLen + _traceWidth) / segLen;
      double alphaAt(double l) {
        final a = math.exp(-((leadEnd - l) + extra) / _unit / 55) * fadeAll;
        return 1 - math.pow(1 - a, cover).toDouble();
      }
      const stops = 24;
      final start = r.route.getTangentForOffset(0)!.position;
      final end = r.route.getTangentForOffset(leadEnd)!.position;
      canvas.drawLine(
        start,
        end,
        Paint()
          ..strokeWidth = _traceWidth
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(start, end, [
            for (var i = 0; i <= stops; i++)
              kJarxPulse.withValues(alpha: alphaAt(leadEnd * i / stops)),
          ], [
            for (var i = 0; i <= stops; i++) i / stops,
          ]),
      );
    }

    // 3. The mark: the stroke thickens from the trace to full weight over its
    // first 12 units.
    Path? sub;
    var grow = 0.0;
    if (len > r.lead) {
      final ml = len - r.lead;
      sub = r.mark.extractPath(0, ml);
      grow = _lerp(_traceWidth, _stroke, _out3(_clamp(ml / _unit / 12)));
      canvas.drawPath(sub, _strokePaint(kJarxPulse, grow));
    }

    // 4. Head: a paper dot (12 px on the lead-in, 16 px on the mark).
    Offset? head;
    if (p > 0 && p < 1) {
      head = r.route.getTangentForOffset(len)!.position;
      canvas.drawCircle(head, len < r.lead ? 12 : _stroke * 0.32,
          Paint()..color = kJarxPaper);
    }

    // 5. Glow: a blurred copy of the mark (1.3× wider) and a 70 px halo on
    // the head, ADDED on top as render.py does. Baseline 0.6 plus a bloom
    // peaking at 1.52 s; amounts above 1 take a second pass.
    final bloom = math.exp(-math.pow((t - 1.52) / 0.15, 2));
    var amount = 0.6 + 0.9 * bloom;
    while (amount > 0.001 && (sub != null || head != null)) {
      final a = math.min(1.0, amount);
      const blur = MaskFilter.blur(BlurStyle.normal, _glowSigma);
      if (sub != null) {
        canvas.drawPath(
            sub,
            _strokePaint(kJarxPulse.withValues(alpha: a), grow * 1.3)
              ..blendMode = BlendMode.plus
              ..maskFilter = blur);
      }
      if (head != null) {
        canvas.drawCircle(
            head,
            70,
            Paint()
              ..color = kJarxPaper.withValues(alpha: a)
              ..blendMode = BlendMode.plus
              ..maskFilter = blur);
      }
      amount -= a;
    }

    // 6–7. Wordmark and tagline.
    if (t > 1.35) _paintText(canvas, t - 1.35);
  }

  Paint _strokePaint(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _paintText(Canvas canvas, double t0) {
    // "track": letter-spacing 0.75em → 0.12em, opacity 0 → 1, easeOutQuint 0.7 s.
    final x = _out5(_seg(t0, 0, 0.7));
    _tracked(canvas, text.word, 150, _lerp(0.75, 0.12, x), 1215, x);
    // Tagline: 0.45–0.95 s after the wordmark starts, rises 10 px, to 0.62.
    final tx = _out3(_seg(t0, 0.45, 0.95));
    if (tx > 0) {
      _tracked(canvas, text.tag, text.tagSize, 0.2, 1215 + 78 + _lerp(10, 0, tx),
          0.62 * tx);
    }
  }

  /// render.py text_tracked: glyphs placed by their advance plus tracking,
  /// centred without trailing tracking, on [baseline].
  void _tracked(Canvas canvas, List<TextPainter> glyphs, double size,
      double trackEm, double baseline, double alpha) {
    if (alpha <= 0) return;
    final tr = trackEm * size;
    final total =
        glyphs.fold<double>(0, (a, g) => a + g.width) + tr * (glyphs.length - 1);
    var x = _w / 2 - total / 2;
    final layer = alpha < 1;
    if (layer) {
      canvas.saveLayer(null, Paint()..color = kJarxInk.withValues(alpha: alpha));
    }
    for (final g in glyphs) {
      final ascent =
          g.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      g.paint(canvas, Offset(x, baseline - ascent));
      x += g.width + tr;
    }
    if (layer) canvas.restore();
  }

  @override
  bool shouldRepaint(JarxIntroPainter old) =>
      old._fixedT != _fixedT || old.text != text;
}
