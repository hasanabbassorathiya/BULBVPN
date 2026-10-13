import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/custom_webview_screen.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/introduction_dialog.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/quick_menu_item.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
                                url: AppLinks.privacy,
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
                                url: AppLinks.terms,
                                title: 'Terms & Conditions',
                              ),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1.h, thickness: 1, color: AppColors.hairline),
                      QuickMenuItem(
                        title: 'Our Website',
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const CustomWebViewScreen(
                                url: AppLinks.website,
                                title: 'Our Website',
                              ),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1.h, thickness: 1, color: AppColors.hairline),
                      QuickMenuItem(
                        title: 'Contact Us',
                        onTap: () {
                          Navigator.of(context).pop();
                          launchUrl(
                            Uri.parse('mailto:${AppLinks.contactEmail}'),
                            mode: LaunchMode.externalApplication,
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
