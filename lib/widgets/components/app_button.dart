import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_theme.dart';

/// Button variants for different visual emphasis levels.
enum AppButtonVariant { filled, outlined, text }

/// A premium button supporting filled, outlined, and text variants.
///
/// Filled buttons use the [AppColors.primary] → [AppColors.primaryDark] gradient.
/// Outlined buttons use a border-only style. Text buttons have no background.
///
/// ```dart
/// AppButton(
///   label: 'Connect',
///   variant: AppButtonVariant.filled,
///   icon: Icons.wifi,
///   onPressed: () {},
/// )
/// ```
class AppButton extends StatelessWidget {
  /// The button label text.
  final String label;

  /// Tap callback. When null the button is disabled.
  final VoidCallback? onPressed;

  /// Visual variant. Defaults to [AppButtonVariant.filled].
  final AppButtonVariant variant;

  /// When true shows a [CircularProgressIndicator] instead of the label.
  final bool isLoading;

  /// When true the button stretches to fill its parent width.
  final bool isFullWidth;

  /// Optional leading icon displayed before the label.
  final IconData? icon;

  /// Override the button's accent color (gradient start / border / text).
  final Color? color;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.isLoading = false,
    this.isFullWidth = false,
    this.icon,
    this.color,
  });

  bool get _isEnabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final accentColor = color ?? AppColors.primary;

    final content = _buildContent(context, colors, accentColor);
    final wrapped = isFullWidth ? SizedBox(width: double.infinity, child: content) : content;

    switch (variant) {
      case AppButtonVariant.filled:
        return wrapped;
      case AppButtonVariant.outlined:
        return wrapped;
      case AppButtonVariant.text:
        return wrapped;
    }
  }

  Widget _buildContent(BuildContext context, AppSemanticColors colors, Color accentColor) {
    if (isLoading) {
      return _LoadingButton(colors: colors, isFullWidth: isFullWidth);
    }

    switch (variant) {
      case AppButtonVariant.filled:
        return _FilledButton(
          label: label,
          icon: icon,
          accentColor: accentColor,
          onPressed: _isEnabled ? _onTap : null,
        );
      case AppButtonVariant.outlined:
        return _OutlinedButton(
          label: label,
          icon: icon,
          accentColor: accentColor,
          borderColor: colors.cardBorder,
          textColor: accentColor,
          onPressed: _isEnabled ? _onTap : null,
        );
      case AppButtonVariant.text:
        return _TextButton(
          label: label,
          icon: icon,
          accentColor: accentColor,
          onPressed: _isEnabled ? _onTap : null,
        );
    }
  }

  void _onTap() {
    HapticFeedback.lightImpact();
    onPressed?.call();
  }
}

class _LoadingButton extends StatelessWidget {
  final AppSemanticColors colors;
  final bool isFullWidth;

  const _LoadingButton({required this.colors, this.isFullWidth = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: isFullWidth ? Alignment.center : null,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AppRadius.lgAll,
      ),
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _FilledButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color accentColor;
  final VoidCallback? onPressed;

  const _FilledButton({
    required this.label,
    this.icon,
    required this.accentColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accentColor, AppColors.primaryDark],
          ),
          borderRadius: AppRadius.lgAll,
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Colors.black),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlinedButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color accentColor;
  final Color borderColor;
  final Color textColor;
  final VoidCallback? onPressed;

  const _OutlinedButton({
    required this.label,
    this.icon,
    required this.accentColor,
    required this.borderColor,
    required this.textColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: accentColor, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: accentColor),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              label,
              style: TextStyle(
                color: accentColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color accentColor;
  final VoidCallback? onPressed;

  const _TextButton({
    required this.label,
    this.icon,
    required this.accentColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: accentColor),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              label,
              style: TextStyle(
                color: accentColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
