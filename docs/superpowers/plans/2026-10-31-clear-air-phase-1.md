# BULBVPN Clear Air — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the retired Filament UI with the Clear Air app shell — light-first with Night Air dark — on every shipping screen, while the existing SoftEther/OpenVPN engine and all connection logic stay untouched.

**Architecture:** A `ThemeExtension` (`AirColors`) carries the day/night palette; a small set of Clear Air primitives (`HorizonField`, `ApertureControl`, `DataShelf`, `TrustBadge`, `AirSheet`, `AirButton`) compose every screen. `MainScreen` keeps its controller, lifecycle, session, IP, ads, and server wiring; only its visual tree is replaced by a testable `HomeComposition`. The engine is mapped to honest labels; no new protocol work happens in Phase 1.

**Tech Stack:** Flutter 3.47.7, Dart 3, Riverpod, go_router, ScreenUtil, flutter_svg. One new asset family: Schibsted Grotesk (OFL). No new packages.

**Spec:** `docs/superpowers/specs/2026-10-31-greatest-vpn-upgrade-design.md` (§8 and Phase 1).
**Direction contract:** `docs/design/clear-air-direction.md` (registered as the surface brief).

## Global Constraints

- **No git commits.** The user has not authorized commits. Stage nothing. End every task with `git diff --stat` and a verification run, not a commit.
- **Do not change engine behavior.** `vpn_controller.dart`, `softether_vpn.dart`, `vpn_service.dart`, native code, relay probing, port agility, relay memory, split tunneling, kill switch, and session persistence keep their logic. The only provider change allowed is read-only statistics (`totalUpload`, `protocol`) and it must not alter state transitions.
- **Honest labels only.** `Connected` appears only while `ConnectionStatus.connected`. Unknown numbers render `—`. Community/bootstrap relays always carry a visible "not private" label. No invented speed, server count, or "military-grade" claims.
- **Night Air and Clear Air both ship.** `themeMode: ThemeMode.system`; no dark-only hardcoding. New UI reads colors from `context.air`.
- **Remove the hard text-scale lock.** Delete `textScaler: TextScaler.linear(1.0)` from `app.dart`. All layouts must survive `textScaler 1.3`.
- **Accessibility floor.** 44×44 pt minimum targets, WCAG AA text contrast in both modes, state never carried by color alone (label + icon), reduced-motion honored, RTL-safe alignment (use `AlignmentDirectional`/`EdgeInsetsDirectional`, not hardcoded left/right).
- **No old-world assets or motifs.** No Filament amber, no dark-neon gradients, no centered orb, no rings/orbits, no glassmorphism, no emoji flags, no old onboarding screenshots.
- **Typography.** Schibsted Grotesk for words, Geist Mono for every number/reading. No Inter, no serif, no system display fallback.
- **Layout ceiling.** Phone content max width 560; settings/paywall 720; test 360×640, 390×844, 430×932, 768×1024, 1024×1366.
- **Verification per task:** `flutter analyze` clean for touched files and `flutter test` green before the task is called done.

---

## File Structure

**Create**
- `assets/fonts/SchibstedGrotesk-VF.ttf` — display/body face (OFL)
- `assets/fonts/OFL-SchibstedGrotesk.txt` — license text
- `lib/core/theme/air_colors.dart` — day/night palette + `ThemeExtension`
- `lib/modules/core/trust_tier.dart` — trust-tier enum and labels
- `lib/shared/air/horizon_field.dart` — full-bleed atmospheric background
- `lib/shared/air/aperture_control.dart` — the 96 px connect control
- `lib/shared/air/data_shelf.dart` — three-figure metric shelf
- `lib/shared/air/trust_badge.dart`
- `lib/shared/air/air_sheet.dart` — sheet scaffold + `showAirSheet`
- `lib/shared/air/air_buttons.dart`
- `lib/modules/main/presentation/widgets/home_composition.dart`
- `test/air_theme_test.dart`, `test/aperture_test.dart`, `test/home_composition_test.dart`, `test/trust_tier_test.dart`

**Rewrite**
- `lib/core/theme/app_colors.dart` (transitional bridge → deleted in Task 9)
- `lib/core/theme/app_text_styles.dart`, `lib/core/theme/app_theme.dart`
- `lib/app/app.dart`
- `lib/modules/main/presentation/screens/main_screen.dart`
- `lib/modules/main/presentation/widgets/server_sheet.dart`
- `lib/shared/layout/navbar/defyx_navbar.dart` and its quick-menu widgets
- `lib/modules/splash/presentation/splash_screen.dart`
- `lib/modules/onboarding/onboarding_screen.dart`
- `lib/modules/speed_test/presentation/**` (visual layer only)
- `lib/modules/settings/presentation/**`
- `lib/modules/legal/legal_screen.dart`
- `lib/modules/monetization/paywall_screen.dart`, `ad_banner.dart`
- `lib/shared/widgets/defyx_switch.dart`
- `lib/shared/providers/connection_state_provider.dart` (stats/protocol only)

