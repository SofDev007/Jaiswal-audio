// The playlist's shuffle button: a tap springs two bubbles out above it,
// "Shuffle" and "Smart shuffle". A tap anywhere else tucks them back in.

import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ShuffleBubbles extends StatefulWidget {
  const ShuffleBubbles({
    super.key,
    required this.button,
    required this.onShuffle,
    required this.onSmartShuffle,
  });

  /// The round button, given what a tap on it does (null: disabled).
  final Widget Function(VoidCallback? onTap) button;
  final VoidCallback? onShuffle, onSmartShuffle;

  @override
  State<ShuffleBubbles> createState() => _ShuffleBubblesState();
}

class _ShuffleBubblesState extends State<ShuffleBubbles>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  /// Opening wraps the portal in a BackButtonListener. Without a GlobalKey
  /// Flutter would build a fresh OverlayPortal there, lose the "showing"
  /// state, and the old one's dispose would detach the controller: the
  /// bubbles never appeared (build 41 bug). The key moves it instead.
  final _portalKey = GlobalKey();
  late final _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      reverseDuration: const Duration(milliseconds: 250));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _isOpen = false;

  void _open() {
    setState(() => _isOpen = true);
    _portal.show();
    _c.forward(from: 0);
  }

  Future<void> _close() async {
    if (_isOpen) setState(() => _isOpen = false);
    await _c.reverse();
    if (mounted && !_isOpen) _portal.hide();
  }

  void _pick(VoidCallback? action) {
    _close();
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    // Another page opened on top: tuck the bubbles away at once.
    if (!(ModalRoute.of(context)?.isCurrent ?? true) && _portal.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_portal.isShowing) return;
        _c.value = 0;
        _portal.hide();
        setState(() => _isOpen = false);
      });
    }
    final portal = OverlayPortal(
      key: _portalKey,
      controller: _portal,
      overlayChildBuilder: (_) => Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _bubble(1, 'Smart shuffle', Icons.auto_awesome_rounded,
                  highlight: true, onTap: () => _pick(widget.onSmartShuffle)),
              const SizedBox(height: 10),
              _bubble(0, 'Shuffle', Icons.shuffle_rounded,
                  onTap: () => _pick(widget.onShuffle)),
            ],
          ),
        ),
      ]),
      child: CompositedTransformTarget(
        link: _link,
        child: widget.button(widget.onShuffle == null ? null : _open),
      ),
    );
    // While open, Back closes the bubbles (and stays on the page). JARX's
    // own Back handling pops the page directly, so the bubbles must take
    // the press first; this listener exists only while they're open.
    if (!_isOpen) return portal;
    return BackButtonListener(
      onBackButtonPressed: () async {
        _close();
        return true;
      },
      child: portal,
    );
  }

  /// Bubble [i] (0 nearest the button) pops out a little after the one
  /// below it, with a springy overshoot.
  Widget _bubble(int i, String label, IconData icon,
      {bool highlight = false, required VoidCallback onTap}) {
    final anim = CurvedAnimation(
      parent: _c,
      curve: Interval(0.12 * i, 0.7 + 0.12 * i, curve: Curves.elasticOut),
      reverseCurve: Curves.easeIn,
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 24.0 * (1 + i) * (1 - anim.value)),
          child: Transform.scale(
            scale: anim.value.clamp(0.0, 1.3),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
      ),
      child: Material(
        color: highlight ? Default_Theme.accentColor2 : const Color(0xFF2A2230),
        elevation: 8,
        shadowColor: highlight
            ? Default_Theme.accentColor2.withValues(alpha: 0.6)
            : Colors.black,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Default_Theme.primaryColor1, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Default_Theme.primaryColor1,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}
