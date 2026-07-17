import 'dart:developer' as dev;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    dev.log('NotificationService initialized (FCM pending — native libs not yet available)', name: 'BULB_VPN');
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int? id,
  }) async {
    dev.log('Local notification: $title — $body', name: 'BULB_VPN');
  }

  Future<void> subscribeToTopic(String topic) async {
    dev.log('Topic subscription skipped (FCM pending)', name: 'BULB_VPN');
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    dev.log('Topic unsubscription skipped (FCM pending)', name: 'BULB_VPN');
  }
}
