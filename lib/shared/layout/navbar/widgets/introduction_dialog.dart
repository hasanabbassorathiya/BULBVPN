import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/copyable_link.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/intro_link_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class IntroductionDialog extends StatelessWidget {
  const IntroductionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15.r),
        side: const BorderSide(color: AppColors.hairline),
      ),
      child: Container(
        padding: EdgeInsets.all(25.w),
        width: 343.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Introduction',
              style: TextStyle(
                fontSize: 18.sp,
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            SizedBox(height: 15.h),
            Text(
              'BULB VPN ensures secure access to public information and a free browsing experience.',
              style: TextStyle(
                fontSize: 15.sp,
                fontFamily: 'Outfit',
                color: AppColors.steel,
                height: 1.4,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              'LEARN MORE',
              style: AppTextStyles.microLabel(color: AppColors.amber),
            ),
            SizedBox(height: 15.h),
            IntroLinkItem(
              title: 'Source code',
              url: 'https://github.com/UnboundTechCo/defyxVPN',
            ),
            SizedBox(height: 10.h),
            IntroLinkItem(
              title: 'Open source licenses',
              url:
                  'https://github.com/UnboundTechCo/DXcore?tab=readme-ov-file#third-party-licenses',
            ),
            SizedBox(height: 10.h),
            CopyableLink(text: 'defyxvpn.com'),
            SizedBox(height: 10.h),
            IntroLinkItem(
              title: 'Beta Community',
              url: 'https://t.me/+KuigyCHadIpiNDhi',
            ),
            SizedBox(height: 20.h),
            SizedBox(
              width: double.infinity,
              height: 46.h,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  shadowColor: Colors.transparent,
                  backgroundColor: AppColors.raised,
                  foregroundColor: AppColors.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Got it',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.steel,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
