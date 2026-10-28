// About page: photos on a slowly turning 3D cylinder ("Round Carousel",
// a look from originkit.dev rebuilt in Flutter for touch).

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// One photo on the About page.
class AboutPhoto {
  const AboutPhoto({required this.asset, required this.caption});
  final String asset;
  final String caption;
}

/// Photos on a cylinder that turns right to left. Dragging spins it with
/// momentum; let go and it eases back to its usual speed.
class RoundCarousel extends StatefulWidget {
  const RoundCarousel({super.key, required this.photos});
  final List<AboutPhoto> photos;

  /// Idle turning speed in radians per second; negative turns right to left.
  static const cruise = -0.25;

  @override
  State<RoundCarousel> createState() => _RoundCarouselState();
}

/// A spin that starts at [v0] rad/s and settles to [cruise] rad/s, forever.
class SettleSpin extends Simulation {
  SettleSpin(this.x0, this.v0, this.cruise);
  final double x0, v0, cruise;

  /// How quickly a flick settles, per second.
  static const k = 1.6;

  @override
  double x(double t) => x0 + cruise * t + (v0 - cruise) / k * (1 - exp(-k * t));

  @override
  double dx(double t) => cruise + (v0 - cruise) * exp(-k * t);

  @override
  bool isDone(double t) => false;
}

class _RoundCarouselState extends State<RoundCarousel>
    with SingleTickerProviderStateMixin {
  static const _cardW = 130.0;
  static const _cardH = 170.0;
  static const _radius = 150.0;

  late final AnimationController _ticker =
      AnimationController.unbounded(vsync: this)
        ..addListener(() => setState(() => _angle = _ticker.value));
  double _angle = 0;

  @override
  void initState() {
    super.initState();
    _spin(RoundCarousel.cruise);
  }

  void _spin(double velocity) {
    _ticker.value = _angle;
    _ticker.animateWith(SettleSpin(_angle, velocity, RoundCarousel.cruise));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final n = photos.length;
    final step = 2 * pi / n;
    // Paint back to front.
    final order = List.generate(n, (i) => i)
      ..sort(
          (a, b) => cos(_angle + a * step).compareTo(cos(_angle + b * step)));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onHorizontalDragStart: (_) => _ticker.stop(),
          onHorizontalDragUpdate: (d) =>
              setState(() => _angle += d.delta.dx / _radius),
          onHorizontalDragEnd: (d) =>
              _spin(d.velocity.pixelsPerSecond.dx / _radius),
          onHorizontalDragCancel: () => _spin(RoundCarousel.cruise),
          child: SizedBox(
            height: _cardH + 60,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final i in order)
                  Builder(builder: (context) {
                    final theta = _angle + i * step;
                    final depth = (cos(theta) + 1) / 2; // 0 back .. 1 front
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..translateByDouble(
                            sin(theta) * _radius, 0, -cos(theta) * _radius, 1)
                        ..rotateY(theta),
                      child: Opacity(
                        opacity: 0.35 + depth * 0.65,
                        child: SizedBox(
                          width: _cardW,
                          height: _cardH,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(photos[i].asset,
                                fit: BoxFit.cover, cacheWidth: 400),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: Text(
            photos[order.last].caption,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 15,
              fontStyle: FontStyle.italic,
              fontFamily: 'Gilroy',
            ),
          ),
        ),
      ],
    );
  }
}
