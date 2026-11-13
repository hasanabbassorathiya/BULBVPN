import 'package:flutter/material.dart';

/// Press feedback for a printed surface. A Metered control is cut into or
/// printed on PVC, so it answers a finger by sinking, not by rippling: a
/// Material ink splash would spread across the card and read as glass.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.sink = true,
  });

  /// Flat variant for printed rows: the ink dips instead of the sheet moving.
  const Pressable.flat({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
  }) : sink = false;

  final Widget child;
  final VoidCallback? onTap;

  /// A second reading of the same print. The plate hides one affordance per
  /// part rather than printing a second key nobody asked for, so a support
  /// gesture lives here instead of in a menu.
  final VoidCallback? onLongPress;
  final bool enabled;

  /// True for controls that are pushed, false for print that is read.
  final bool sink;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  static const _press = Duration(milliseconds: 90);
  static const _release = Duration(milliseconds: 150);

  bool _down = false;
  bool _hover = false;

  bool get _live =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _set(bool Function() next) => setState(() => _down = next());

  @override
  Widget build(BuildContext context) {
    final held = _live && _down;
    final lifted = _live && _hover && !_down;
    return MouseRegion(
      cursor: _live ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: _live ? (_) => setState(() => _hover = true) : null,
      onExit: _live
          ? (_) => setState(() {
              _hover = false;
              _down = false;
            })
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _live ? widget.onTap : null,
        onLongPress: _live ? widget.onLongPress : null,
        onTapDown: _live ? (_) => _set(() => true) : null,
        onTapUp: _live ? (_) => _set(() => false) : null,
        onTapCancel: _live ? () => _set(() => false) : null,
        child: widget.sink
            ? AnimatedSlide(
                offset: Offset(0, held ? 0.022 : 0),
                duration: held ? _press : _release,
                curve: held ? Curves.easeOut : Curves.easeOutBack,
                child: AnimatedScale(
                  scale: held ? 0.988 : (lifted ? 1.006 : 1.0),
                  duration: held ? _press : _release,
                  child: widget.child,
                ),
              )
            : AnimatedOpacity(
                opacity: held ? 0.55 : 1.0,
                duration: held ? _press : _release,
                child: widget.child,
              ),
      ),
    );
  }
}
