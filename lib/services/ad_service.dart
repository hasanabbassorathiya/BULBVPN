import 'dart:developer' as dev;

class AdService {
  bool _initialized = false;
  final bool _isRewardedAdLoaded = false;

  bool get isBannerLoaded => false;
  bool get isRewardedLoaded => _isRewardedAdLoaded;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    dev.log('AdService initialized (ads disabled — pending google_mobile_ads Gradle 9.x compat)', name: 'BULB_VPN');
  }

  void loadBannerAd() {
    dev.log('Banner ad loading skipped (ads disabled)', name: 'BULB_VPN');
  }

  void loadRewardedAd() {
    dev.log('Rewarded ad loading skipped (ads disabled)', name: 'BULB_VPN');
  }

  Future<bool> showRewardedAd() async {
    dev.log('Rewarded ad skipped (ads disabled)', name: 'BULB_VPN');
    return false;
  }

  void dispose() {}
}
