import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:icons_plus/icons_plus.dart';

class LikeBtnWidget extends StatefulWidget {
  final bool isLiked;
  final bool isPlaying;
  final double iconSize;
  final VoidCallback? onLiked;
  final VoidCallback? onDisliked;
  const LikeBtnWidget({
    Key? key,
    this.isLiked = false,
    this.isPlaying = false,
    this.iconSize = 50,
    this.onLiked,
    this.onDisliked,
  }) : super(key: key);

  @override
  State<LikeBtnWidget> createState() => _LikeBtnWidgetState();
}

class _LikeBtnWidgetState extends State<LikeBtnWidget>
    with TickerProviderStateMixin {
  late AnimationController _colorController;
  late Animation<Color?> _colorAnimation;

  /// Plays once when the heart is tapped on: pop + a ring of dots.
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  static final _pop = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35),
    TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 65),
  ]);

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _setupAnimation();
    if (widget.isPlaying) {
      _colorController.value = 1.0;
    }
  }

  void _setupAnimation() {
    _colorAnimation = ColorTween(
      begin: Default_Theme.accentColor2, // Pink (paused)
      end: Default_Theme.accentColor1, // Sky Blue (playing)
    ).animate(CurvedAnimation(
      parent: _colorController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void didUpdateWidget(covariant LikeBtnWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _colorController.forward();
      } else {
        _colorController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _colorController.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_colorController, _burst]),
      builder: (context, child) {
        final color = _colorAnimation.value ?? Default_Theme.accentColor2;
        return CustomPaint(
          painter: _BurstPainter(_burst.value, color),
          child: IconButton(
            onPressed: () {
              if (widget.isLiked) {
                widget.onDisliked?.call();
              } else {
                HapticFeedback.lightImpact();
                _burst.forward(from: 0);
                widget.onLiked?.call();
              }
            },
            icon: Transform.scale(
              scale: _burst.isAnimating ? _pop.transform(_burst.value) : 1,
              child: Icon(
                widget.isLiked ? AntDesign.heart_fill : AntDesign.heart_outline,
                color: color,
                size: widget.iconSize,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Eight dots flying out from the heart and fading.
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0 || t == 1) return;
    final center = size.center(Offset.zero);
    final spread = Curves.easeOutCubic.transform(t);
    final radius = size.shortestSide * (0.3 + 0.5 * spread);
    final paint = Paint()..color = color.withValues(alpha: 1 - t);
    for (var i = 0; i < 8; i++) {
      final a = i * pi / 4 + pi / 8;
      canvas.drawCircle(
          center + Offset(cos(a), sin(a)) * radius, 3 * (1 - t) + 0.5, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}
