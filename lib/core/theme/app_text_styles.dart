import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'app_colors.dart';

/// Typography utilities. Every number, metric, and timestamp in the product
/// renders in GeistMono with tabular figures (DESIGN.md §3).
class AppTextStyles {
  static const String mono = 'GeistMono';

  /// 11px mono uppercase micro-label.
  static TextStyle microLabel({Color color = AppColors.mute}) => TextStyle(
        fontFamily: mono,
        fontSize: 11.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.9,
        color: color,
      );

  /// Large instrument readout (speed, ping, timer).
  static TextStyle metric({
    double size = 32,
    Color color = AppColors.ink,
    FontWeight weight = FontWeight.w500,
  }) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size.sp,
        fontWeight: weight,
        height: 1.0,
        letterSpacing: -0.5,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Compact monospace value (latency, counters, byte sizes).
  static TextStyle monoValue({
    double size = 13,
    Color color = AppColors.ink,
    FontWeight weight = FontWeight.w500,
  }) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size.sp,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Log console line.
  static TextStyle logLine({Color color = AppColors.steel}) => TextStyle(
        fontFamily: mono,
        fontSize: 11.sp,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );
}