**Delete**
- `lib/modules/main/presentation/widgets/bulb_orb.dart`
- `lib/shared/layout/main_screen_background.dart` (superseded by `HorizonField`)
- `lib/modules/speed_test/presentation/widgets/speed_test_progress/painters/semicircular_progress_painter.dart`
- `lib/modules/speed_test/presentation/widgets/speed_test_progress/painters/animated_grid_painter.dart`
- Any navbar widget proven unused after Task 5.

---

### Task 1: Foundation — font, palette, typography, theme

**Files:**
- Create: `assets/fonts/SchibstedGrotesk-VF.ttf`, `assets/fonts/OFL-SchibstedGrotesk.txt`
- Create: `lib/core/theme/air_colors.dart`
- Modify: `pubspec.yaml`, `lib/core/theme/app_colors.dart`, `lib/core/theme/app_text_styles.dart`, `lib/core/theme/app_theme.dart`, `lib/app/app.dart`
- Test: `test/air_theme_test.dart`

**Interfaces:**
- Produces: `AirColors`, `AirColors.day`, `AirColors.night`, `AirColors.of(BuildContext)`, `context.air`; `AppTextStyles`; `AppTheme.light`, `AppTheme.dark`.

- [ ] **Step 1: Download the face and its license**

```bash
curl -L --fail -o assets/fonts/SchibstedGrotesk-VF.ttf \
  'https://raw.githubusercontent.com/google/fonts/main/ofl/schibstedgrotesk/SchibstedGrotesk%5Bwght%5D.ttf'
curl -L --fail -o assets/fonts/OFL-SchibstedGrotesk.txt \
  'https://raw.githubusercontent.com/google/fonts/main/ofl/schibstedgrotesk/OFL.txt'
file assets/fonts/SchibstedGrotesk-VF.ttf   # expect TrueType font data
wc -c assets/fonts/SchibstedGrotesk-VF.ttf  # expect ~176068 bytes
```

- [ ] **Step 2: Register the family**

In `pubspec.yaml`, replace the `Outfit` family block with:

```yaml
  fonts:
    - family: SchibstedGrotesk
      fonts:
        - asset: assets/fonts/SchibstedGrotesk-VF.ttf
    - family: GeistMono
      fonts:
        - asset: assets/fonts/GeistMono-VF.ttf
```

Keep `assets/fonts/` in the asset list. Do not delete `Outfit-VF.ttf` yet; it is removed after no `Outfit` references remain.

- [ ] **Step 3: Write the failing contrast test**

`test/air_theme_test.dart`:

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bulbvpn/core/theme/air_colors.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void expectAA(AirColors c, Color fg, Color bg, {String? why}) {
  expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: why);
}

void main() {
  test('Clear Air and Night Air text pairs meet WCAG AA', () {
    for (final c in [AirColors.day, AirColors.night]) {
      expectAA(c, c.ink, c.ground, why: 'ink on ground');
      expectAA(c, c.ink, c.surface, why: 'ink on surface');
      expectAA(c, c.steel, c.ground, why: 'steel on ground');
      expectAA(c, c.steel, c.surface, why: 'steel on surface');
      expectAA(c, c.accentInk, c.ground, why: 'accent text on ground');
      expectAA(c, c.connectedInk, c.surface, why: 'connected text on surface');
      expectAA(c, c.alertInk, c.ground, why: 'alert text on ground');
      expectAA(c, c.accentInk, c.accentWash, why: 'selected row');
      expectAA(c, c.alertInk, c.accentWash, why: 'warning on wash');
    }
  });
}
```

- [ ] **Step 4: Run it — expect failure**

Run: `flutter test test/air_theme_test.dart`
Expected: FAIL, `air_colors.dart` not found.

- [ ] **Step 5: Implement `AirColors`**

`lib/core/theme/air_colors.dart`:

```dart
import 'package:flutter/material.dart';

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
  final Color ground, surface, raised, sunken;
  final Color ink, steel, mute;
  final Color hairline, hairlineStrong;
  final Color accent, accentInk, accentWash;
  final Color connected, connectedInk;
  final Color alert, alertInk;
  final Color graphite, sun, shadow;
  final Color skyTop, skyHorizon, groundHorizon, groundBottom, haze;

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
  AirColors copyWith({Brightness? brightness, Color? ground, Color? ink}) =>
      this;

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
```

- [ ] **Step 6: Turn `AppColors` into a transitional day-palette bridge**

Replace `lib/core/theme/app_colors.dart` with constants that keep every existing reference compiling while the immediate value becomes Clear Air day. Delete the old gradient names only after Task 9.

```dart
import 'package:flutter/material.dart';
import 'air_colors.dart';

// Transitional bridge: existing widgets compile against day values while they
// are migrated to `context.air`. Deleted when the last reference is gone.
class AppColors {
  static const Color canvas = AirColors.day.ground;
  static const Color surface = AirColors.day.surface;
  static const Color raised = AirColors.day.raised;
  static const Color ink = AirColors.day.ink;
  static const Color steel = AirColors.day.steel;
  static const Color mute = AirColors.day.mute;
  static const Color hairline = AirColors.day.hairline;
  static const Color shadow = AirColors.day.shadow;
  static const Color amber = AirColors.day.accentInk;
  static const Color amberTint = AirColors.day.accentWash;
  static const Color emerald = AirColors.day.connectedInk;
  static const Color red = AirColors.day.alertInk;
  static const Color graphite = AirColors.day.graphite;
  static const Color sky = AirColors.day.accent;

