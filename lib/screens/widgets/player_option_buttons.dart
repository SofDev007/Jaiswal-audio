import 'dart:math' as math;

import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/blocs/timer/timer_bloc.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/screens/screen/home_views/timer_view.dart';
import 'package:Bloomee/services/player/player_engine.dart' show LoopMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:icons_plus/icons_plus.dart';

/// A short message for the pill above the cover (shuffle, sleep timer).
class PlayerFlashMessage {
  const PlayerFlashMessage(this.icon, this.text);
  final IconData icon;
  final String text;
}

/// What the pill above the cover shows next; set it to flash a message.
final ValueNotifier<PlayerFlashMessage?> playerFlash = ValueNotifier(null);

/// "1 h 30 min", "15 min", "45 s".
String sleepTimeText(int seconds) {
  if (seconds < 60) return '$seconds s';
  final h = seconds ~/ 3600, m = (seconds % 3600 + 59) ~/ 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The pill that pops up just above the cover: grows in with a little
/// overshoot, stays a moment, then floats up and fades.
class PlayerFlash extends StatefulWidget {
  const PlayerFlash({super.key});

  @override
  State<PlayerFlash> createState() => _PlayerFlashState();
}

class _PlayerFlashState extends State<PlayerFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1700));
  PlayerFlashMessage? _shown;

  @override
  void initState() {
    super.initState();
    playerFlash.addListener(_onFlash);
  }

  void _onFlash() {
    final m = playerFlash.value;
    if (m == null || !mounted) return;
    setState(() => _shown = m);
    _c.forward(from: 0);
    playerFlash.value = null; // the same message can flash again
  }

  @override
  void dispose() {
    playerFlash.removeListener(_onFlash);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _shown;
    if (m == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          // 0-0.15 in, 0.15-0.75 hold, 0.75-1 out.
          final inT = Curves.easeOutBack.transform((t / 0.15).clamp(0.0, 1.0));
          final outT =
              Curves.easeIn.transform(((t - 0.75) / 0.25).clamp(0.0, 1.0));
          return Opacity(
            opacity: (inT.clamp(0.0, 1.0) * (1 - outT)),
            child: Transform.translate(
              offset: Offset(0, -10 * outT),
              child: Transform.scale(scale: 0.6 + 0.4 * inT, child: child),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
                color: Default_Theme.primaryColor1.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(m.icon, color: Default_Theme.accentColor1, size: 22),
              const SizedBox(width: 8),
              Text(
                m.text,
                style: Default_Theme.secondoryTextStyleMedium.merge(
                    const TextStyle(
                        color: Default_Theme.primaryColor1,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shuffle: spins a full turn with a bounce when toggled and flashes
/// "Shuffle on/off" above the cover.
class ShuffleButton extends StatefulWidget {
  const ShuffleButton({super.key});

  @override
  State<ShuffleButton> createState() => _ShuffleButtonState();
}

class _ShuffleButtonState extends State<ShuffleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 550));
  double _direction = 1;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<bool>(
      stream: player.shuffleMode,
      builder: (context, snapshot) {
        final on = snapshot.data ?? false;
        return IconButton(
          icon: AnimatedBuilder(
            animation: _spin,
            builder: (context, child) {
              final t = Curves.easeOutBack.transform(_spin.value);
              final bounce = 1 + 0.25 * math.sin(math.pi * _spin.value);
              return Transform.rotate(
                angle: 2 * math.pi * t * _direction,
                child: Transform.scale(scale: bounce, child: child),
              );
            },
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                  end: on
                      ? Default_Theme.accentColor1
                      : Default_Theme.primaryColor1),
              duration: const Duration(milliseconds: 300),
              builder: (context, color, _) =>
                  Icon(MingCute.shuffle_2_fill, color: color, size: 28),
            ),
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            _direction = on ? -1 : 1;
            _spin.forward(from: 0);
            playerFlash.value = PlayerFlashMessage(MingCute.shuffle_2_fill,
                on ? l10n.playerShuffleOff : l10n.playerShuffleOn);
            player.shuffle(!on);
          },
        );
      },
    );
  }
}

/// Sleep timer: opens the timer page. While a timer runs the icon turns the
/// accent colour, a ring around it empties as time runs out (pulsing in the
/// last minute) and the minutes left show under it. Setting a timer makes
/// the icon ring like an alarm clock and flashes the time above the cover.
class SleepTimerButton extends StatefulWidget {
  const SleepTimerButton({super.key});

  @override
  State<SleepTimerButton> createState() => _SleepTimerButtonState();
}

class _SleepTimerButtonState extends State<SleepTimerButton>
    with TickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  int _total = 0;
  late TimerState _prev;

  @override
  void initState() {
    super.initState();
    _prev = context.read<TimerBloc>().state;
    if (_running(_prev)) _total = _prev.duration;
  }

  @override
  void dispose() {
    _ring.dispose();
    _pulse.dispose();
    super.dispose();
  }

  bool _running(TimerState s) => s is TimerRunInProgress || s is TimerRunPause;

  void _onChange(TimerState prev, TimerState now) {
    final l10n = AppLocalizations.of(context)!;
    if (_running(now) && (!_running(prev) || now.duration > prev.duration)) {
      // A timer was set (or changed to a longer one).
      _total = now.duration;
      _ring.forward(from: 0);
      HapticFeedback.lightImpact();
      playerFlash.value = PlayerFlashMessage(MingCute.alarm_1_fill,
          l10n.playerSleepTimerSet(sleepTimeText(now.duration)));
    } else if (_running(prev) && !_running(now)) {
      _pulse.stop();
      _ring.forward(from: 0);
      if (now is! TimerRunComplete) {
        playerFlash.value =
            PlayerFlashMessage(MingCute.alarm_1_line, l10n.playerSleepTimerOff);
      }
    }
    final lastMinute = now is TimerRunInProgress && now.duration <= 60;
    if (lastMinute && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!lastMinute && _pulse.isAnimating) _pulse.stop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TimerBloc, TimerState>(
      listener: (context, s) {
        _onChange(_prev, s);
        _prev = s;
      },
      builder: (context, s) {
        final running = _running(s);
        final left = running && _total > 0 ? s.duration / _total : 0.0;
        return IconButton(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const TimerView())),
          icon: AnimatedBuilder(
            animation: Listenable.merge([_ring, _pulse]),
            builder: (context, _) {
              // Alarm-clock shake: a few fast, shrinking wiggles.
              final r = _ring.value;
              final shake = math.sin(r * math.pi * 8) * 0.35 * (1 - r);
              return SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (running)
                      Opacity(
                        opacity: 1 - 0.6 * _pulse.value,
                        child: CustomPaint(
                          size: const Size(44, 44),
                          painter: _RingPainter(left.clamp(0.0, 1.0)),
                        ),
                      ),
                    Transform.rotate(
                      angle: shake,
                      child: Icon(
                        running ? MingCute.alarm_1_fill : MingCute.alarm_1_line,
                        color: running
                            ? Default_Theme.accentColor1
                            : Default_Theme.primaryColor1,
                        size: running ? 24 : 28,
                      ),
                    ),
                    if (running)
                      Positioned(
                        bottom: -14,
                        child: Text(
                          sleepTimeText(s.duration)
                              .replaceAll(' min', 'm')
                              .replaceAll(' h', 'h')
                              .replaceAll(' s', 's'),
                          style: const TextStyle(
                              color: Default_Theme.accentColor1,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// The part of the ring still to go, drawn clockwise from the top.
class _RingPainter extends CustomPainter {
  const _RingPainter(this.left);
  final double left;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Default_Theme.primaryColor1.withValues(alpha: 0.12);
    canvas.drawArc(rect.deflate(2), 0, 2 * math.pi, false, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = Default_Theme.accentColor1;
    canvas.drawArc(
        rect.deflate(2), -math.pi / 2, 2 * math.pi * left, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.left != left;
}

/// Repeat: each tap moves Off -> Repeat all -> Repeat one -> Off, with a
/// half-turn of the icon and the mode flashed above the cover.
class LoopButton extends StatefulWidget {
  const LoopButton({super.key});

  @override
  State<LoopButton> createState() => _LoopButtonState();
}

class _LoopButtonState extends State<LoopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<LoopMode>(
      stream: player.loopMode,
      builder: (context, snapshot) {
        final mode = snapshot.data ?? LoopMode.off;
        final next = switch (mode) {
          LoopMode.off => LoopMode.all,
          LoopMode.all => LoopMode.one,
          LoopMode.one => LoopMode.off,
        };
        return IconButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            _turn.forward(from: 0);
            player.setLoopMode(next);
            playerFlash.value = PlayerFlashMessage(
              next == LoopMode.one
                  ? MingCute.repeat_one_line
                  : MingCute.repeat_fill,
              switch (next) {
                LoopMode.off => l10n.playerRepeatOff,
                LoopMode.all => l10n.playerRepeatAll,
                LoopMode.one => l10n.playerRepeatOne,
              },
            );
          },
          icon: AnimatedBuilder(
            animation: _turn,
            // A full turn, so it always lands upright (a half turn left the
            // "1" of Repeat one upside down).
            builder: (context, child) => Transform.rotate(
              angle: 2 * math.pi * Curves.easeOutBack.transform(_turn.value),
              child: Transform.scale(
                  scale: 1 + 0.2 * math.sin(math.pi * _turn.value),
                  child: child),
            ),
            child: Icon(
              mode == LoopMode.off
                  ? MingCute.repeat_line
                  : mode == LoopMode.one
                      ? MingCute.repeat_one_line
                      : MingCute.repeat_fill,
              color: mode == LoopMode.off
                  ? Default_Theme.primaryColor1
                  : Default_Theme.accentColor1,
              size: 24,
            ),
          ),
        );
      },
    );
  }
}
