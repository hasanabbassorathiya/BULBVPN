import 'package:flutter/material.dart';

import '../../core/theme/air_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// A titled group of hairline rows on the ground. No cards, no shadows.
class AirSection extends StatelessWidget {
  const AirSection({
    super.key,
    required this.title,
    required this.rows,
    this.note,
  });

  final String title;
  final List<Widget> rows;
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final note = this.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: AppTextStyles.label(color: air.steel, size: 10.5),
          ),
        ),
        Container(height: 1, color: air.hairline),
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i != rows.length - 1) Container(height: 1, color: air.hairline),
        ],
        Container(height: 1, color: air.hairline),
        if (note != null) ...[
          const SizedBox(height: 10),
          note,
        ],
      ],
    );
  }
}

/// One 56 px row (48 dense): title, optional subtitle, optional value or
/// trailing control. The whole row is the tap target.
class AirRow extends StatelessWidget {
  const AirRow({
    super.key,
    this.title,
    this.subtitle,
    this.value,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.dense = false,
    this.titleColor,
    this.chevron = true,
  });

  final String? title;
  final String? subtitle;
  final String? value;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool dense;
  final Color? titleColor;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final title = this.title;
    final subtitle = this.subtitle;
    final value = this.value;
    final trailing = this.trailing;
    final leading = this.leading;

    final body = ConstrainedBox(
      constraints: BoxConstraints(minHeight: dense ? 48 : 56),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 8 : 12),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        color: titleColor ?? air.ink,
                        size: 15,
                        weight: FontWeight.w500,
                      ),
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      // Two lines hold these subtitles at 1.0; the third keeps
                      // 1.3x text from ending mid-word.
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: air.steel, size: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 12),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.monoValue(color: air.steel, size: 12),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
            if (trailing == null && onTap != null && chevron) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: air.mute),
            ],
          ],
        ),
      ),
    );

    if (onTap == null && onLongPress == null) {
      return ColoredBox(
        color: selected ? air.surface : Colors.transparent,
        child: body,
      );
    }
    return Material(
      color: selected ? air.surface : Colors.transparent,
      child: InkWell(onTap: onTap, onLongPress: onLongPress, child: body),
    );
  }
}
