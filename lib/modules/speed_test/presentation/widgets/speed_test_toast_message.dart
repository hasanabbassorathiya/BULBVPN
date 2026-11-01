import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

class SpeedTestToastMessage extends StatelessWidget {
  final String message;

  const SpeedTestToastMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      decoration: BoxDecoration(
        color: air.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: air.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: 16, color: air.alertInk),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body(color: air.ink, size: 13),
            ),
          ),
        ],
      ),
    );
  }
}
