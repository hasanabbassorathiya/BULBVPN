import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';
import 'package:flutter/material.dart';

class SpeedTestToastMessage extends StatelessWidget {
  final String message;

  const SpeedTestToastMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: 16, color: s.error),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body(color: s.ink, size: 13),
            ),
          ),
        ],
      ),
    );
  }
}
