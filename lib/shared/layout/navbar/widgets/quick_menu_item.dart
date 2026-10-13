import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class QuickMenuItem extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final bool? topBorderRadius;
  final bool? bottomBorderRadius;

  const QuickMenuItem({
    super.key,
    required this.title,
    required this.onTap,
    this.topBorderRadius = false,
    this.bottomBorderRadius = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: AppColors.raised,
      splashColor: AppColors.raised,
      highlightColor: AppColors.raised,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(topBorderRadius! ? 12.r : 0),
        topRight: Radius.circular(topBorderRadius! ? 12.r : 0),
        bottomLeft: Radius.circular(bottomBorderRadius! ? 12.r : 0),
        bottomRight: Radius.circular(bottomBorderRadius! ? 12.r : 0),
      ),
      child: Container(
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16.sp,
                fontFamily: 'Outfit',
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
