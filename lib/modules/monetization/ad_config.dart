import 'package:flutter/foundation.dart';

/// AdMob identifiers.
///
/// Google's public test units are debug-only. A release build requests ads
/// only once [useTestAds] is false and both live unit IDs are filled in;
/// until then it ships with the ad slots collapsed instead of showing
/// "Test Ad" creatives to users.
///
/// Inventory is also behind Firebase Remote Config (`ads_enabled`, default
/// `false`) — see `ads_remote_config.dart`. A build that passes
/// [canRequestAds] still shows nothing until that flag is published.
class AdConfig {
  const AdConfig._();

  /// Compile-time kill switch for the whole ad system.
  static const bool enabled = true;

  static const bool useTestAds = true;

  // Google sample IDs: https://developers.google.com/admob/flutter/test-ads
  static const String testAndroidAppId =
      'ca-app-pub-3940256099942544~3347511713';
  static const String testIosAppId = 'ca-app-pub-3940256099942544~1458002511';
  static const String testAndroidBannerUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String testIosBannerUnitId =
      'ca-app-pub-3940256099942544/2934735716';

  // Live IDs from the AdMob console. Empty until the account is set up.
  static const String androidAppId = '';
  static const String iosAppId = '';
  static const String androidBannerUnitId = '';
  static const String iosBannerUnitId = '';

  /// True when live IDs are present and test mode is off.
  static bool get isLive =>
      !useTestAds &&
      androidAppId.isNotEmpty &&
      androidBannerUnitId.isNotEmpty &&
      iosAppId.isNotEmpty &&
      iosBannerUnitId.isNotEmpty;

  /// Whether this build may request inventory at all. The visible switch is
  /// the `ads_enabled` Remote Config value; UI gates on both.
  static bool get canRequestAds => enabled && (isLive || !kReleaseMode);

  static bool isTestBanner(String unitId) =>
      unitId.startsWith('ca-app-pub-3940256099942544');

  static String bannerUnitIdFor({required bool isIos}) {
    if (useTestAds) {
      return isIos ? testIosBannerUnitId : testAndroidBannerUnitId;
    }
    final live = isIos ? iosBannerUnitId : androidBannerUnitId;
    return live.isNotEmpty
        ? live
        : (isIos ? testIosBannerUnitId : testAndroidBannerUnitId);
  }
}
