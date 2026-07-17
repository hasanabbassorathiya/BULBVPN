import 'notification_service.dart';
import 'storage_service.dart';
import 'analytics_service.dart';

class NotificationTriggers {
  static final NotificationTriggers _instance = NotificationTriggers._();
  factory NotificationTriggers() => _instance;
  NotificationTriggers._();

  Future<void> checkSubscriptionExpiry({required DateTime? expiryDate, required bool isSubscriber}) async {
    if (!isSubscriber || expiryDate == null) return;

    final daysLeft = expiryDate.difference(DateTime.now()).inDays;
    final lastReminder = StorageService().getString('last_expiry_reminder');
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (lastReminder == today) return;

    if (daysLeft <= 3 && daysLeft > 0) {
      await NotificationService().showLocalNotification(
        title: 'Subscription Expiring Soon',
        body: 'Your subscription expires in $daysLeft days. Renew now to keep your protection.',
        payload: 'subscription_expiry',
      );
      await StorageService().setString('last_expiry_reminder', today);
      AnalyticsService().logEvent(name: 'notification_expiry_reminder');
    }
  }

  Future<void> checkConnectionReminder({required bool isConnected, required bool autoConnect}) async {
    if (isConnected || autoConnect) return;

    final lastReminder = StorageService().getString('last_connection_reminder');
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (lastReminder == today) return;

    await NotificationService().showLocalNotification(
      title: 'Stay Protected',
      body: 'Your VPN is not connected. Tap to connect and stay safe.',
      payload: 'connection_reminder',
    );
    await StorageService().setString('last_connection_reminder', today);
    AnalyticsService().logEvent(name: 'notification_connection_reminder');
  }

  Future<void> showServerAlert({required String serverName, required String message}) async {
    await NotificationService().showLocalNotification(
      title: 'Server Alert: $serverName',
      body: message,
      payload: 'server_alert',
    );
    AnalyticsService().logEvent(name: 'notification_server_alert');
  }

  Future<void> showPromoOffer({required String title, required String body, String? promoCode}) async {
    final lastPromo = StorageService().getString('last_promo_notification');
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (lastPromo == today) return;

    await NotificationService().showLocalNotification(
      title: title,
      body: body,
      payload: promoCode != null ? 'promo:$promoCode' : 'promo',
    );
    await StorageService().setString('last_promo_notification', today);
    AnalyticsService().logEvent(name: 'notification_promo');
  }

  Future<void> checkWelcomeBack() async {
    final lastActive = StorageService().getString('last_active_date');
    if (lastActive == null) return;

    final lastDate = DateTime.parse(lastActive);
    final daysInactive = DateTime.now().difference(lastDate).inDays;

    if (daysInactive >= 3) {
      final lastWelcome = StorageService().getString('last_welcome_back');
      final today = DateTime.now().toIso8601String().substring(0, 10);

      if (lastWelcome != today) {
        await NotificationService().showLocalNotification(
          title: 'We Miss You!',
          body: 'Your online security matters. Connect to BULB VPN to stay protected.',
          payload: 'welcome_back',
        );
        await StorageService().setString('last_welcome_back', today);
        AnalyticsService().logEvent(name: 'notification_welcome_back');
      }
    }
  }

  Future<void> recordActiveDate() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await StorageService().setString('last_active_date', today);
  }
}
