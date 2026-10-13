import 'dart:math' as math;

import 'package:flutter/material.dart';

/// JARX loading indicator: equalizer bars bouncing up and down (the motion
/// from intro option D).
///
/// A drop-in for an indeterminate [CircularProgressIndicator]: it fills the
/// box it is given (at least 36×36 when unconstrained, like the Material
/// indicator) and takes the same colour parameters. Below 24 px it draws three
/// bars instead of five so they stay readable. With "remove animations" on, the
/// bars hold still.
class JarxLoadingIndicator extends StatefulWidget {
  const JarxLoadingIndicator({
    super.key,
    this.color,
    this.valueColor,
    this.backgroundColor,
    this.strokeWidth,
    this.semanticsLabel,
  });

  /// Bar colour. Falls back to [valueColor], then the theme's progress colour.
  final Color? color;
  final Animation<Color?>? valueColor;

  /// Accepted so existing [CircularProgressIndicator] call sites keep
  /// compiling; the bars have no track, so this is unused.
  final Color? backgroundColor;

  /// Accepted for the same reason; bar thickness follows the size instead.
  final double? strokeWidth;
  final String? semanticsLabel;

  @override
  State<JarxLoadingIndicator> createState() => _JarxLoadingIndicatorState();
}

/// One loop covers two bounces of every bar, so it repeats seamlessly.
const Duration _kLoop = Duration(milliseconds: 1250);

class _JarxLoadingIndicatorState extends State<JarxLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _kLoop);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        widget.valueColor?.value ??
        ProgressIndicatorTheme.of(context).color ??
        Theme.of(context).colorScheme.primary;
    final bars = Container(
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      child: CustomPaint(painter: _BarsPainter(_controller, color)),
    );
    final label = widget.semanticsLabel;
    return label == null ? bars : Semantics(label: label, child: bars);
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.progress, this.color) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;
    final count = side < 24 ? 3 : 5;
    final barW = side * (count == 3 ? 0.2 : 0.12);
    final gap = side * (count == 3 ? 0.12 : 0.07);
    final total = count * barW + (count - 1) * gap;
    final maxH = side * 0.9;
    var x = (size.width - total) / 2;
    final cy = size.height / 2;
    // Same motion as the intro: each bar 30–100% tall, |sin| at 1.6 Hz,
    // phases offset so the bars ripple.
    final t = progress.value * _kLoop.inMilliseconds / 1000;
    final paint = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final h = maxH * (0.3 + 0.7 * (math.sin(2 * math.pi * 1.6 * t + i * 1.1)).abs());
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, cy - h / 2, barW, h),
          Radius.circular(barW / 2),
        ),
        paint,
      );
      x += barW + gap;
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color;
}