  static const Color primary = amber;
  static const Color secondary = steel;
  static const Color background = canvas;
  static const Color downloadColor = emerald;
  static const Color uploadColor = sky;
  static const Color warningColor = amber;

  static const Color topGradient = canvas;
  static const Color topGradientReadyToConnect = canvas;
  static const Color topGradientConnecting = canvas;
  static const Color middleGradient = AirColors.day.skyHorizon;
  static const Color bottomGradient = AirColors.day.groundBottom;
  static const Color middleGradientConnected = AirColors.day.skyHorizon;
  static const Color bottomGradientConnected = AirColors.day.groundBottom;
  static const Color middleGradientNoInternet = AirColors.day.groundHorizon;
  static const Color bottomGradientNoInternet = AirColors.day.groundBottom;
  static const Color middleGradientFailedToConnect = AirColors.day.groundHorizon;
  static const Color bottomGradientFailedToConnect = AirColors.day.groundBottom;
  static const Color middleGradientConnecting = AirColors.day.skyHorizon;
  static const Color bottomGradientConnecting = AirColors.day.groundBottom;

  static const Color liveEmerald = emerald;
  static const Color skySeries = sky;
}
```

- [ ] **Step 7: Rewrite typography**

`lib/core/theme/app_text_styles.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Clear Air type: Schibsted Grotesk speaks, Geist Mono measures.
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
  }) =>
      TextStyle(
        fontFamily: sans,
        fontSize: size.sp,
        height: 1.42,
        fontWeight: weight,
        color: color,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
      );

  static TextStyle label({required Color color, double size = 10.5}) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size.sp,
        height: 1.2,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
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
}
```

Every caller must now pass `color`. Fix compile errors mechanically by passing the closest semantic color (`context.air.ink/steel/alertInk/connectedInk`) in migrated files; for files not yet migrated use `AppColors.*` until their task.

- [ ] **Step 8: Rewrite the theme**

`lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'air_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  static ThemeData get light => _build(AirColors.day);
  static ThemeData get dark => _build(AirColors.night);

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
        titleLarge: AppTextStyles.title(color: c.ink, size: 22),
        titleMedium: AppTextStyles.title(color: c.ink, size: 17),
        bodyLarge: AppTextStyles.body(color: c.ink, size: 16),
        bodyMedium: AppTextStyles.body(color: c.ink, size: 14),
        labelLarge: AppTextStyles.body(color: c.ink, size: 14, weight: FontWeight.w600),
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
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        modalBarrierColor: c.ink.withValues(alpha: 0.28),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          (s) => s.contains(WidgetState.selected) ? c.surface : c.steel,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.sunken,
        ),
        trackOutlineColor: WidgetStateProperty.all(c.hairlineStrong),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    );
  }
}
```

Keep a `themeData` alias if any caller still uses it; delete after Task 9.

- [ ] **Step 9: Wire the app**

In `lib/app/app.dart`:

```dart
theme: AppTheme.light,
darkTheme: AppTheme.dark,
themeMode: ThemeMode.system,
```

and change `_appBuilder` to pass the child through unchanged (delete the `MediaQuery.copyWith(textScaler:)` override).

- [ ] **Step 10: Run the tests**

Run: `flutter test test/air_theme_test.dart && flutter analyze`
Expected: PASS; analyze may still report `AppTextStyles` call-site errors from the signature change. Fix each by passing an explicit color. Do not weaken the contrast values to make a test pass.

---

### Task 2: Clear Air primitives

**Files:**
- Create: `lib/shared/air/horizon_field.dart`, `aperture_control.dart`, `data_shelf.dart`, `trust_badge.dart`, `air_sheet.dart`, `air_buttons.dart`
- Create: `lib/modules/core/trust_tier.dart` (needed by `TrustBadge`)
- Delete: `lib/shared/layout/main_screen_background.dart`
- Modify: imports in `main_screen.dart`, `settings_screen.dart`, `speed_test_screen.dart`, `legal_screen.dart`
- Test: `test/aperture_test.dart`, `test/trust_tier_test.dart`

**Interfaces:**
- Produces: `enum AirPhase { idle, preparing, connecting, verifying, connected, closing, failed, offline }`
- Produces: `HorizonField({required AirPhase phase, required Widget child, double horizonFraction = 0.38})`
- Produces: `ApertureControl({required AirPhase phase, required VoidCallback onTap, double size = 96, String? caption})`
- Produces: `class ShelfMetric { final String label, value, unit; final Color color; }`, `DataShelf({required List<ShelfMetric> metrics, required Widget meta})`
- Produces: `TrustBadge({required TrustTier tier, bool compact = false})`
- Produces: `showAirSheet(BuildContext, {required String title, String? subtitle, required Widget child})`, `AirSheetHeader`, `AirButton.primary/secondary`

- [ ] **Step 1: Write `trust_tier.dart` + test**

```dart
enum TrustTier { owned, byos, community, bootstrap }

