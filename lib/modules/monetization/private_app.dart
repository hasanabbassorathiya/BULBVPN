/// Store monetization stays off while this build is distributed privately.
///
/// Flip [privateBuild] when a public release should show AdMob and RevenueCat.
/// Unit ids and the entitlement name are the only values those SDKs need.
class PrivateApp {
  static const bool privateBuild = true;

  static const bool showAds = !privateBuild;
  static const bool showPaywall = !privateBuild;

  /// AdMob application id is declared in the Android manifest.
  /// Replace the placeholder unit before a public release.
  static const String bannerAdUnitId = 'ca-app-pub-0000000000000000/0000000000';

  /// RevenueCat entitlement checked before a premium gate.
  static const String premiumEntitlement = 'premium';

  static const String revenueCatAppleKey = '';
  static const String revenueCatGoogleKey = '';
}
