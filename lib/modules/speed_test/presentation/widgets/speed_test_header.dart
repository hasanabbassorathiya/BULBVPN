import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../models/speed_test_result.dart';

class SpeedTestHeader extends StatelessWidget {
  final SpeedTestStep step;

  const SpeedTestHeader({
    super.key,
    required this.step,
  });

  @override
  Widget build(BuildContext context) {
    final bool testing = step != SpeedTestStep.ready;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          testing ? 'LIVE MEASUREMENT' : 'THROUGHPUT CHECK',
          style: AppTextStyles.microLabel(
            color: testing ? AppColors.amber : AppColors.mute,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          testing ? 'Measuring link' : 'Speed test',
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
