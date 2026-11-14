import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';

/// An action row: a title, a supporting line of text, and a key label.
class SimpleAction extends StatelessWidget {
  const SimpleAction({
    super.key,
    required this.title,
    required this.text,
    required this.keyLabel,
    required this.onTap,
  });

  final String title;
  final String text;
  final String keyLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(10),
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
                      color: s.ink,
                      size: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: AppTextStyles.monoValue(
                      color: s.inkSoft,
                      size: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              keyLabel,
              style: AppTextStyles.label(
                color: s.connected,
                size: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
