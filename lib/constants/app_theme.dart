import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Spacing Scale ──────────────────────────────────────────────────────────
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

// ─── Border Radius ──────────────────────────────────────────────────────────
class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double pill = 50;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get xxlAll => BorderRadius.circular(xxl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

// ─── Typography ─────────────────────────────────────────────────────────────
class AppTypography {
  static TextStyle _base(BuildContext context) => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static TextStyle displayLarge(BuildContext context) => _base(context).copyWith(
    fontSize: 32, fontWeight: FontWeight.w800, height: 1.2,
    color: Theme.of(context).colorScheme.onSurface,
  );

  static TextStyle displayMedium(BuildContext context) => _base(context).copyWith(
    fontSize: 26, fontWeight: FontWeight.w800, height: 1.2,
    color: Theme.of(context).colorScheme.onSurface,
  );

  static TextStyle headlineMedium(BuildContext context) => _base(context).copyWith(
    fontSize: 20, fontWeight: FontWeight.w700, height: 1.3,
    color: Theme.of(context).colorScheme.onSurface,
  );

  static TextStyle titleLarge(BuildContext context) => _base(context).copyWith(
    fontSize: 16, fontWeight: FontWeight.w700, height: 1.3,
    color: Theme.of(context).colorScheme.onSurface,
  );

  static TextStyle titleMedium(BuildContext context) => _base(context).copyWith(
    fontSize: 15, fontWeight: FontWeight.w600, height: 1.4,
    color: Theme.of(context).colorScheme.onSurface,
  );

  static TextStyle bodyLarge(BuildContext context) => _base(context).copyWith(
    fontSize: 15, fontWeight: FontWeight.w500,
    color: Theme.of(context).colorScheme.onSurface,
  );

  static TextStyle bodyMedium(BuildContext context) => _base(context).copyWith(
    fontSize: 14, fontWeight: FontWeight.w500,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  static TextStyle bodySmall(BuildContext context) => _base(context).copyWith(
    fontSize: 13, fontWeight: FontWeight.w500,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  static TextStyle labelLarge(BuildContext context) => _base(context).copyWith(
    fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  static TextStyle labelMedium(BuildContext context) => _base(context).copyWith(
    fontSize: 12, fontWeight: FontWeight.w600,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  static TextStyle labelSmall(BuildContext context) => _base(context).copyWith(
    fontSize: 11, fontWeight: FontWeight.w500,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  static TextStyle statValue(BuildContext context) => _base(context).copyWith(
    fontSize: 28, fontWeight: FontWeight.w800, height: 1.0,
    color: Theme.of(context).colorScheme.primary,
  );

  static TextStyle mono(BuildContext context) => _base(context).copyWith(
    fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600,
    color: Theme.of(context).colorScheme.onSurface,
  );
}

// ─── Semantic Colors ────────────────────────────────────────────────────────
class AppColors {
  // Brand
  static const Color primary = Color(0xFF00E5C0);
  static const Color primaryDark = Color(0xFF00B89C);
  static const Color secondary = Color(0xFF9B59B6);
  static const Color accent = Color(0xFF6C63FF);

  // Status
  static const Color connected = Color(0xFF00E5C0);
  static const Color disconnected = Color(0xFFEF4444);
  static const Color warning = Color(0xFFFBBF24);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color success = Color(0xFF22C55E);

  // Dark theme surfaces
  static const Color bgDark = Color(0xFF0A0F1C);
  static const Color bgSurface = Color(0xFF111827);
  static const Color bgCard = Color(0xFF1A2332);
  static const Color bgCardLight = Color(0xFF1F2D3D);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Light theme surfaces
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFF1F5F9);
  static const Color lightCardBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);

  // Dark gradients
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F172A), Color(0xFF0A0F1C)],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6C63FF), Color(0xFF00E5C0)],
  );

  static const LinearGradient connectedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00E5C0), Color(0xFF00B89C)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A2332), Color(0xFF111827)],
  );

  // Light gradients
  static const LinearGradient lightBgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
  );

  static const LinearGradient lightCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
  );

  // Ping colors
  static Color pingColor(int ping) {
    if (ping < 30) return connected;
    if (ping < 80) return primary;
    if (ping < 150) return warning;
    return error;
  }
}

// ─── Theme Extension for Semantic Colors ────────────────────────────────────
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color background;
  final Color surface;
  final Color card;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final LinearGradient bgGradient;
  final LinearGradient cardGradient;

  const AppSemanticColors({
    required this.background,
    required this.surface,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.bgGradient,
    required this.cardGradient,
  });

  static const dark = AppSemanticColors(
    background: AppColors.bgDark,
    surface: AppColors.bgSurface,
    card: AppColors.bgCard,
    cardBorder: AppColors.bgCardLight,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    bgGradient: AppColors.bgGradient,
    cardGradient: AppColors.cardGradient,
  );

  static const light = AppSemanticColors(
    background: AppColors.lightBg,
    surface: AppColors.lightSurface,
    card: AppColors.lightCard,
    cardBorder: AppColors.lightCardBorder,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textMuted: AppColors.lightTextMuted,
    bgGradient: AppColors.lightBgGradient,
    cardGradient: AppColors.lightCardGradient,
  );

  @override
  AppSemanticColors copyWith({
    Color? background,
    Color? surface,
    Color? card,
    Color? cardBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    LinearGradient? bgGradient,
    LinearGradient? cardGradient,
  }) {
    return AppSemanticColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      bgGradient: bgGradient ?? this.bgGradient,
      cardGradient: cardGradient ?? this.cardGradient,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      bgGradient: LinearGradient.lerp(bgGradient, other.bgGradient, t)!,
      cardGradient: LinearGradient.lerp(cardGradient, other.cardGradient, t)!,
    );
  }

  static AppSemanticColors of(BuildContext context) {
    return Theme.of(context).extension<AppSemanticColors>() ?? dark;
  }
}

// ─── Theme Builder ──────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.bgDark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.bgSurface,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        error: AppColors.disconnected,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
        ),
      ),
      extensions: const [AppSemanticColors.dark],
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.lightBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightTextPrimary,
        onSurfaceVariant: AppColors.lightTextSecondary,
        error: AppColors.disconnected,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      cardTheme: CardThemeData(
        color: AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.lightTextPrimary,
        ),
      ),
      extensions: const [AppSemanticColors.light],
    );
  }
}
