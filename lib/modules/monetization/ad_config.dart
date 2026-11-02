import 'dart:io';

import 'package:flutter/foundation.dart';

/// AdMob identifiers.
///
/// Google's public test units are debug-only and are never used in a release
/// build. A platform without a live app/banner pair requests nothing instead
/// of falling back to sample creatives.
///
/// Inventory is also behind Firebase Remote Config (`ads_enabled`, default
/// `false`) — see `ads_remote_config.dart`. A build that passes
/// [canRequestAds] still shows nothing until that flag is published.
class AdConfig {
  const AdConfig._();

  /// Compile-time kill switch for the whole ad system.
  static const bool enabled = true;

  static const bool useTestAds = false;

  // Google sample IDs: https://developers.google.com/admob/flutter/test-ads
  static const String testAndroidAppId =
      'ca-app-pub-3940256099942544~3347511713';
  static const String testIosAppId = 'ca-app-pub-3940256099942544~1458002511';
  static const String testAndroidBannerUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String testIosBannerUnitId =
      'ca-app-pub-3940256099942544/2934735716';

  // Live IDs from the AdMob console (publisher ca-app-pub-3075850349836552).
  static const String androidAppId = 'ca-app-pub-3075850349836552~5056027114';
  static const String iosAppId = 'ca-app-pub-3075850349836552~4383829994';
  static const String androidBannerUnitId =
      'ca-app-pub-3075850349836552/2637747334';
  static const String iosBannerUnitId =
      'ca-app-pub-3075850349836552/8376587886';

  static bool _hasLiveIds({required bool isIos}) => isIos
      ? iosAppId.isNotEmpty && iosBannerUnitId.isNotEmpty
      : androidAppId.isNotEmpty && androidBannerUnitId.isNotEmpty;

  /// True when the current platform has both a live app ID and banner unit.
  static bool get isLive =>
      !useTestAds && _hasLiveIds(isIos: Platform.isIOS);

  /// Whether this build may request inventory on this platform. The visible
  /// switch is the `ads_enabled` Remote Config value; UI gates on both.
  static bool get canRequestAds =>
      enabled &&
      (useTestAds ? !kReleaseMode : _hasLiveIds(isIos: Platform.isIOS));

  static bool isTestBanner(String unitId) =>
      unitId.startsWith('ca-app-pub-3940256099942544');

  /// The unit for this platform, or an empty string when ads are not
  /// configured here. Callers must skip the request on an empty id.
  static String bannerUnitIdFor({required bool isIos}) {
    if (useTestAds) {
      return isIos ? testIosBannerUnitId : testAndroidBannerUnitId;
    }
    return isIos ? iosBannerUnitId : androidBannerUnitId;
  }
}
