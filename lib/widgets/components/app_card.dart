import 'package:flutter/material.dart';
import '../../constants/app_theme.dart';

/// A premium card component with gradient background and semantic theming.
///
/// Automatically adapts to dark and light themes via [AppSemanticColors].
///
/// ```dart
/// AppCard(
///   child: Text('Hello'),
///   onTap: () => print('tapped'),
/// )
/// ```
class AppCard extends StatelessWidget {
  /// The child widget displayed inside the card.
  final Widget child;

  /// Internal padding. Defaults to [AppSpacing.lg].
  final EdgeInsetsGeometry? padding;

  /// External margin around the card.
  final EdgeInsetsGeometry? margin;

  /// Tap callback. When non-null the card becomes interactive.
  final VoidCallback? onTap;

  /// Override the default gradient background from the current theme.
  final Gradient? gradient;

  /// Override the default border color from the current theme.
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.gradient,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);

    final effectiveGradient = gradient ?? colors.cardGradient;
    final effectiveBorderColor = borderColor ?? colors.cardBorder;

    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: effectiveGradient,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: effectiveBorderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }

    return card;
  }
}
