import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';

/// The one key a face has left: a single action button.
class SimpleKey extends StatelessWidget {
  const SimpleKey({
    super.key,
    required this.label,
    this.busy = false,
    this.emphasis = false,
    this.onTap,
  });

  final String label;
  final bool busy;
  final bool emphasis;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    final enabled = onTap != null && !busy;
    final color = emphasis
        ? (enabled ? s.connected : s.inkFaint)
        : (enabled ? s.primary : s.inkFaint);
    final textColor = enabled ? s.connectedInk : s.inkFaint;

    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: AppTextStyles.body(
                color: textColor,
                size: 15,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
