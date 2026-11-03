import 'package:flutter/material.dart';

/// Grey placeholder shapes with a light band sweeping across, shown while
/// content loads instead of a spinner.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.06),
          ],
          stops: const [0.35, 0.5, 0.65],
          transform: _Sweep(_c.value),
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _Sweep extends GradientTransform {
  const _Sweep(this.t);
  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (2 * t - 1), 0, 0);
}

Widget _box(double w, double h, {double r = 6}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r),
      ),
    );

/// Placeholder song rows, shaped like [SongCardWidget].
class SkeletonSongList extends StatelessWidget {
  const SkeletonSongList({super.key, this.count = 7});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _box(50, 50, r: 10),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Varying widths so it doesn't look like a grid.
                        FractionallySizedBox(
                          widthFactor: 0.75 - (i % 3) * 0.15,
                          child: _box(double.infinity, 13),
                        ),
                        const SizedBox(height: 8),
                        FractionallySizedBox(
                          widthFactor: 0.45 - (i % 2) * 0.1,
                          child: _box(double.infinity, 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Placeholder Home sections: a title bar over a row of square cards.
class SkeletonCardRows extends StatelessWidget {
  const SkeletonCardRows({super.key, this.rows = 2});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var r = 0; r < rows; r++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: _box(140, 16),
            ),
            SizedBox(
              height: 170,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _box(130, 130, r: 14),
                          const SizedBox(height: 10),
                          _box(90, 11),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
