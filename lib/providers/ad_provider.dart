import 'package:flutter/foundation.dart';
import '../services/ad_service.dart';

enum AdPlacement { bannerHome, bannerServers, bannerStats }

class AdProvider extends ChangeNotifier {
  final AdService _service = AdService();
  bool _initialized = false;
  bool _showAds = true;

  AdService get service => _service;
  bool get initialized => _initialized;
  bool get showAds => _showAds;
  bool get isBannerLoaded => _service.isBannerLoaded;
  bool get isRewardedLoaded => _service.isRewardedLoaded;

  Future<void> initialize() async {
    if (_initialized) return;
    await _service.initialize();
    _service.loadBannerAd();
    _service.loadRewardedAd();
    _initialized = true;
    notifyListeners();
  }

  void setShowAds(bool value) {
    _showAds = value;
    notifyListeners();
  }

  Future<bool> watchAdForPremium() async {
    return await _service.showRewardedAd();
  }

  void refreshBanner() {
    _service.loadBannerAd();
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
