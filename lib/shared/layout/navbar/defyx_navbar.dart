import 'package:bulbvpn/app/router/app_router.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/shared/providers/app_screen_provider.dart';
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
        padding: EdgeInsets.only(bottom: 18.h, left: 16.w, right: 16.w),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 64.h,
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(100.r),
                  border: Border.all(color: AppColors.hairline),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(child: _NavPill(screen: AppScreen.speedTest, icon: "speed", label: "Speed", current: currentScreen, onTap: () => _handleSpeedTest(context, ref))),
                    Expanded(child: _NavPill(screen: AppScreen.home, icon: "chield", label: "Home", current: currentScreen, onTap: () => _navigateToHome(context))),
                    Expanded(child: _NavPill(screen: AppScreen.settings, icon: "settings", label: "Info", current: currentScreen, onTap: () => _navigateToSettings(context))),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12.w),
            GestureDetector(
              onTap: () => _showShareDialog(context, ref),
              child: Container(
                width: 56.w,
                height: 56.w,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.hairline),
                  boxShadow: [
                    BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: const Offset(0, 4)),
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/info.svg',
                    width: 22.w,
                    height: 22.w,
                    colorFilter: const ColorFilter.mode(AppColors.steel, BlendMode.srcIn),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

class _NavPill extends StatelessWidget {
  final AppScreen screen;
  final String icon;
  final String label;
  final AppScreen current;
  final VoidCallback onTap;

  const _NavPill({
    required this.screen,
    required this.icon,
    required this.label,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = current == screen;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.amberTint : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/$icon.svg',
              width: 20.w,
              height: 20.w,
              colorFilter: ColorFilter.mode(
                isSelected ? AppColors.amber : AppColors.steel,
                BlendMode.srcIn,
              ),
            ),
            if (isSelected) ...[
              SizedBox(width: 6.w),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.amber,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
