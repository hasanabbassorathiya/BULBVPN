import 'dart:developer' as dev;

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._();
  factory SubscriptionService() => _instance;
  SubscriptionService._();

  bool _initialized = false;

  bool get isPro => false;
  bool get isPremium => false;
  bool get isSubscriber => false;
  String get subscriptionTier => 'free';

  bool get hasUnlimitedServers => false;
  bool get hasStreamingServers => false;
  bool get hasGamingServers => false;
  bool get hasNoAds => false;
  bool get hasPrioritySupport => false;
  bool get hasAdvancedProtocol => false;

  Future<void> initialize({String? apiKey}) async {
    if (_initialized) return;
    _initialized = true;
    dev.log('SubscriptionService initialized (RevenueCat pending — native libs not yet available)', name: 'BULB_VPN');
  }

  Future<bool> purchase(dynamic package) async {
    dev.log('Purchase skipped (RevenueCat pending)', name: 'BULB_VPN');
    return false;
  }

  Future<bool> restorePurchases() async {
    dev.log('Restore skipped (RevenueCat pending)', name: 'BULB_VPN');
    return false;
  }

  Future<void> syncWithAuth(String userId) async {}
  Future<void> logout() async {}
}
