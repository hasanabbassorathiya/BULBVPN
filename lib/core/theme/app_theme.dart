import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'air_colors.dart';
import 'app_text_styles.dart';
import 'metered_colors.dart';

class AppTheme {
  static const String fontFamily = AppTextStyles.sans;

  static ThemeData get light => _build(MeteredColors.day);
  static ThemeData get dark => _build(MeteredColors.night);

  // Transitional aliases for callers that still use the old names.
  static ThemeData get lightTheme => light;
  static ThemeData get darkTheme => dark;

  /// The retired Clear Air palette, re-tuned to the Metered card so screens
  /// that have not been rebuilt yet still live in the new world. Deleted with
  /// `AirColors` once every surface is Metered.
  static AirColors _bridge(MeteredColors m) {
    final raised = Color.lerp(m.card, m.ink, m.isNight ? 0.07 : 0.05)!;
    return AirColors(
      brightness: m.brightness,
      ground: m.cardDeep,
      surface: m.card,
      raised: raised,
      sunken: m.well,
      ink: m.ink,
      steel: m.inkSoft,
      mute: m.inkFaint,
      hairline: m.rule,
      hairlineStrong: m.ruleStrong,
      accent: m.value,
      accentInk: m.ink,
      accentWash: m.value.withValues(alpha: 0.14),
      connected: m.proven,
      connectedInk: m.valueOn,
      alert: m.blocked,
      alertInk: m.blockedLift,
      graphite: m.wheel,
      sun: m.value,
      shadow: m.cardDeep.withValues(alpha: 0.55),
      skyTop: m.card,
      skyHorizon: m.card,
      groundHorizon: m.cardDeep,
      groundBottom: m.cardDeep,
      haze: m.card.withValues(alpha: 0.0),
    );
  }

  static ThemeData _build(MeteredColors m) {
    final c = _bridge(m);
    final scheme = ColorScheme(
      brightness: m.brightness,
      primary: m.ink,
      onPrimary: m.card,
      secondary: m.value,
      onSecondary: m.valueOn,
      error: m.blocked,
      onError: m.paper,
      surface: m.card,
      onSurface: m.ink,
      surfaceContainerHighest: c.raised,
      outline: m.ruleStrong,
      outlineVariant: m.rule,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: m.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: m.cardDeep,
      dividerColor: m.rule,
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: m.rule,
      extensions: [m, c],
      textTheme: TextTheme(
        displayLarge: AppTextStyles.masthead(color: m.ink, size: 38),
        displayMedium: AppTextStyles.display(color: m.ink, size: 30),
        displaySmall: AppTextStyles.display(color: m.ink, size: 26),
        titleLarge: AppTextStyles.title(color: m.ink, size: 21),
        titleMedium: AppTextStyles.title(color: m.ink, size: 17),
        bodyLarge: AppTextStyles.body(color: m.ink, size: 16),
        bodyMedium: AppTextStyles.body(color: m.ink, size: 14),
        bodySmall: AppTextStyles.body(color: m.inkSoft, size: 13),
        labelLarge: AppTextStyles.body(
          color: m.ink,
          size: 14,
          weight: FontWeight.w600,
        ),
        labelSmall: AppTextStyles.label(color: m.inkFaint),
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: c.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: c.brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        titleTextStyle: AppTextStyles.title(color: c.ink, size: 19),
        iconTheme: IconThemeData(color: c.ink, size: 22),
      ),
      iconTheme: IconThemeData(color: c.steel, size: 22),
      dividerTheme: DividerThemeData(
        color: c.hairline,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        modalBarrierColor: c.ink.withValues(alpha: 0.28),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.hairline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: AppTextStyles.body(color: c.surface, size: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.raised,
        hintStyle: AppTextStyles.body(color: c.steel, size: 14),
        prefixIconColor: c.steel,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.accent, width: 1.4),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentInk,
          minimumSize: const Size(44, 44),
          textStyle: AppTextStyles.body(
            color: c.accentInk,
            size: 14,
            weight: FontWeight.w600,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.surface
              : c.steel,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.accent
              : c.sunken,
        ),
        trackOutlineColor: WidgetStateProperty.all(c.hairlineStrong),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
      listTileTheme: ListTileThemeData(
        iconColor: c.steel,
        textColor: c.ink,
        minVerticalPadding: 14,
      ),
    );
  }
}
