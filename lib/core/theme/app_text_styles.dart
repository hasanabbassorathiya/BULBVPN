import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';


/// Clear Air type: Schibsted Grotesk speaks, Geist Mono measures.
///
/// Colors are always explicit at call sites (`context.air.ink` etc.); there is
/// no palette bridge, so a Night Air screen can never inherit a day color.
class AppTextStyles {
  static const String sans = 'SchibstedGrotesk';
  static const String mono = 'GeistMono';

  static TextStyle display({
    required Color color,
    double size = 34,
    FontWeight weight = FontWeight.w600,
  }) =>
      TextStyle(
        fontFamily: sans,
        fontSize: size.sp,
        height: 1.06,
        fontWeight: weight,
        letterSpacing: -0.8,
        color: color,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
      );

  static TextStyle title({
    required Color color,
    double size = 21,
    FontWeight weight = FontWeight.w600,
  }) =>
      TextStyle(
        fontFamily: sans,
        fontSize: size.sp,
        height: 1.18,
        fontWeight: weight,
        letterSpacing: -0.3,
        color: color,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
      );

  static TextStyle body({
    required Color color,
    double size = 15,
    FontWeight weight = FontWeight.w400,
    double height = 1.42,
  }) =>
      TextStyle(
        fontFamily: sans,
        fontSize: size.sp,
        height: height,
        fontWeight: weight,
        color: color,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
      );

  static TextStyle label({
    required Color color,
    double size = 10.5,
    double tracking = 0.8,
  }) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size.sp,
        height: 1.2,
        fontWeight: FontWeight.w500,
        letterSpacing: tracking,
        color: color,
      );

  static TextStyle metric({
    required Color color,
    double size = 26,
    FontWeight weight = FontWeight.w500,
  }) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size.sp,
        height: 1.0,
        fontWeight: weight,
        letterSpacing: -0.6,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle monoValue({
    required Color color,
    double size = 12,
    FontWeight weight = FontWeight.w500,
  }) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size.sp,
        height: 1.25,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle logLine({required Color color}) => TextStyle(
        fontFamily: mono,
        fontSize: 11.sp,
        height: 1.5,
        color: color,
      );

  /// Transitional alias retained while screens migrate to [label].
  static TextStyle microLabel({required Color color}) => TextStyle(
        fontFamily: mono,
        fontSize: 11.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.9,
        color: color,
      );
}
