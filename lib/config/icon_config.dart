/// App Icon Configuration
///
/// Required icon assets:
/// - Android: mipmap-mdpi (48x48), mipmap-hdpi (72x72), mipmap-xhdpi (96x96),
///            mipmap-xxhdpi (144x144), mipmap-xxxhdpi (192x192)
/// - iOS: Icon-App-20x20, Icon-App-29x29, Icon-App-40x40, Icon-App-60x60,
///        Icon-App-76x76, Icon-App-83.5x83.5, Icon-App-1024x1024
///
/// Design: Bolt/lightning icon on gradient background (primary → accent)
/// Colors: #00E5C0 (teal) → #6C63FF (purple) gradient
/// Shape: Rounded square with 22% corner radius
class IconConfig {
  IconConfig._();

  static const String appName = 'BULB VPN';
  static const String appTagline = 'Fast. Secure. Private.';

  // Brand colors used in the icon gradient
  static const int gradientStartColor = 0xFF00E5C0; // Teal
  static const int gradientEndColor = 0xFF6C63FF; // Purple

  // Android adaptive icon safe zone (66dp centered in 108dp grid)
  static const double adaptiveIconForegroundSize = 108.0;
  static const double adaptiveIconSafeZone = 66.0;

  // Icon description for designer
  static const String designBrief = '''
  App Icon Design Brief:
  - Central element: White bolt/lightning symbol
  - Background: Gradient from #00E5C0 (top-left) to #6C63FF (bottom-right)
  - Style: Flat, minimal, modern
  - No text on the icon
  - Rounded corners (iOS auto-masks)
  - Must be recognizable at 48x48 pixels
  ''';
}
