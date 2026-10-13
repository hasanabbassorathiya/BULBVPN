import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/utils/format_number.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SpeedValueDisplay extends StatelessWidget {
  final double value;
  final String unit;
  final String? subtitle;
  final Color subtitleColor;

  const SpeedValueDisplay({
    super.key,
    required this.value,
    required this.unit,
    this.subtitle,
    required this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 4.h,
      children: [
        if (subtitle != null)
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12.sp,
              fontFamily: 'Outfit',
              color: subtitleColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 4.h,
          children: [
            SizedBox(
              width: 150.w,
              height: 90.h,
              child: Center(
                child: Text(
                  doubleFormatNumber(value),
                  style: TextStyle(
                    fontSize: value >= 1000
                        ? 25.sp
                        : value >= 100
                            ? 50.sp
                            : value >= 10
                                ? 70.sp
                                : 90.sp,
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                    height: 1.0,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 6.h),
              child: Text(
                unit,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w400,
                  color: AppColors.steel,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
