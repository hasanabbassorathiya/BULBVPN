import 'package:flutter/material.dart';

/// Clear Air palette. Day is the default world; Night Air is the same world
/// after dark, not a neon console. Text pairs here are asserted at WCAG AA in
/// `test/air_theme_test.dart`.
@immutable
class AirColors extends ThemeExtension<AirColors> {
  const AirColors({
    required this.brightness,
    required this.ground,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.ink,
    required this.steel,
    required this.mute,
    required this.hairline,
    required this.hairlineStrong,
    required this.accent,
    required this.accentInk,
    required this.accentWash,
    required this.connected,
    required this.connectedInk,
    required this.alert,
    required this.alertInk,
    required this.graphite,
    required this.sun,
    required this.shadow,
    required this.skyTop,
    required this.skyHorizon,
    required this.groundHorizon,
    required this.groundBottom,
    required this.haze,
  });

  final Brightness brightness;
  final Color ground;
  final Color surface;
  final Color raised;
  final Color sunken;
  final Color ink;
  final Color steel;
  final Color mute;
  final Color hairline;
  final Color hairlineStrong;
  final Color accent;
  final Color accentInk;
  final Color accentWash;
  final Color connected;
  final Color connectedInk;
  final Color alert;
  final Color alertInk;
  final Color graphite;
  final Color sun;
  final Color shadow;
  final Color skyTop;
  final Color skyHorizon;
  final Color groundHorizon;
  final Color groundBottom;
  final Color haze;

  static const day = AirColors(
    brightness: Brightness.light,
    ground: Color(0xFFE9F0EC),
    surface: Color(0xFFF7F4EC),
    raised: Color(0xFFFCFAF3),
    sunken: Color(0xFFE1E9E4),
    ink: Color(0xFF0E1B1D),
    steel: Color(0xFF5A6A67),
    mute: Color(0xFF5B6B67),
    hairline: Color(0x1A0E1B1D),
    hairlineStrong: Color(0x330E1B1D),
    accent: Color(0xFF0E7C86),
    accentInk: Color(0xFF0B656D),
    accentWash: Color(0xFFD8E9E8),
    connected: Color(0xFF2E8B6D),
    connectedInk: Color(0xFF246B55),
    alert: Color(0xFFC9553D),
    alertInk: Color(0xFF9E3B28),
    graphite: Color(0xFF8A9691),
    sun: Color(0xFFF3E3C4),
    shadow: Color(0x140E1B1D),
    skyTop: Color(0xFFDFEBE7),
    skyHorizon: Color(0xFFE9F0EC),
    groundHorizon: Color(0xFFE6EBE3),
    groundBottom: Color(0xFFF4F1E8),
    haze: Color(0xFFF7F4EC),
  );

  static const night = AirColors(
    brightness: Brightness.dark,
    ground: Color(0xFF0B1416),
    surface: Color(0xFF111D1F),
    raised: Color(0xFF162426),
    sunken: Color(0xFF091113),
    ink: Color(0xFFE9F0EC),
    steel: Color(0xFFA9B8B3),
    mute: Color(0xFF8FA09B),
    hairline: Color(0x1AFFFFFF),
    hairlineStrong: Color(0x33FFFFFF),
    accent: Color(0xFF4FB3BF),
    accentInk: Color(0xFF7BD1D9),
    accentWash: Color(0xFF143B3E),
    connected: Color(0xFF59C39A),
    connectedInk: Color(0xFF8ADBB9),
    alert: Color(0xFFE0715A),
    alertInk: Color(0xFFF0A08D),
    graphite: Color(0xFF6E7C78),
    sun: Color(0xFFE8D6AE),
    shadow: Color(0x66000000),
    skyTop: Color(0xFF0D1A1C),
    skyHorizon: Color(0xFF0B1416),
    groundHorizon: Color(0xFF0A1213),
    groundBottom: Color(0xFF0B1416),
    haze: Color(0xFF162426),
  );

  static AirColors of(BuildContext context) =>
      Theme.of(context).extension<AirColors>() ?? day;

  @override
  AirColors copyWith({Brightness? brightness}) => AirColors(
        brightness: brightness ?? this.brightness,
        ground: ground,
        surface: surface,
        raised: raised,
        sunken: sunken,
        ink: ink,
        steel: steel,
        mute: mute,
        hairline: hairline,
        hairlineStrong: hairlineStrong,
        accent: accent,
        accentInk: accentInk,
        accentWash: accentWash,
        connected: connected,
        connectedInk: connectedInk,
        alert: alert,
        alertInk: alertInk,
        graphite: graphite,
        sun: sun,
        shadow: shadow,
        skyTop: skyTop,
        skyHorizon: skyHorizon,
        groundHorizon: groundHorizon,
        groundBottom: groundBottom,
        haze: haze,
      );

  @override
  AirColors lerp(covariant AirColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AirColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      ground: c(ground, other.ground),
      surface: c(surface, other.surface),
      raised: c(raised, other.raised),
      sunken: c(sunken, other.sunken),
      ink: c(ink, other.ink),
      steel: c(steel, other.steel),
      mute: c(mute, other.mute),
      hairline: c(hairline, other.hairline),
      hairlineStrong: c(hairlineStrong, other.hairlineStrong),
      accent: c(accent, other.accent),
      accentInk: c(accentInk, other.accentInk),
      accentWash: c(accentWash, other.accentWash),
      connected: c(connected, other.connected),
      connectedInk: c(connectedInk, other.connectedInk),
      alert: c(alert, other.alert),
      alertInk: c(alertInk, other.alertInk),
      graphite: c(graphite, other.graphite),
      sun: c(sun, other.sun),
      shadow: c(shadow, other.shadow),
      skyTop: c(skyTop, other.skyTop),
      skyHorizon: c(skyHorizon, other.skyHorizon),
      groundHorizon: c(groundHorizon, other.groundHorizon),
      groundBottom: c(groundBottom, other.groundBottom),
      haze: c(haze, other.haze),
    );
  }
}

extension AirContext on BuildContext {
  AirColors get air => AirColors.of(this);
}
