import 'package:flutter/material.dart';
import '../../constants/app_theme.dart';

/// An animated loading shimmer effect.
///
/// Renders an animated gradient that sweeps across the widget to indicate
/// content is loading. Automatically adapts its shimmer colors to the
/// current theme.
///
/// ```dart
/// AppShimmer(width: 200, height: 16, borderRadius: 8)
/// ```
class AppShimmer extends StatefulWidget {
  /// Desired width of the shimmer placeholder.
  final double width;

  /// Desired height of the shimmer placeholder.
  final double height;

  /// Corner radius of the shimmer placeholder.
  final double borderRadius;

  const AppShimmer({
    super.key,
    this.width = double.infinity,
    this.height = 20,
    this.borderRadius = 8,
  });

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor = isDark
        ? colors.card
        : colors.card;
    final highlightColor = isDark
        ? colors.cardBorder
        : colors.surface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(-0.5 + 2.0 * _controller.value, 0),
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          ),
        );
      },
    );
  }
}
