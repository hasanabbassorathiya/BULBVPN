import 'package:flutter/material.dart';

/// Simple type styles for the VPN app.
///
/// Vazirmatn sets Latin and Persian from one family, so an RTL sheet is the
/// same card mirrored rather than a substitute face. Geist Mono is used for
/// figures, metrics, IPs, and timers — fixed cells so readings never drift.
///
/// Sizes are absolute logical pixels. `flutter_screenutil`'s `.sp` is banned:
/// it multiplies by the text scale factor and then `Text` applies the platform
/// `TextScaler` again, so a 1.3x setting rendered 1.69x.
///
/// Colors are explicit at call sites (`context.simple.ink`, etc.).
class AppTextStyles {
  static const String sans = 'Vazirmatn';
  static const String mono = 'GeistMono';

  static TextStyle _v({
    required String family,
    required Color color,
    required double size,
    required double height,
    required FontWeight weight,
    double tracking = 0,
    bool tabular = false,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: tracking,
        color: color,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      );

  static TextStyle display({
    required Color color,
    double size = 34,
    FontWeight weight = FontWeight.w700,
    double tracking = -0.6,
  }) =>
      _v(
        family: sans,
        color: color,
        size: size,
        height: 1.06,
        weight: weight,
        tracking: tracking,
      );

  static TextStyle title({
    required Color color,
    double size = 20,
    FontWeight weight = FontWeight.w700,
    double tracking = 0.2,
  }) =>
      _v(
        family: sans,
        color: color,
        size: size,
        height: 1.18,
        weight: weight,
        tracking: tracking,
      );

  static TextStyle body({
    required Color color,
    double size = 15,
    FontWeight weight = FontWeight.w400,
    double height = 1.45,
  }) =>
      _v(
        family: sans,
        color: color,
        size: size,
        height: height,
        weight: weight,
      );

  static TextStyle label({
    required Color color,
    double size = 10,
    double tracking = 1.4,
  }) =>
      _v(
        family: mono,
        color: color,
        size: size,
        height: 1.2,
        weight: FontWeight.w500,
        tracking: tracking,
      );

  static TextStyle metric({
    required Color color,
    double size = 26,
    FontWeight weight = FontWeight.w700,
    double tracking = -0.4,
  }) =>
      _v(
        family: mono,
        color: color,
        size: size,
        height: 1.0,
        weight: weight,
        tracking: tracking,
        tabular: true,
      );

  static TextStyle monoValue({
    required Color color,
    double size = 12,
    FontWeight weight = FontWeight.w500,
    double tracking = 0,
    double height = 1.25,
  }) =>
      _v(
        family: mono,
        color: color,
        size: size,
        height: height,
        weight: weight,
        tracking: tracking,
        tabular: true,
      );

  static TextStyle logLine({required Color color}) => _v(
        family: mono,
        color: color,
        size: 11,
        height: 1.5,
        weight: FontWeight.w400,
      );
}
