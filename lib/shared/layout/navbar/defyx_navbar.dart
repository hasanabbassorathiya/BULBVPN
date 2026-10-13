import 'package:bulbvpn/app/router/app_router.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/shared/providers/app_screen_provider.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/defyx_nav_item.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/quick_menu_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class DefyxNavBar extends ConsumerWidget {
  const DefyxNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final currentScreen = _getCurrentScreenFromLocation(location);

    return SafeArea(
        child: Padding(
      padding: EdgeInsets.only(bottom: 20.h),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 210.w,
            height: 62.h,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(100.r),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                DefyxNavItem(
                  screen: AppScreen.speedTest,
                  icon: "speed",
                  current: currentScreen,
                  onTap: () => _handleSpeedTest(context, ref),
                ),
                DefyxNavItem(
                  screen: AppScreen.home,
                  icon: "chield",
                  current: currentScreen,
                  onTap: () => _navigateToHome(context),
                ),
                DefyxNavItem(
                  screen: AppScreen.settings,
                  icon: "settings",
                  current: currentScreen,
                  onTap: () => _navigateToSettings(context),
                ),
              ],
            ),
          ),
          Positioned(
            right: 24.w,
            child: GestureDetector(
              onTap: () => _showShareDialog(context, ref),
              child: Container(
                width: 56.w,
                height: 56.w,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/info.svg',
                    width: 24.w,
                    height: 24.w,
                    colorFilter: const ColorFilter.mode(
                      AppColors.steel,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ));
  }

  void _handleSpeedTest(BuildContext context, WidgetRef ref) {
    context.go(DefyxVPNRoutes.speedTest.route);
  }

  void _navigateToHome(BuildContext context) {
    context.go(DefyxVPNRoutes.main.route);
  }

  void _navigateToSettings(BuildContext context) {
    context.go(DefyxVPNRoutes.settings.route);
  }

  AppScreen _getCurrentScreenFromLocation(String location) {
    switch (location) {
      case '/main':
        return AppScreen.home;
      case '/settings':
        return AppScreen.settings;
      case '/speedTest':
        return AppScreen.speedTest;
      default:
        return AppScreen.home;
    }
  }

  void _showShareDialog(BuildContext context, WidgetRef ref) {
    ref.read(currentScreenProvider.notifier).state = AppScreen.share;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Quick Menu',
      barrierColor: AppColors.canvas.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const QuickMenuDialog();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curvedAnimation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
            alignment: Alignment.bottomRight,
            child: child,
          ),
        );
      },
    ).then((_) {
      ref.read(currentScreenProvider.notifier).state = AppScreen.home;
    });
  }
}
