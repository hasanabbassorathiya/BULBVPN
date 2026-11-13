import 'package:flutter/material.dart';

/// Metered type. Vazirmatn speaks — it sets Latin and Persian from one family,
/// so an RTL sheet is the same card mirrored rather than a substitute face.
/// Geist Mono measures: every figure on the card is a reading, and a reading
/// gets a face with fixed cells.
///
/// Sizes are absolute logical pixels, exactly as DESIGN.md declares them.
/// `flutter_screenutil`'s `.sp` was removed: it multiplies by the text scale
/// factor and then `Text` applies the platform `TextScaler` again, so a 1.3x
/// setting rendered 1.69x and overflowed the rails that were verified at 1.3x.
///
/// Colors are always explicit at call sites (`context.metered.ink` etc.); there
/// is no palette bridge, so a Night card can never inherit a day color.
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

  /// The issuer band. Print weight, not size, carries the rank.
  static TextStyle masthead({
    required Color color,
    double size = 30,
    FontWeight weight = FontWeight.w800,
    double tracking = 2.2,
  }) =>
      _v(
        family: sans,
        color: color,
        size: size,
        height: 1.0,
        weight: weight,
        tracking: tracking,
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

  /// The rubric under a reading: what the number measures.
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

  /// A measured figure.
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

  /// Transitional alias retained while screens migrate to [label].
  static TextStyle microLabel({required Color color}) => label(color: color);
}
