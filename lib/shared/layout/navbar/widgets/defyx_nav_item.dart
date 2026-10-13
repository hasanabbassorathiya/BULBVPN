import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/shared/providers/app_screen_provider.dart';
import 'package:bulbvpn/shared/widgets/staggered_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class DefyxNavItem extends StatelessWidget {
  final AppScreen screen;
  final String icon;
  final AppScreen current;
  final VoidCallback onTap;

  static const double _navItemSize = 55;
  static const double _defaultIconSize = 24;

  const DefyxNavItem({
    super.key,
    required this.screen,
    required this.icon,
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
        curve: kSpring,
        width: _navItemSize.w,
        height: _navItemSize.w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? AppColors.amberTint : Colors.transparent,
        ),
        child: Center(
          child: SvgPicture.asset(
            'assets/icons/$icon.svg',
            width: _defaultIconSize.w,
            height: _defaultIconSize.w,
            colorFilter: ColorFilter.mode(
              isSelected ? AppColors.amber : AppColors.steel,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}
