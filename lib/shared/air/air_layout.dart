import 'package:flutter/widgets.dart';

/// Shared measurements for Clear Air screens. One rail, one gutter, no
/// per-screen drift.
abstract final class AirLayout {
  /// Phone content ceiling (main, servers, speed).
  static const double rail = 560;

  /// Reading-heavy screens (settings, legal, paywall).
  static const double wideRail = 720;

  static const double gutter = 20;
  static const double sectionGap = 28;
}

/// Centres content inside [maxWidth] and applies the horizontal gutter.
class AirRail extends StatelessWidget {
  const AirRail({
    super.key,
    required this.child,
    this.maxWidth = AirLayout.rail,
    this.padding = const EdgeInsets.symmetric(horizontal: AirLayout.gutter),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
