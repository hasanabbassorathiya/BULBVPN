import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class DefyxSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final double? width;
  final double? height;

  const DefyxSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? 48.w,
      height: height ?? 24.h,
      child: CupertinoSwitch(
        value: value,
        onChanged: enabled ? onChanged : null,
        activeTrackColor: AppColors.amber,
        inactiveTrackColor: AppColors.graphite,
        thumbColor: AppColors.ink,
      ),
    );
  }
}
