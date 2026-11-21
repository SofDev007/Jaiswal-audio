// The tip bubble: dims the screen except the button, rings it, and pops a
// bubble with an arrow next to it. A tap anywhere closes it. Screens wrap
// the button in [TipAnchor]; tips without a button (e.g. "queued songs
// play next") use [Tips.offer] and show above the mini player.
// The rules (once, one at a time, 3 a day) are in services/tips.dart.

import 'dart:async';

import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/routes/app_router.dart';
import 'package:Bloomee/services/tips.dart';
import 'package:flutter/material.dart';

class Tips {
  /// Tip id -> the buttons it can point at (e.g. every Home card's ⊖).
  static final _anchors = <String, List<BuildContext>>{};
  static final _offered = <String>{};
  static Timer? _wait;
  static OverlayEntry? _showing;

  /// [id] could show now: after a short pause the most important tip
  /// offered meanwhile shows (if the rules allow one).
  static void offer(String id) {
    _offered.add(id);
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 900), _decide);
  }

  /// The first of [id]'s buttons that is fully on screen, on the page in
  /// front, and its context.
  static (Rect, BuildContext)? _find(String id) {
    for (final ctx in _anchors[id] ?? const <BuildContext>[]) {
      if (!ctx.mounted) continue;
      if (!(ModalRoute.of(ctx)?.isCurrent ?? true)) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final screen = MediaQuery.sizeOf(ctx);
      if (rect.top < 0 ||
          rect.left < 0 ||
          rect.bottom > screen.height ||
          rect.right > screen.width ||
          rect.isEmpty) {
        continue; // scrolled out of sight, or half off the screen
      }
      return (rect, ctx);
    }
    return null;
  }

  static Future<void> _decide() async {
    final offered = Set.of(_offered);
    _offered.clear();
    if (_showing != null) return;
    final book = await TipStore.load();
    final now = DateTime.now();
    final ok = [
      for (final id in offered)
        if (_anchors.containsKey(id) ? _find(id) != null : true) id
    ];
    final id = book.pick(ok, now);
    if (id == null) return;
    final found = _anchors.containsKey(id) ? _find(id) : null;
    final rect = found?.$1;
    final ctx = found?.$2 ?? GlobalRoutes.globalRouterKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final overlay = Overlay.maybeOf(ctx, rootOverlay: true);
    if (overlay == null) return;
    book.markShown(id, now);
    unawaited(TipStore.save());
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TipBubble(
        text: tipTexts[id]!,
        target: rect,
        onClosed: () {
          entry.remove();
          if (_showing == entry) _showing = null;
        },
      ),
    );
    _showing = entry;
    overlay.insert(entry);
  }
}

/// Marks [child] as the button tip [id] points at, and offers the tip once
/// it is on screen.
class TipAnchor extends StatefulWidget {
  const TipAnchor({super.key, required this.id, required this.child});
  final String id;
  final Widget child;

  @override
  State<TipAnchor> createState() => _TipAnchorState();
}

class _TipAnchorState extends State<TipAnchor> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (Tips._anchors[widget.id] ??= []).add(context);
      Tips.offer(widget.id);
    });
  }

  @override
  void dispose() {
    final list = Tips._anchors[widget.id];
    list?.remove(context);
    if (list != null && list.isEmpty) Tips._anchors.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TipBubble extends StatefulWidget {
  const _TipBubble(
      {required this.text, required this.target, required this.onClosed});
  final String text;

  /// The button, in screen coordinates; null: no button (bubble at the
  /// bottom, above the mini player).
  final Rect? target;
  final VoidCallback onClosed;

  @override
  State<_TipBubble> createState() => _TipBubbleState();
}

class _TipBubbleState extends State<_TipBubble> with TickerProviderStateMixin {
  late final _in = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500))
    ..forward();
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();
  Timer? _auto;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // Never stuck on screen: closes by itself after a while.
    _auto = Timer(const Duration(seconds: 12), _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _auto?.cancel();
    await _in.reverse();
    widget.onClosed();
  }

  @override
  void dispose() {
    _auto?.cancel();
    _in.dispose();
    _pulse.dispose();
    super.dispose();
  }

  static const _w = 250.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final t = widget.target?.inflate(5);
    final below = t == null ? false : t.center.dy < size.height * 0.55;
    final left = t == null
        ? (size.width - _w) / 2
        : (t.center.dx - _w / 2).clamp(12.0, size.width - _w - 12);
    final arrowX = t == null ? null : (t.center.dx - left).clamp(18.0, _w - 18);
    final pop = CurvedAnimation(
        parent: _in, curve: Curves.elasticOut, reverseCurve: Curves.easeIn);
    final fade = CurvedAnimation(parent: _in, curve: const Interval(0, 0.4));

    final bubble = Material(
      color: Colors.transparent,
      child: Container(
        width: _w,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1022),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Default_Theme.accentColor1light.withValues(alpha: 0.8)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.text,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14.5, height: 1.4)),
            const SizedBox(height: 6),
            const Text('Got it',
                style: TextStyle(
                    color: Default_Theme.accentColor1light,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
          ],
        ),
      ),
    );

    return FadeTransition(
      opacity: fade,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: CustomPaint(painter: _DimPainter(t)),
          ),
        ),
        if (t != null)
          Positioned.fromRect(
            rect: t,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                        (t.shortestSide / 2).clamp(0, 16)),
                    border: Border.all(
                        color: Default_Theme.accentColor1light, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Default_Theme.accentColor1light
                            .withValues(alpha: 0.5 * (1 - _pulse.value)),
                        spreadRadius: 12 * _pulse.value,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: left,
          top: t != null && below ? t.bottom + 14 : null,
          bottom: t == null
              ? 150
              : below
                  ? null
                  : size.height - t.top + 14,
          child: GestureDetector(
            onTap: _close,
            child: ScaleTransition(
              scale: pop,
              alignment: Alignment(
                  arrowX == null ? 0 : (arrowX / _w) * 2 - 1, below ? -1 : 1),
              child: Stack(clipBehavior: Clip.none, children: [
                bubble,
                if (arrowX != null)
                  Positioned(
                    left: arrowX - 7,
                    top: below ? -7 : null,
                    bottom: below ? null : -7,
                    child: Transform.rotate(
                      angle: 0.785398,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1022),
                          border: Border(
                            left: below
                                ? const BorderSide(
                                    color: Default_Theme.accentColor1light)
                                : BorderSide.none,
                            top: below
                                ? const BorderSide(
                                    color: Default_Theme.accentColor1light)
                                : BorderSide.none,
                            right: below
                                ? BorderSide.none
                                : const BorderSide(
                                    color: Default_Theme.accentColor1light),
                            bottom: below
                                ? BorderSide.none
                                : const BorderSide(
                                    color: Default_Theme.accentColor1light),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Dims everything except a rounded hole around the button.
class _DimPainter extends CustomPainter {
  _DimPainter(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (hole != null) {
      path.addRRect(RRect.fromRectAndRadius(
          hole!, Radius.circular((hole!.shortestSide / 2).clamp(0, 16))));
    }
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}
