import 'package:flutter/foundation.dart';
import '../services/subscription_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  final SubscriptionService _service = SubscriptionService();
  bool _isLoading = false;
  String? _error;

  SubscriptionService get service => _service;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isPro => _service.isPro;
  bool get isPremium => _service.isPremium;
  bool get isSubscriber => _service.isSubscriber;
  String get tier => _service.subscriptionTier;

  // Feature gates
  bool get hasUnlimitedServers => _service.hasUnlimitedServers;
  bool get hasStreamingServers => _service.hasStreamingServers;
  bool get hasGamingServers => _service.hasGamingServers;
  bool get hasNoAds => _service.hasNoAds;
  bool get hasPrioritySupport => _service.hasPrioritySupport;
  bool get hasAdvancedProtocol => _service.hasAdvancedProtocol;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _service.initialize();
    } catch (e) {
      _error = e.toString();
    }
    
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> purchase(dynamic package) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    final success = await _service.purchase(package);
    
    _isLoading = false;
    if (!success) _error = 'Purchase failed. Please try again.';
    notifyListeners();
    return success;
  }

  Future<bool> restore() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    final success = await _service.restorePurchases();
    
    _isLoading = false;
    if (!success) _error = 'No active subscriptions found.';
    notifyListeners();
    return success;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
