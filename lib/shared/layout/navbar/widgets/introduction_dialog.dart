import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/shared/air/air_buttons.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/copyable_link.dart';
import 'package:flutter/material.dart';

class IntroductionDialog extends StatelessWidget {
  const IntroductionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: air.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: air.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BULBVPN',
                style: AppTextStyles.label(color: air.steel, size: 10.5),
              ),
              const SizedBox(height: 10),
              Text(
                'A quieter way through.',
                style: AppTextStyles.title(color: air.ink, size: 21),
              ),
              const SizedBox(height: 10),
              Text(
                'BULBVPN measures working relays before you tap, so the '
                'first byte arrives sooner. Bootstrap relays are public and '
                'not private — you can import your own server instead.',
                style: AppTextStyles.body(color: air.steel, size: 14),
              ),
              const SizedBox(height: 16),
              CopyableLink(text: AppLinks.website),
              const SizedBox(height: 18),
              AirButton.secondary(
                label: 'Got it',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
