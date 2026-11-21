import 'package:Bloomee/screens/widgets/tip_overlay.dart';
import 'package:Bloomee/services/tips.dart';
import 'package:Bloomee/blocs/player_overlay/player_overlay_cubit.dart';
import 'package:Bloomee/screens/screen/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The player's open/close progress (0 = closed, 1 = open), for widgets
/// inside the player that animate with it (the cover grows as it opens).
class PlayerOpenAnimation extends InheritedWidget {
  const PlayerOpenAnimation(
      {super.key, required this.animation, required super.child});
  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlayerOpenAnimation>()?.animation;

  @override
  bool updateShouldNotify(PlayerOpenAnimation oldWidget) =>
      animation != oldWidget.animation;
}

/// A persistent player overlay that stays mounted in the widget tree.
/// This widget wraps the main content and overlays the full player on top
/// with a slide-up animation when visible, similar to modern media apps.
/// Dragging the player down closes it.
class PlayerOverlayWrapper extends StatefulWidget {
  final Widget child;

  const PlayerOverlayWrapper({
    super.key,
    required this.child,
  });

  @override
  State<PlayerOverlayWrapper> createState() => _PlayerOverlayWrapperState();
}

class _PlayerOverlayWrapperState extends State<PlayerOverlayWrapper>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  /// How far the player is dragged down, as a share of the screen height.
  late final AnimationController _drag = AnimationController(vsync: this);
  bool _closingByDrag = false;

  /// Drag past this share of the screen (or fling) to close.
  static const double _closeFraction = 0.22;

  /// Track if the player has ever been shown so we can keep it mounted
  bool _hasBeenShown = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    _drag.dispose();
    super.dispose();
  }

  void _onPlayerVisibilityChanged(bool isVisible) {
    if (isVisible) {
      _hasBeenShown = true;
      _closingByDrag = false;
      _drag.value = 0;
      // Dismiss keyboard by unfocusing any active text field
      FocusManager.instance.primaryFocus?.unfocus();
      _animationController.forward();
    } else if (_closingByDrag) {
      // Already slid off screen by the drag: no second slide.
      _closingByDrag = false;
      _animationController.value = 0;
      _drag.value = 0;
    } else {
      _animationController.reverse();
    }
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_animationController.value < 1) return; // still opening/closing
    _drag.value += d.delta.dy / MediaQuery.sizeOf(context).height;
  }

  /// A drag the system took over (back gesture, notification shade, app
  /// switch) used to leave the player a little lower, which pushed the Up
  /// next bar off the bottom of the screen. Put it back.
  void _onDragCancel() {
    if (_drag.value == 0) return;
    _drag.animateBack(0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic);
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    final v = d.primaryVelocity ?? 0;
    if (_drag.value == 0) {
      // A quick swipe up opens the queue.
      if (v < -400) context.read<PlayerOverlayCubit>().openUpNextPanel();
      return;
    }
    if (_drag.value < _closeFraction && v < 900) {
      _drag.animateBack(0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
      return;
    }
    HapticFeedback.lightImpact();
    await _drag.animateTo(1,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    if (!mounted) return;
    _closingByDrag = true;
    context.read<PlayerOverlayCubit>().hidePlayer();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PlayerOverlayCubit, bool>(
      listener: (context, isVisible) {
        _onPlayerVisibilityChanged(isVisible);
        if (isVisible) {
          TipStore.bump('player').then((_) {
            Tips.offer('A4');
            Tips.offer('T2');
          });
        }
      },
      child: Stack(
        children: [
          // Main content (always visible)
          widget.child,

          // Player overlay - once shown, stays mounted for instant reopening
          BlocBuilder<PlayerOverlayCubit, bool>(
            buildWhen: (previous, current) {
              // Only rebuild if we need to first mount the player
              // Once mounted, it stays mounted
              return !_hasBeenShown && current;
            },
            builder: (context, isVisible) {
              if (!_hasBeenShown && !isVisible) {
                return const SizedBox.shrink();
              }

              // Mark that player has been shown
              if (isVisible && !_hasBeenShown) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _hasBeenShown = true;
                    });
                  }
                });
              }

              return AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Visibility(
                    visible: _animationController.value > 0,
                    maintainState: true, // Keep state when hidden
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: child,
                      ),
                    ),
                  );
                },
                child: GestureDetector(
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  onVerticalDragCancel: _onDragCancel,
                  child: AnimatedBuilder(
                    animation: _drag,
                    // Follows the finger, shrinks a little and rounds its
                    // corners like a card being pulled away.
                    builder: (context, child) {
                      final t = _drag.value;
                      return Transform.translate(
                        offset:
                            Offset(0, t * MediaQuery.sizeOf(context).height),
                        child: Transform.scale(
                          scale: 1 - 0.08 * t,
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular((t * 160).clamp(0, 28)),
                            clipBehavior: t == 0 ? Clip.none : Clip.antiAlias,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: PlayerOpenAnimation(
                      animation: _animationController,
                      child: const _PersistentPlayerView(),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The persistent player view that stays mounted.
class _PersistentPlayerView extends StatelessWidget {
  const _PersistentPlayerView();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Colors.transparent,
      child: AudioPlayerView(),
    );
  }
}