extension TrustTierX on TrustTier {
  bool get isPrivate => this == TrustTier.owned || this == TrustTier.byos;
  String get name => switch (this) {
        TrustTier.owned => 'Owned relay',
        TrustTier.byos => 'Your server',
        TrustTier.community => 'Community relay',
        TrustTier.bootstrap => 'Bootstrap relay',
      };
  String get short => switch (this) {
        TrustTier.owned => 'OWNED',
        TrustTier.byos => 'YOURS',
        TrustTier.community => 'COMMUNITY',
        TrustTier.bootstrap => 'BOOTSTRAP',
      };
  String get disclosure => isPrivate ? name : '$name — not private';
}
```

Test: owned/byos `isPrivate` true, community/bootstrap false, every `disclosure` for non-private ends with `not private`.

- [ ] **Step 2: Implement `ApertureControl`**

Behavioral contract:
- 96 px circle; minimum hit area 120×120; `Semantics(button: true, label: phase == connected ? 'Disconnect' : 'Connect', value: phase word)`; `HapticFeedback.lightImpact()` on tap down.
- Circle face is `context.air.surface`, 1 px `hairlineStrong`, soft cast shadow (`Offset(0, 6)`, blur 18, `air.shadow`).
- Iris opening animates with `smoothTowards` at rate 4:
  `idle 0.30, preparing 0.38, connecting 0.56, verifying 0.76, connected 1.0, closing 0.20, failed 0.14, offline 0.14`.
- Six 1.2 px blade lines from the rim toward the iris, `ink` at 12% opacity; no rings.
- `connected`: opening filled with a vertical `skyTop → accentWash` gradient; a 12 px `sun` disc sits 8 px above center; three 1 px horizontal flow lines drift at 6 px/s, `accentInk` at 18%; no rotation.
- `connecting`/`verifying`: one 1.6 px `accent` arc sweeps 1.6 rad per 1.25 s.
- `failed`/`offline`: opening nearly closed; a 1.6 px `alertInk` rim and a 14 px horizontal bar through the center.
- Caption 10.5 px mono `steel` 10 px below the circle; copy passed by the caller.
- Press feedback: scale to 0.97 (140 ms out, spring back).
- Reduced motion (`MediaQuery.disableAnimationsOf(context)`): do not repeat the ticker; jump to the target opening; no sweep/flow; sun static. `pumpAndSettle` must settle.
- Dispose both controllers.

Test with a `StatefulBuilder` toggling `phase` and a tap-counter; assert:
1. Semantics label flips with phase.
2. Tap fires callback exactly once.
3. With `MediaQuery(data: copyWith(disableAnimations: true))`, `pumpAndSettle` completes for every phase.
4. At 96 px and textScaler 1.3 no exception.

- [ ] **Step 3: Implement `HorizonField`**

Behavioral contract:
- Full-bleed `Scaffold(extendBody: true, backgroundColor: air.ground)`; system overlay style from brightness.
- Sky gradient `skyTop → skyHorizon` down to `horizonFraction`; ground gradient `groundHorizon → groundBottom` below; 1 px horizon line `ink` at 12% (day) / white 10% (night).
- Sun: 44 px disc at `x = 0.72w`, on the horizon when `connected` (center 28 px above the line); rises 8 px over 500 ms; breathing opacity 0.88–1.0 over 3 s. Hidden otherwise.
- Haze: four soft horizontal bands between 8% and 34% height using `haze` at 5–8%; during `preparing/connecting/verifying`, the bands drift 6 px horizontally over 9 s (transform only).
- Clearing: on entering `connected`, a radial mask centered at `(0.30w, horizonY)` grows its clear radius from 0 to `1.2 × diagonal` over 700 ms, removing haze outward. On leaving, haze returns over 500 ms. Reduced motion: cross-fade haze only.
- Repaint via one `AnimationController` (only while animating; stop when settled and when reduced motion).
- `shouldRepaint` compares phase, clear progress, drift.
- The child sits above all paint.

- [ ] **Step 4: Implement `DataShelf`**

- Top 1 px `hairline`, 14 px top padding.
- Row of three `Expanded` columns: label (mono 10.5, `steel`), 6 px, value (mono 26, `ink`; `steel` when value is `—`), 4 px, unit (mono 10, `steel`, omitted when empty).
- 20 px gap between figures; no cards, no dividers.
- Meta row 12 px below: caller-supplied widget (protocol + trust).
- No overflow at 360 px with textScaler 1.3.

- [ ] **Step 5: Implement `TrustBadge`**

- 24 px high, 8 px horizontal padding, radius 6, no left border.
- Private: `accentInk` text on `accentWash`.
- Non-private: `alertInk` text on `alert` at 12%; text `NOT PRIVATE` (compact) or `${tier.short} · NOT PRIVATE`.
- Mono 9.5, tracking 0.6.
- `Semantics(label: tier.disclosure)`.

- [ ] **Step 6: Implement `air_sheet.dart` + `air_buttons.dart`**

`showAirSheet` mirrors `showServerSheet`: `isScrollControlled`, `useSafeArea`, `backgroundColor: air.surface`, top radius 24, `FractionallySizedBox` height factor passed in (default 0.86), max width 640, grabber 36×4 `hairlineStrong`, title `titleLarge`, optional subtitle `body 13 steel`, close 44×44. Buttons: 50 px high, radius 12; primary is `ink` fill with `surface` text; secondary is hairline border with `ink` text; both use 15 w600 sans.

- [ ] **Step 7: Swap the background everywhere**

Replace `MainScreenBackground(connectionStatus: status, child: …)` with `HorizonField(phase:…, child: …)`:
- `main_screen.dart` maps status via `airPhaseFor(status)`.
- `settings_screen.dart`, `speed_test_screen.dart`, `legal_screen.dart` use `AirPhase.idle`.
Delete `main_screen_background.dart`. Run `flutter analyze`; expected clean.

---

### Task 3: Home / connect composition

**Files:**
- Create: `lib/modules/main/presentation/widgets/home_composition.dart`
- Modify: `lib/modules/main/presentation/screens/main_screen.dart`, `lib/shared/providers/connection_state_provider.dart`
- Delete: `lib/modules/main/presentation/widgets/bulb_orb.dart`
- Test: `test/home_composition_test.dart`

**Interfaces:**
- Produces: `HomeComposition({required HomeViewState state, required VoidCallback onConnect, required VoidCallback onOpenServers, required VoidCallback onRefreshIps, required VoidCallback onCopyIp, Widget? sponsored})`
- `HomeViewState` fields: `AirPhase phase`, `String statusTitle`, `String statusDetail`, `String networkLabel`, `String clockLabel`, `String pingLabel`, `String downLabel`, `String upLabel`, `String protocolLabel`, `String relayLabel`, `String exitIp`, `String exitLocation`, `TrustTier? trustTier`, `bool live`, `bool measuring`, `bool tight`.
- Consumes: `HorizonField`, `ApertureControl`, `DataShelf`, `TrustBadge`.

- [ ] **Step 1: Add honest read-only stats to `ConnectionState`**

Add `enum TunnelProtocol { none, softEther, openVpn }` with `String get label => switch (this) { none => 'Automatic', softEther => 'SoftEther', openVpn => 'OpenVPN' }`. Add fields `int totalUpload` (default 0), `bool hasUpload` (default false), `TunnelProtocol protocol` (default none), plus copyWith support.

Stats timer:
- When `_holdEngineEvents` (SoftEther): set `totalDownload` from `SoftEtherVpn.bytesReceived()` and `hasUpload: false`.
- Otherwise: `await _vpnService.refreshTunnelStatistics()` once, then read both `totalDownload` and `totalUpload`, set `hasUpload: true`.
- Never change status transitions. Terminal `_setStatus` resets both totals and `hasUpload: false`.
- Set `protocol: TunnelProtocol.softEther` when `holdEngineEvents(true)`; set `TunnelProtocol.openVpn` when a connected event arrives while `_holdEngineEvents == false`; set `none` on terminal states.

- [ ] **Step 2: Build `HomeComposition`**

Composition (phone):
```
HorizonField(phase)
  Stack
    Positioned(left: contentX + w*0.30 - 48, top: horizonY - 48)
      ApertureControl(phase, caption)
    SafeArea
      Center
        ConstrainedBox(maxWidth: 560)
          Padding(horizontal 22, top 8)
            Column
              _TopRail: networkLabel (mono 10.5 steel) + clockLabel (mono 10.5 ink; session when live)
              SizedBox(10)
              _StatusBlock: statusTitle (display 34, status color) + icon 16 + statusDetail (mono 11 steel)
              Spacer
              DataShelf(metrics: ping/down/up, meta: protocol + TrustBadge)
              SizedBox(10)
              _ExitRow: exit IP (mono 12 ink) + location (11 steel) + refresh 44×44 + copy
              SizedBox(10)
              sponsored (ad banner) if present
              SizedBox(8)
              _DestinationRow: flag 18×12 + "relayLabel · protocolLabel" + TrustBadge + chevron (48 high, opens servers)
              SizedBox(96) // nav clearance
