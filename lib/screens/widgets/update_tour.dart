// Guided tour for a compulsory update (UpdateGate): a spotlight on the Home
// bell, then the update in the bell list and the Download/Install button
// glow (UpdateGlow) until the new JARX is installed.

import 'dart:math' as math;

import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/screens/screen/home_views/notification_view.dart';
import 'package:Bloomee/services/app_updater.dart';
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';

/// On the Home bell, so the tour can find it.
final updateBellKey = GlobalKey();

const _accent = Default_Theme.accentColor2;

class UpdateTour extends StatefulWidget {
  const UpdateTour({super.key, required this.navigatorKey});
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<UpdateTour> createState() => _UpdateTourState();
}

class _UpdateTourState extends State<UpdateTour> with TickerProviderStateMixin {
  late final _enter = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();
  late final _loop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();
  Rect? _bell;
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    // Measured after the first frame, while this layer still lets taps
    // through, so the hit test sees what is really under the bell.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _bell = _visibleBell();
          _measured = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// The bell's place on screen if the user can see and tap it right now
  /// (not under another screen or on another tab), else null.
  Rect? _visibleBell() {
    final ctx = updateBellKey.currentContext;
    final box = ctx?.findRenderObject();
    if (ctx == null || box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final hit = HitTestResult();
    WidgetsBinding.instance
        .hitTestInView(hit, rect.center, View.of(ctx).viewId);
    return hit.path.any((e) => e.target == box) ? rect : null;
  }

  double _holeRadius(Rect bell) => bell.longestSide / 2 + 12;

  Future<void> _close() async {
    await _enter.animateBack(0, duration: const Duration(milliseconds: 350));
    UpdateGate.showingTour.value = false;
  }

  void _openBell() {
    UpdateGate.showingTour.value = false;
    widget.navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const NotificationView()));
  }

  /// A short ring, then a rest, every loop.
  double _ring(double t) =>
      t < 0.4 ? math.sin(t / 0.4 * 6 * math.pi) * 0.35 * (1 - t / 0.4) : 0;

  double _interval(double begin, double end, Curve curve) =>
      Interval(begin, end, curve: curve).transform(_enter.value);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_measured,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: Listenable.merge([_enter, _loop]),
          builder: (context, _) {
            final fade = _interval(0, 0.4, Curves.easeOut);
            final t = _loop.value;
            final bell = _bell;
            return Stack(children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    if (bell != null &&
                        (d.globalPosition - bell.center).distance <
                            _holeRadius(bell) + 8) {
                      _openBell();
                    }
                  },
                  child: CustomPaint(
                    painter: _Spotlight(
                        hole: bell,
                        radius: bell == null ? 0 : _holeRadius(bell),
                        pulse: t,
                        opacity: fade),
                  ),
                ),
              ),
              if (bell != null)
                Positioned(
                  left: bell.center.dx - 16,
                  top: bell.bottom +
                      18 +
                      10 * math.sin(t * 2 * math.pi).abs(),
                  child: Opacity(
                    opacity: fade,
                    child: const Icon(Icons.arrow_upward_rounded,
                        color: _accent, size: 32),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 24 + MediaQuery.of(context).padding.bottom,
                child: Opacity(
                  opacity: fade,
                  child: Transform.translate(
                    offset: Offset(
                        0, (1 - _interval(0, 0.6, Curves.easeOutBack)) * 320),
                    child: _card(bell != null, t),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _card(bool bellVisible, double t) {
    final steps = [
      bellVisible ? 'Tap the glowing bell at the top' : 'Open the bell on Home',
      'Tap the update',
      'Tap Download update, then Install update',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
      decoration: BoxDecoration(
        color: Default_Theme.themeColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: _accent.withValues(alpha: 0.25), blurRadius: 30)
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Transform.rotate(
              angle: _ring(t),
              alignment: Alignment.topCenter,
              child: const Icon(MingCute.notification_fill,
                  color: _accent, size: 30),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Update required',
                  style: TextStyle(
                      color: Default_Theme.primaryColor1,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ),
            IconButton(
              onPressed: _close,
              icon: const Icon(Icons.close_rounded,
                  color: Default_Theme.primaryColor2),
            ),
          ]),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Text(
              "This version of JARX can't play songs any more. The new one "
              'takes a minute to install and keeps your music and sign-in.',
              style: TextStyle(
                  color: Default_Theme.primaryColor2, fontSize: 14, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            Builder(builder: (_) {
              final p = _interval(0.4 + 0.15 * i, 0.7 + 0.1 * i, Curves.easeOut);
              return Opacity(
                opacity: p,
                child: Transform.translate(
                  offset: Offset(24 * (1 - p), 0),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10, right: 12),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: _accent,
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                color: Default_Theme.primaryColor1,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(steps[i],
                            style: const TextStyle(
                                color: Default_Theme.primaryColor1,
                                fontSize: 15)),
                      ),
                    ]),
                  ),
                ),
              );
            }),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  minimumSize: const Size.fromHeight(48)),
              onPressed: _openBell,
              icon: const Icon(MingCute.notification_line),
              label: Text(bellVisible ? 'Open the bell' : 'Show me'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dims the screen except a round hole over the bell, with two rings
/// rippling out of it.
class _Spotlight extends CustomPainter {
  _Spotlight(
      {required this.hole,
      required this.radius,
      required this.pulse,
      required this.opacity});
  final Rect? hole;
  final double radius, pulse, opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.78 * opacity);
    final screen = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(screen, dim);
      return;
    }
    final c = h.center;
    canvas.drawPath(
        Path.combine(PathOperation.difference, screen,
            Path()..addOval(Rect.fromCircle(center: c, radius: radius))),
        dim);
    for (final k in const [0.0, 0.5]) {
      final p = (pulse + k) % 1;
      canvas.drawCircle(
          c,
          radius + 24 * p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = _accent.withValues(alpha: (1 - p) * opacity));
    }
  }

  @override
  bool shouldRepaint(_Spotlight old) => true;
}

/// While a compulsory update is waiting: a hint above [child] and a soft,
/// breathing glow around it. Otherwise just [child].
class UpdateGlow extends StatefulWidget {
  const UpdateGlow(
      {super.key, required this.hint, required this.child, this.radius = 16});
  final String hint;
  final Widget child;
  final double radius;

  @override
  State<UpdateGlow> createState() => _UpdateGlowState();
}

class _UpdateGlowState extends State<UpdateGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300));
    if (UpdateGate.blocked) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!UpdateGate.blocked) return widget.child;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Keyed by the text: a new hint slides in again.
        TweenAnimationBuilder<double>(
          key: ValueKey(widget.hint),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          builder: (_, p, child) => Opacity(
            opacity: p.clamp(0, 1),
            child: Transform.translate(
                offset: Offset(0, 12 * (1 - p)), child: child),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Transform.translate(
              offset: Offset(0, 4 * _c.value),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.arrow_downward_rounded,
                        color: _accent, size: 20),
                    const SizedBox(width: 6),
                    Text(widget.hint,
                        style: const TextStyle(
                            color: _accent,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final v = Curves.easeInOut.transform(_c.value);
            return Transform.scale(
              scale: 1 + 0.025 * v,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius),
                  boxShadow: [
                    BoxShadow(
                        color: _accent.withValues(alpha: 0.2 + 0.35 * v),
                        blurRadius: 10 + 16 * v,
                        spreadRadius: 1 + 2 * v),
                  ],
                ),
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
      ],
    );
  }
}
