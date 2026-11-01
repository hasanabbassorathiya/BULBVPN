import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'air_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  static const String fontFamily = AppTextStyles.sans;

  static ThemeData get light => _build(AirColors.day);
  static ThemeData get dark => _build(AirColors.night);

  // Transitional aliases for callers that still use the old names.
  static ThemeData get lightTheme => light;
  static ThemeData get darkTheme => dark;

  static ThemeData _build(AirColors c) {
    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.accentInk,
      onPrimary: c.surface,
      secondary: c.connectedInk,
      onSecondary: c.surface,
      error: c.alertInk,
      onError: c.surface,
      surface: c.surface,
      onSurface: c.ink,
      surfaceContainerHighest: c.raised,
      outline: c.hairlineStrong,
      outlineVariant: c.hairline,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.ground,
      dividerColor: c.hairline,
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: c.hairline,
      extensions: [c],
      textTheme: TextTheme(
        displayLarge: AppTextStyles.display(color: c.ink, size: 44),
        displayMedium: AppTextStyles.display(color: c.ink, size: 34),
        displaySmall: AppTextStyles.display(color: c.ink, size: 28),
        titleLarge: AppTextStyles.title(color: c.ink, size: 22),
        titleMedium: AppTextStyles.title(color: c.ink, size: 17),
        bodyLarge: AppTextStyles.body(color: c.ink, size: 16),
        bodyMedium: AppTextStyles.body(color: c.ink, size: 14),
        bodySmall: AppTextStyles.body(color: c.steel, size: 13),
        labelLarge: AppTextStyles.body(
          color: c.ink,
          size: 14,
          weight: FontWeight.w600,
        ),
        labelSmall: AppTextStyles.label(color: c.steel),
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