```
- Status color: idle `ink`; preparing/connecting/verifying `accentInk`; connected `connectedInk`; closing `steel`; failed/offline `alertInk`.
- Status icon mapping: idle `Icons.horizontal_rule`, preparing `Icons.more_horiz`, connecting `Icons.arrow_outward`, verifying `Icons.visibility_outlined`, connected `Icons.check`, closing `Icons.close`, failed `Icons.priority_high`, offline `Icons.cloud_off_outlined`; always accompanied by the words.
- Aperture caption: `Tap to connect` / `Tap to disconnect` / stage verb / `Tap to retry`.
- Tight mode (`height < 740` or unbounded): `SingleChildScrollView`; horizon band fixed 250 px with aperture at `left: w*0.30`, top 80; data shelf follows; no `Expanded` in unbounded height.
- Exit row only when `exitIp` is non-empty; otherwise `Exit · measuring` with refresh.
- Never render `BEFORE` as exit.

- [ ] **Step 3: Rewire `MainScreen`**

- Replace `_bulbPhase` with `airPhaseFor(ConnectionStatus)`.
- Keep every listener, `_restoreLiveTunnel`, `_onNetworkChanged`, `_applyServerConfig`, `_connectIfLaunchRequested`, IP refresh/copy, logs sheet, ads gating.
- Add `_upRateLabel` and `_prevByteUp`, mirroring download; `upLabel = cs.hasUpload ? _upRateLabel : '—'`.
- `clockLabel`: when live, session `HH:MM:SS`; otherwise local `HH:mm` updated by the 1 s timer.
- `networkLabel` from `networkFingerprintProvider`: `wifi:` → `Wi-Fi`, `cell:` → `Mobile`, `eth:` → `Ethernet`, `offline` → `Offline`, else `Network`; append the trailing IP prefix for Wi-Fi (`Wi-Fi · 192.168.1`).
- `pingLabel`: measured ping of the connected/selected/fastest relay; else `—`.
- `protocolLabel`: `cs.protocol.label` when live, else `Automatic`.
- `relayLabel`: connected relay name when live; selected/fastest country otherwise; `Auto` while finding.
- `trustTier`: tier of the selected/fastest server; for a connected relay matched by IP to the catalog; otherwise null (show `Path verified` instead of a tier when live).
- Status copy (exact):
  - disconnected: `Standby` / `path closed · {endpoint}`
  - loading: `Preparing` / `waking the engine`
  - connecting: `Connecting` / `opening tunnel · {endpoint}`
  - analyzing: `Verifying` / `checking the first byte`
  - connected: `Connected` / `traffic confirmed · {endpoint}`
  - disconnecting: `Closing` / `closing the tunnel`
  - error: `Blocked` / `no working path on this network`
  - noInternet: `No internet` / `this network is offline`
- `error`/`noInternet` status word is `Blocked`/`No internet`; the old `Connection failed` string is retired.

- [ ] **Step 4: Delete `bulb_orb.dart`** after confirming no imports remain.

- [ ] **Step 5: Test `HomeComposition` directly**

Pump at 390×844 and 360×640 with `textScaler 1.3` and with `disableAnimations: true`; assert:
1. `Standby` and the aperture semantics exist when idle.
2. `Connected` + `traffic confirmed` + `NOT PRIVATE` render when live (bootstrap tier).
3. No overflow/exception in either size.
4. In RTL (`Directionality(textDirection: TextDirection.rtl)`), no overflow and the status block still starts at the right edge.

---

### Task 4: Server sheet with trust tiers

**Files:**
- Modify: `lib/modules/core/vpn_server.dart` (add `trustTier`, default `TrustTier.bootstrap`), `lib/modules/main/presentation/widgets/server_sheet.dart`
- Test: `test/server_sheet_test.dart` (update expected copy; add tier assertions)

- [ ] **Step 1: Add the tier field**

```dart
import 'trust_tier.dart';
// inside VpnServer
final TrustTier trustTier;
// constructor
this.trustTier = TrustTier.bootstrap,
```

Every existing constructor call keeps compiling.

- [ ] **Step 2: Rebuild the sheet**

- Use `showAirSheet`-style container; search field 44 high, `raised` fill, magnifier `steel`; header `Relays`, subtitle `N relays · M countries · lowest ping first`.
- Persistent notice under the header, 13 px sans `steel`: `Bootstrap relays are community-contributed. They are not private and may see your traffic.` with a `TrustBadge(compact: true)`.
- Section `Fastest now` (top 3 by measured ping, only when pings exist and not probing): row = country code mono 11 `steel` at 48 px wide, city `body 15 ink`, latency mono 13 `connectedInk`, tier badge.
- Section `Bootstrap` — current country grouping; each row: country code mono 11 `steel` (48 px), city + host-less label, latency mono 12 (`—` when timeout), tier badge on the group header only.
- Selected row: `accentWash` background + 2 px `accent` left hairline (use `BorderDirectional` for RTL).
- Pull-to-refresh (`RefreshIndicator`) re-probes; keep `ensureFresh`.
- Empty: `No relays measured yet` + `Pull to refresh`; error: `Catalog unavailable` + retry.
- Preserve `_countryCount`, grouping, sorting, search, and the selected-server behavior.

- [ ] **Step 3: Update tests** — keep the `4 relays · 3 countries · lowest ping first` assertion; add `expect(find.textContaining('not private'), findsWidgets)`.

---

### Task 5: Navigation and quick menu

**Files:**
- Rewrite: `lib/shared/layout/navbar/defyx_navbar.dart`
- Rewrite: `lib/shared/layout/navbar/widgets/quick_menu_dialog.dart`, `quick_menu_item.dart`, `introduction_dialog.dart`, `custom_webview_screen.dart`, `copyable_link.dart`
- Delete if unused: `defyx_nav_item.dart`, `widgets/defyx_nav_item.dart`
- Add share access in `settings_screen.dart` (Task 8) if the navbar no longer hosts it.

- [ ] **Step 1: Restyle the bar**

- Full-width `SafeArea` bottom bar, not a pill: `surface` background, 1 px top `hairline`, no shadow; 64 high.
- Three destinations: `Connect` (`Icons.horizontal_rule`), `Servers` (`Icons.public`), `Speed` (`Icons.speed`).
- Active: `ink` label 11 w600 + 2 px `accent` underline above the label; inactive `steel`.
- `Servers` calls `showServerSheet(context)` with the current context; if not on `/main`, `context.go('/main')` first, then open after a frame.
- Separate 44×44 settings action at the trailing end: `Icons.tune`, opens `/settings`. No circular raised container, no shadow.
- Long-press on the wordmark or nav → About? No. Keep quick-menu share reachable: move it to Settings ("Share BULBVPN") in Task 8; until then keep a trailing `Icons.ios_share` 44×44 that opens `QuickMenuDialog` only if Settings has not landed yet. Final state: Settings action only.
- RTL: reverse destination order automatically via `Row` + `Directionality`; do not hardcode left/right.

- [ ] **Step 2: Restyle quick menu/dialogs** with `surface`, `hairline`, `ink/steel`; remove gradients and blur.

---

### Task 6: Splash, onboarding, legal

**Files:**
- Rewrite: `lib/modules/splash/presentation/splash_screen.dart`, `lib/modules/onboarding/onboarding_screen.dart`, `lib/modules/legal/legal_screen.dart`

- [ ] **Step 1: Splash**

- `ground` background; centered wordmark `BULB` (`ink`) + `VPN` (`accentInk`) in Schibsted 26 w700.
- One hairline under the wordmark animates width 48→120 over 600 ms; no rotation, no glow.
- Route timing unchanged. Reduced motion: static full width.

- [ ] **Step 2: Onboarding — three frames**

1. **`Your path, prepared.`** Body: `BULBVPN measures working relays before you tap, so the first byte arrives sooner.` Action: `Continue`.
2. **`Every network is different.`** Body: `Relays that work on one carrier fail on another. The app remembers per network and switches when the path changes.` Action: `Continue`.
3. **`One permission.`** Body: `The VPN permission lets BULBVPN carry your traffic. It cannot see your screen, messages, or files.` Action: primary `Allow VPN` (runs the existing permission/connect path), secondary `Not now`.
- Each frame: full-bleed horizon at 44%, a 64 px aperture visual (static), large title 30, body 15, one action. No old screenshots, no dots-as-numbers; a hairline progress bar 1 px.
- If the platform has no permission prompt on this path, keep the current behavior and copy; do not invent a new permission API.
- Persistent footer: `Bootstrap relays are not private. You can import your own server later.` 11 mono `steel`.

- [ ] **Step 3: Legal** — paper sheet, readable measure (max 68 ch), `body 15/1.6 ink`, headings `title 17`, hairlines between sections, same acceptance logic and links.

---

### Task 7: Speed test

**Files:**
- Rewrite visual layer: `speed_test_screen.dart`, `speed_test_header.dart`, `speed_test_start_button.dart`, `speed_test_metrics/*`, `speed_test_progress/speed_test_progress_indicator.dart`, `speed_test_progress/components/speed_value_display.dart`, `speed_test_progress/components/progress_arc_stack.dart`, state widgets, toast.
- Delete painters: `semicircular_progress_painter.dart`, `animated_grid_painter.dart`.
- Keep: providers, services, models, API.

- [ ] **Step 1: Replace the gauge with a horizontal waveform**

- Full-width 96 px band; 5 horizon-aligned baseline ticks (0, 1, 10, 100, 1000 Mbps) in mono 9 `steel`; a 1.4 px `accent` waveform that fills left→right with real measured samples; the live number in mono 44 `ink` above it; unit `Mbps` mono 11 `steel`.
- State colors: idle `steel`, running `accent`, done `connectedInk`, error `alertInk`; labels always present.
- Reduced motion: no traveling shimmer; the waveform still grows with data.
- "Through the tunnel" note: 11 mono `steel` when connected; `Direct measurement — tunnel is off` when idle (honest).

- [ ] **Step 2: Metrics row** — three baseline figures `DOWNLOAD / UPLOAD / PING` in mono 22 `ink`, labels mono 10 `steel`; dashes before measurement; no icons, no cards.

- [ ] **Step 3: Start control** — full-width 52 px, `ink` fill, `surface` text, label `Start test` / `Testing…` / `Test again`; disabled while running; 44 pt minimum.

- [ ] **Step 4: Update `test/metrics_layout_test.dart`** to the new widget names; keep the no-overflow assertions at 1080×2400 and add 320×568 with textScaler 1.3.

---

### Task 8: Settings, routing, logs, paywall, ads, switch

**Files:**
- Rewrite: `settings_screen.dart`, `settings_group_widget.dart`, `settings_item_widget.dart`, `legal_links_section.dart`, `routing_screen.dart`, `logs_screen.dart`, `paywall_screen.dart`, `ad_banner.dart`, `defyx_switch.dart`

- [ ] **Step 1: Settings** — hairline-separated rows on `ground`, section titles `label` mono 10.5 `steel`, 56 px row height, trailing 44×44 controls. Sections: Connection (Kill switch, Split tunneling, Protocol preference → "Automatic (recommended)"), Community sources (toggle with inline warning `Not private · may see your traffic`), Diagnostics (Logs, Copy support blob), About (Share BULBVPN, Legal, Privacy, Terms, Version). Premium row at top only if not premium: `BULBVPN Premium` + `Manage` → paywall.
- [ ] **Step 2: Routing** — same calm rows; app list with 48 px rows and `surface` selected wash; search 44 high; preserve the split-tunnel save logic and `System apps` caution.
- [ ] **Step 3: Logs** — `surface` sheet, mono 11/1.6 `steel`, timestamps `ink`, error lines `alertInk`, success `connectedInk`; copy button 44×44; `Clear` text button with destructive confirmation; empty state `No events yet.`
- [ ] **Step 4: Paywall** — two columns/sections `Free` vs `Premium`; Free: `Owned and bootstrap relays`, `Speed test`, `Split tunneling`; Premium: `Import your own server (VLESS, VMess, Trojan, Shadowsocks, WireGuard, Hysteria2)`, `Priority relays`, `No ads`. Exact store prices; `Restore purchases`; `Terms of Use` + `Privacy Policy` links; no countdown, no fake discount, no "most popular" badge. Keep RevenueCat purchase/restore logic untouched.
- [ ] **Step 5: Ads + switch** — banner on `surface` with hairline, no rounded shadow; switch uses theme colors and 44 pt target.

---

### Task 9: Cleanup, verification, documentation

**Files:**
- Delete: `lib/core/theme/app_colors.dart` after zero references; delete `Outfit-VF.ttf` and its registration; remove unused navbar widgets.
- Create: `DESIGN.md`, `docs/design/evidence/phase1/*`

- [ ] **Step 1: Remove the bridge** — `grep -rn "AppColors" lib test` must return zero; then delete the file and the Outfit font asset.

- [ ] **Step 2: Static checks**

```bash
flutter analyze
flutter test
```

Expected: no errors; all tests pass. Record the exact output in the evidence file.

- [ ] **Step 3: Android emulator**

```bash
scripts/emu.sh boot            # from the android-emulator skill, AVD BulbVpn_4k
scripts/emu.sh run
scripts/emu.sh wait-run
scripts/emu.sh ui-list
scripts/emu.sh screenshot      # save as day-phone.png
```

Verify: home composition, aperture connects/disconnects with honest labels, server sheet tiers, nav, speed test, settings, paywall, legal. Toggle system dark mode (`adb shell cmd uimode night yes|no`) and capture `night-phone.png`. Set font scale to 1.3 (`adb shell settings put system font_scale 1.3`) and capture; restore to 1.0. Enable RTL (`adb shell settings put global debug.force_rtl 1`) and capture; disable. Enable "Remove animations" and confirm no continuous ticker.

- [ ] **Step 4: iOS simulator**

```bash
flutter build ios --simulator --no-codesign
xcrun simctl boot "iPhone 16" || true
flutter run -d "iPhone 16"
```

Capture day/night via `xcrun simctl ui <udid> appearance light|dark` and screenshot with `xcrun simctl io <udid> screenshot`. Verify Dynamic Type at 130% and reduced motion.

- [ ] **Step 5: Fix and re-verify** — batch all render findings, fix once, capture one confirmation round. Cap at two inspection rounds per impeccable.

- [ ] **Step 6: Write `DESIGN.md`** — palette table (day/night), type scale, component anatomy (horizon, aperture, shelf, badge, sheet, buttons), state → copy mapping, motion grammar, accessibility behavior, and the evidence paths. Include a provenance line for every shipped raster used in store listings (if regenerated; Phase 1 only records the raw captures).

- [ ] **Step 7: Store screenshots** — regenerate `store/screenshots/iphone69/*` and `store/screenshots/play-phone/*` from the device captures only after the UI is verified; keep the same shot list (home, connecting, servers, speed test, results). This is a user-visible asset change; do not upload anything.

- [ ] **Step 8: Final report** — list files changed, evidence paths, test counts, remaining risks (upload dash under SoftEther, protocol label auto until engine reports), and confirm no commits were made.

---

## Task Dependency Order

1 → 2 → 3 → 4/5 → 6 → 7 → 8 → 9. Tasks 4, 5, 6 can run in parallel after 3; Task 7 and 8 only need 1–2. Do not start Task 9 until every screen is migrated.

## Acceptance Criteria for Phase 1

1. Both `flutter analyze` and `flutter test` are clean.
2. Android and iOS builds launch and show the Clear Air home in day and Night Air in dark.
3. Every screen renders without overflow at 360×640 with text scale 1.3 and in RTL.
4. Connecting/disconnecting works through the existing engine; status copy matches the real state, and `Connected` still requires the data-path probe.
5. Community/bootstrap relays carry a visible `not private` label on home and in the sheet.
6. Reduced motion removes continuous motion and every screen still communicates state.
7. No `Filament` color, font, orb, ring, or old onboarding screenshot remains in the UI.
8. `DESIGN.md` exists and the device captures are recorded under `docs/design/evidence/phase1/`.
9. No commits were created.
