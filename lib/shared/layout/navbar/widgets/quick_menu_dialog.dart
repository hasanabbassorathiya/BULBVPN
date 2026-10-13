import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_icons.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/custom_webview_screen.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/introduction_dialog.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/quick_menu_item.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/social_icon_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:package_info_plus/package_info_plus.dart';

class QuickMenuDialog extends StatefulWidget {
  const QuickMenuDialog({super.key});

  @override
  State<QuickMenuDialog> createState() => _QuickMenuDialogState();
}

class _QuickMenuDialogState extends State<QuickMenuDialog> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = '${packageInfo.version}+${packageInfo.buildNumber}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: 20.h),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              bottom: 90.h,
              right: 24.w,
              child: Material(
                borderRadius: BorderRadius.circular(12.r),
                color: AppColors.surface,
                child: SizedBox(
                  width: 230.w,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      QuickMenuItem(
                        topBorderRadius: true,
                        title: 'Introduction',
                        onTap: () {
                          Navigator.of(context).pop();
                          showCupertinoDialog(
                            context: context,
                            barrierDismissible: true,
                            builder: (ctx) => const IntroductionDialog(),
                          );
                        },
                      ),
                      Divider(height: 1.h, thickness: 1, color: AppColors.hairline),
                      QuickMenuItem(
                        title: 'Privacy Policy',
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const CustomWebViewScreen(
                                url: 'https://defyxvpn.com/privacy-policy',
                                title: 'Privacy Policy',
                              ),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1.h, thickness: 1, color: AppColors.hairline),
                      QuickMenuItem(
                        title: 'Terms & Conditions',
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const CustomWebViewScreen(
                                url: 'https://defyxvpn.com/terms-and-conditions',
                                title: 'Terms & Conditions',
                              ),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1.h, thickness: 1, color: AppColors.hairline),
                      SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            SocialIconButton(
                              iconPath: AppIcons.telegramPath,
                              url: 'https://t.me/defyxvpn',
                              iconWidth: 17.w,
                              iconHeight: 17.w,
                            ),
                            SocialIconButton(
                              iconPath: AppIcons.instagramPath,
                              url: 'https://instagram.com/defyxvpn',
                              iconWidth: 24.w,
                              iconHeight: 24.w,
                            ),
                            SocialIconButton(
                              iconPath: AppIcons.xPath,
                              url: 'https://x.com/defyxvpn',
                              iconWidth: 20.w,
                              iconHeight: 20.w,
                            ),
                            SocialIconButton(
                              iconPath: AppIcons.facebookPath,
                              url: 'https://fb.com/defyxvpn',
                              enable: false,
                            ),
                            SocialIconButton(
                              iconPath: AppIcons.linkedinPath,
                              url: 'https://linkedin.com/company/defyxvpn',
                              enable: false,
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1.h, thickness: 1, color: AppColors.hairline),
                      QuickMenuItem(
                        title: 'Our Website',
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const CustomWebViewScreen(
                                url: 'https://defyxvpn.com/contact',
                                title: 'Our Website',
                              ),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1.h, thickness: 1, color: AppColors.hairline),
                      Container(
                        height: 44,
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '© BULB VPN',
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontFamily: 'Outfit',
                                color: AppColors.mute,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _version,
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontFamily: 'GeistMono',
                                color: AppColors.steel,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
