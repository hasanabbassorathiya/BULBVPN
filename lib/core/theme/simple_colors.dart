import 'package:flutter/material.dart';

/// Simple VPN theme: dark mode only, OLED-safe.
///
/// Navy primary (#1E3A5F), connected green accent (#22C55E),
/// near-black background (#0F172A), white foreground. No day/night split —
/// the app is dark everywhere, which matches a VPN that runs in the background
/// and only surfaces when it has something to say.
@immutable
class SimpleColors extends ThemeExtension<SimpleColors> {
  const SimpleColors({
    required this.brightness,
    required this.primary,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.hairline,
    required this.connected,
    required this.connectedInk,
    required this.error,
    required this.errorInk,
  });

  final Brightness brightness;

  /// Navy primary brand color.
  final Color primary;

  /// OLED-safe background: near-black.
  final Color background;

  /// Slightly lighter surface for cards and sheets.
  final Color surface;

  /// Secondary surface for subtle grouping.
  final Color surfaceVariant;

  /// White foreground for high-contrast text.
  final Color ink;

  /// Secondary print, pulled toward the background.
  final Color inkSoft;

  /// Tertiary print: small text that is present but not urgent.
  final Color inkFaint;

  /// Subtle hairline for dividers and borders.
  final Color hairline;

  /// Connected green — the one accent that means "bytes are crossing".
  final Color connected;

  /// Text printed on the connected green.
  final Color connectedInk;

  /// Error red for failed states.
  final Color error;

  /// Text printed on the error red.
  final Color errorInk;

  static const dark = SimpleColors(
    brightness: Brightness.dark,
    primary: Color(0xFF1E3A5F),
    background: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    surfaceVariant: Color(0xFF334155),
    ink: Color(0xFFFFFFFF),
    inkSoft: Color(0xFFCBD5E1),
    inkFaint: Color(0xFF64748B),
    hairline: Color(0x33FFFFFF),
    connected: Color(0xFF22C55E),
    connectedInk: Color(0xFF065F46),
    error: Color(0xFFEF4444),
    errorInk: Color(0xFFFEE2E2),
  );

  bool get isDark => brightness == Brightness.dark;

  @override
  SimpleColors copyWith({
    Brightness? brightness,
    Color? primary,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? hairline,
    Color? connected,
    Color? connectedInk,
    Color? error,
    Color? errorInk,
  }) {
    return SimpleColors(
      brightness: brightness ?? this.brightness,
      primary: primary ?? this.primary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkFaint: inkFaint ?? this.inkFaint,
      hairline: hairline ?? this.hairline,
      connected: connected ?? this.connected,
      connectedInk: connectedInk ?? this.connectedInk,
      error: error ?? this.error,
      errorInk: errorInk ?? this.errorInk,
    );
  }

  @override
  SimpleColors lerp(covariant SimpleColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return SimpleColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      primary: c(primary, other.primary),
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceVariant: c(surfaceVariant, other.surfaceVariant),
      ink: c(ink, other.ink),
      inkSoft: c(inkSoft, other.inkSoft),
      inkFaint: c(inkFaint, other.inkFaint),
      hairline: c(hairline, other.hairline),
      connected: c(connected, other.connected),
      connectedInk: c(connectedInk, other.connectedInk),
      error: c(error, other.error),
      errorInk: c(errorInk, other.errorInk),
    );
  }
}

extension SimpleOnContext on BuildContext {
  SimpleColors get simple =>
      Theme.of(this).extension<SimpleColors>() ?? SimpleColors.dark;
}
