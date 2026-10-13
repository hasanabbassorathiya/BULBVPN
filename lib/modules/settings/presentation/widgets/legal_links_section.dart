import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

/// Static legal / website links rendered below the settings groups.
class LegalLinksSection extends StatelessWidget {
  const LegalLinksSection({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _row(BuildContext context, String title, String url) {
    return InkWell(
      onTap: () => _open(url),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17.sp,
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w400,
                  color: AppColors.ink,
                ),
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 16.sp, color: AppColors.mute),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 12.h, left: 4.w),
          child: Text('LEGAL', style: AppTextStyles.microLabel()),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16.r),
          ),
          padding: EdgeInsets.fromLTRB(2.w, 1.h, 2.w, 1.h),
          child: Column(
            children: [
              _row(context, 'Privacy policy', AppLinks.privacy),
              Container(
                height: 1,
                margin: EdgeInsets.symmetric(horizontal: 12.w),
                color: AppColors.hairline,
              ),
              _row(context, 'Terms of service', AppLinks.terms),
              Container(
                height: 1,
                margin: EdgeInsets.symmetric(horizontal: 12.w),
                color: AppColors.hairline,
              ),
              _row(context, 'Website', AppLinks.website),
              Container(
                height: 1,
                margin: EdgeInsets.symmetric(horizontal: 12.w),
                color: AppColors.hairline,
              ),
              _row(context, 'Contact', 'mailto:${AppLinks.contactEmail}'),
            ],
          ),
        ),
      ],
    );
  }
}
