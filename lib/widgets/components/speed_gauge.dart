import 'package:flutter/material.dart';
import '../../constants/app_theme.dart';

/// A premium animated speed display widget.
///
/// Shows a large animated number with unit label and descriptive text.
/// Uses [AnimatedSwitcher] for smooth number transitions.
///
/// ```dart
/// SpeedGauge(
///   value: 85.4,
///   unit: 'Mbps',
///   label: 'Download',
///   color: AppColors.primary,
/// )
/// ```
class SpeedGauge extends StatelessWidget {
  /// The numeric value to display.
  final double value;

  /// Unit string (e.g. 'Mbps', 'Kbps', 'ms').
  final String unit;

  /// Accent color for the value and decoration.
  final Color color;

  /// Descriptive label (e.g. 'Download', 'Upload', 'Ping').
  final String label;

  const SpeedGauge({
    super.key,
    required this.value,
    this.unit = 'Mbps',
    this.color = AppColors.primary,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        Text(
          label.toUpperCase(),
          style: AppTypography.labelMedium(context).copyWith(
            color: AppSemanticColors.of(context).textMuted,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Animated value
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              ),
            );
          },
          child: Text(
            _formatValue(value),
            key: ValueKey(_formatValue(value)),
            style: AppTypography.displayLarge(context).copyWith(
              color: color,
              fontSize: 48,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Unit label
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: AppRadius.pillAll,
          ),
          child: Text(
            unit,
            style: AppTypography.labelLarge(context).copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  String _formatValue(double val) {
    if (val >= 1000) return (val / 1000).toStringAsFixed(1);
    if (val >= 100) return val.toStringAsFixed(1);
    if (val >= 10) return val.toStringAsFixed(2);
    if (val >= 1) return val.toStringAsFixed(2);
    if (val > 0) return val.toStringAsFixed(2);
    return '0.00';
  }
}
