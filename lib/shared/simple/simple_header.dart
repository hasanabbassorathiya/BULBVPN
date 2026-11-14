import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';

/// The head of a settings face: title, optional note, optional back key, and an
/// optional trailing key. A pushed screen owns its own back; a tab face does not.
class SimpleHeader extends StatelessWidget {
  const SimpleHeader({
    super.key,
    required this.title,
    this.note,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? note;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: s.hairline, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 24, 24, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (onBack != null) ...[
              InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.chevron_left, size: 20),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.title(
                      color: s.ink,
                      size: 18,
                      weight: FontWeight.w700,
                      tracking: 0.2,
                    ),
                  ),
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.monoValue(
                        color: s.inkSoft,
                        size: 13,
                        height: 1.0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
