import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';

/// A single line of print on the card: a claim with an optional mark above it.
///
/// `failed` prints the note in error red instead of ink. `mark` is a small
/// uppercase label (e.g. 'NOT PRIVATE', 'NO TLS') printed before the text.
class SimpleNote extends StatelessWidget {
  const SimpleNote({
    super.key,
    required this.text,
    this.failed = false,
    this.mark,
    this.markSemantic,
  });

  final String text;
  final bool failed;
  final String? mark;
  final String? markSemantic;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    final color = failed ? s.error : s.inkSoft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 12, 26, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mark != null) ...[
            Row(
              children: [
                Text(
                  mark!,
                  style: AppTextStyles.label(
                    color: failed ? s.error : s.inkFaint,
                    size: 10,
                  ),
                ),
                if (markSemantic != null && markSemantic!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '($markSemantic)',
                    style: AppTextStyles.label(
                      color: failed ? s.error : s.inkFaint,
                      size: 10,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
          ],
          Text(
            text,
            style: AppTextStyles.body(
              color: color,
              size: 13,
              height: 1.34,
            ),
          ),
        ],
      ),
    );
  }
}
