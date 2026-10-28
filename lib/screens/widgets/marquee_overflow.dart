import 'package:flutter/material.dart';

/// Shows [child] on one line; when it is wider than the space it gets, it
/// slides left to reveal the rest, pauses, and starts over (like `<marquee>`).
/// Text that fits stays still. Links inside [child] remain tappable.
/// Give it a key per song (e.g. `ValueKey(track.id)`) so it restarts on change.
class MarqueeOverflow extends StatefulWidget {
  final Widget child;

  /// Scroll speed in logical pixels per second.
  final double speed;

  const MarqueeOverflow({super.key, required this.child, this.speed = 30});

  @override
  State<MarqueeOverflow> createState() => _MarqueeOverflowState();
}

class _MarqueeOverflowState extends State<MarqueeOverflow> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loop());
  }

  Future<void> _loop() async {
    bool live() => mounted && _controller.hasClients;
    while (live()) {
      await Future.delayed(const Duration(seconds: 2));
      if (!live()) return;
      final extent = _controller.position.maxScrollExtent;
      if (extent <= 0) return; // Fits: nothing to scroll.
      await _controller.animateTo(extent,
          duration: Duration(milliseconds: (extent / widget.speed * 1000).round()),
          curve: Curves.linear);
      await Future.delayed(const Duration(seconds: 1));
      if (!live()) return;
      await _controller.animateTo(0,
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: widget.child,
    );
  }
}
