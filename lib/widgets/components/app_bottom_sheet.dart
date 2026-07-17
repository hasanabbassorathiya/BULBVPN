import 'package:flutter/material.dart';
import '../../constants/app_theme.dart';

/// A premium bottom sheet with drag handle, title, and semantic theming.
///
/// Automatically adapts to dark and light themes via [AppSemanticColors].
/// Includes a drag-to-dismiss handle and optional close button.
///
/// ```dart
/// AppBottomSheet.show(
///   context: context,
///   title: 'Server List',
///   child: ServerList(),
/// );
/// ```
class AppBottomSheet extends StatelessWidget {
  /// The content displayed below the title and handle.
  final Widget child;

  /// Optional title displayed at the top of the sheet.
  final String? title;

  /// Whether to show a close button in the top-right corner.
  final bool showCloseButton;

  /// Maximum height as a fraction of screen height.
  final double maxHeightFraction;

  const AppBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.showCloseButton = true,
    this.maxHeightFraction = 0.85,
  });

  /// Convenience method to show the bottom sheet.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    bool showCloseButton = true,
    double maxHeightFraction = 0.85,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (_) => AppBottomSheet(
        title: title,
        showCloseButton: showCloseButton,
        maxHeightFraction: maxHeightFraction,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return DraggableScrollableSheet(
      initialChildSize: maxHeightFraction,
      minChildSize: 0.3,
      maxChildSize: maxHeightFraction,
      builder: (context, scrollController) {
        return Container(
          height: screenHeight * maxHeightFraction,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              _DragHandle(color: colors.cardBorder),
              // Header
              if (title != null || showCloseButton)
                _Header(
                  title: title,
                  showCloseButton: showCloseButton,
                  colors: colors,
                ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DragHandle extends StatelessWidget {
  final Color color;

  const _DragHandle({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String? title;
  final bool showCloseButton;
  final AppSemanticColors colors;

  const _Header({
    this.title,
    required this.showCloseButton,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (title != null)
            Expanded(
              child: Text(
                title!,
                style: AppTypography.titleLarge(context).copyWith(
                  color: colors.textPrimary,
                ),
              ),
            )
          else
            const Spacer(),
          if (showCloseButton)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
