import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../models/speed_test_result.dart';

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
    final bool testing = step != SpeedTestStep.ready;
    final String kicker = testing
        ? 'LIVE MEASUREMENT'
        : (hasResult ? 'LAST RESULT' : 'THROUGHPUT CHECK');
    final String title = testing
        ? 'Measuring link'
        : (hasResult ? 'One reading' : 'Speed test');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          kicker,
          style: AppTextStyles.microLabel(
            color: testing ? AppColors.amber : AppColors.mute,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 32.sp,
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w600,
            letterSpacing: -0.6,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}
