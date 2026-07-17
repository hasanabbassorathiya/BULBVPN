import 'package:flutter/material.dart';
import '../../constants/app_theme.dart';

/// Size variants for the badge.
enum AppBadgeSize { small, medium, large }

/// A pill-shaped status badge with optional icon.
///
/// Use a semantic color from [AppColors] (e.g. [AppColors.connected],
/// [AppColors.warning]) or any custom color.
///
/// ```dart
/// AppBadge(
///   label: 'Connected',
///   color: AppColors.connected,
///   icon: Icons.check_circle_outline,
/// )
/// ```
class AppBadge extends StatelessWidget {
  /// The badge label text.
  final String label;

  /// Background/text accent color.
  final Color color;

  /// Optional icon displayed to the left of the label.
  final IconData? icon;

  /// Badge size. Defaults to [AppBadgeSize.medium].
  final AppBadgeSize size;

  const AppBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.size = AppBadgeSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = _textStyle(context);
    final horizontalPadding = _horizontalPadding;
    final iconSize = _iconSize;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: _verticalPadding,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: color),
            SizedBox(width: _iconGap),
          ],
          Text(label, style: textStyle),
        ],
      ),
    );
  }

  TextStyle _textStyle(BuildContext context) {
    switch (size) {
      case AppBadgeSize.small:
        return AppTypography.labelSmall(context).copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        );
      case AppBadgeSize.medium:
        return AppTypography.labelMedium(context).copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        );
      case AppBadgeSize.large:
        return AppTypography.labelLarge(context).copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        );
    }
  }

  double get _horizontalPadding {
    switch (size) {
      case AppBadgeSize.small:
        return AppSpacing.sm;
      case AppBadgeSize.medium:
        return AppSpacing.md;
      case AppBadgeSize.large:
        return AppSpacing.lg;
    }
  }

  double get _verticalPadding {
    switch (size) {
      case AppBadgeSize.small:
        return AppSpacing.xs;
      case AppBadgeSize.medium:
        return AppSpacing.xs;
      case AppBadgeSize.large:
        return AppSpacing.sm;
    }
  }

  double get _iconSize {
    switch (size) {
      case AppBadgeSize.small:
        return 10;
      case AppBadgeSize.medium:
        return 14;
      case AppBadgeSize.large:
        return 16;
    }
  }

  double get _iconGap => size == AppBadgeSize.small ? 3 : AppSpacing.xs;
}
