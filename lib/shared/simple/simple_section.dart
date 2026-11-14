import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';

/// A section header inside the card: a title with an optional mark and note.
class SimpleSection extends StatelessWidget {
  const SimpleSection({
    super.key,
    required this.title,
    this.proven = false,
    this.leading,
    this.note,
    this.disclosure,
    this.disclosureSemantics,
  });

  final String title;
  final bool proven;
  final Widget? leading;
  final String? note;
  final String? disclosure;
  final String? disclosureSemantics;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.title(
                    color: s.ink,
                    size: 16,
                    weight: FontWeight.w700,
                    tracking: 0.2,
                  ),
                ),
                if (note != null && note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    note!,
                    style: AppTextStyles.body(
                      color: s.inkSoft,
                      size: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (disclosure != null && disclosure!.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(
              disclosure!,
              style: AppTextStyles.label(
                color: proven ? s.connected : s.error,
                size: 10,
              ),
              semanticsLabel: disclosureSemantics,
            ),
          ],
        ],
      ),
    );
  }
}
