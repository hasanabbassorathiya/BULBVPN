import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';

/// One settings line: title, optional sub, optional value at the trailing edge,
/// optional failure colour, optional trailing widget, and an optional long press.
class SimpleTermRow extends StatelessWidget {
  const SimpleTermRow({
    super.key,
    required this.title,
    this.sub,
    this.value,
    this.failed = false,
    this.selected = false,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String? sub;
  final String? value;
  final bool failed;
  final bool selected;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    final titleColor = failed ? s.error : s.ink;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? s.surfaceVariant : s.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body(
                      color: titleColor,
                      size: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub != null && sub!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: AppTextStyles.monoValue(
                        color: s.inkSoft,
                        size: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
            if (value != null && value!.isNotEmpty && trailing == null) ...[
              const SizedBox(width: 10),
              Text(
                value!,
                style: AppTextStyles.monoValue(
                  color: failed ? s.error : s.inkSoft,
                  size: 12,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small mark printed at the trailing edge of a row: e.g. 'NOT PRIVATE'.
class SimpleTrustMark extends StatelessWidget {
  const SimpleTrustMark({
    super.key,
    required this.label,
    this.semantic,
    this.proven = false,
  });

  final String label;
  final String? semantic;
  final bool proven;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return Text(
      label,
      style: AppTextStyles.label(
        color: proven ? s.connected : s.error,
        size: 10,
      ),
      semanticsLabel: semantic,
    );
  }
}
