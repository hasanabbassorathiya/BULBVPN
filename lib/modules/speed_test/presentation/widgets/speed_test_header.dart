import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/speed_test/models/speed_test_result.dart';
import 'package:flutter/material.dart';

class SpeedTestHeader extends StatelessWidget {
  final SpeedTestStep step;
  final bool hasResult;

  const SpeedTestHeader({
    super.key,
    required this.step,
    this.hasResult = false,
  });

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final testing = step != SpeedTestStep.ready;
    final kicker = testing
        ? 'LIVE MEASUREMENT'
        : (hasResult ? 'LAST RESULT' : 'THROUGHPUT CHECK');
    final title = testing
        ? 'Measuring link'
        : (hasResult ? 'Last reading' : 'Speed test');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          kicker,
          style: AppTextStyles.label(
            color: testing ? air.accentInk : air.steel,
            size: 10.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: AppTextStyles.display(
            color: air.ink,
            size: 30,
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
