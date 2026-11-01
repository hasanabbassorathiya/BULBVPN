import 'package:flutter/material.dart';

import '../../core/theme/air_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Sheet actions: 50 px high, 12 px radius. Primary is ink on paper; secondary
/// is a hairline. No elevation, no gradients.
class AirButton extends StatelessWidget {
  const AirButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = true,
    this.icon,
    this.height = 50,
  }) : _primary = true;

  const AirButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = true,
    this.icon,
    this.height = 50,
  }) : _primary = false;

  final String label;
  final VoidCallback? onPressed;
  final bool expand;
  final IconData? icon;
  final double height;
  final bool _primary;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final fg = _primary ? air.surface : air.ink;
    final radius = BorderRadius.circular(12);
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: AppTextStyles.body(
        color: fg,
        size: 15,
        weight: FontWeight.w600,
      ),
    );

    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: SizedBox(
        height: height,
        width: expand ? double.infinity : null,
        child: Material(
          color: _primary ? air.ink : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: _primary
                ? BorderSide.none
                : BorderSide(color: air.hairlineStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            splashColor: fg.withValues(alpha: 0.08),
            highlightColor: fg.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 8),
                  ],
                  if (expand) Flexible(child: text) else text,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
