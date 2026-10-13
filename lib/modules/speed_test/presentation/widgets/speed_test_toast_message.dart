import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SpeedTestToastMessage extends StatelessWidget {
  final String message;

  const SpeedTestToastMessage({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: 80.h),
      alignment: Alignment.center,
      // margin: EdgeInsets.symmetric(horizontal: 20.w),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 16.sp,
          fontFamily: 'Outfit',
          color: AppColors.ink,
          height: 1.4,
        ),
      ),
    );
  }
}
