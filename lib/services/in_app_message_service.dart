import '../models/in_app_message.dart';
import '../services/storage_service.dart';

class InAppMessageService {
  static final InAppMessageService _instance = InAppMessageService._();
  factory InAppMessageService() => _instance;
  InAppMessageService._();

  List<InAppMessage> _messages = [];
  List<InAppMessage> get messages => _messages;

  Future<void> loadMessages() async {
    _messages = [
      const InAppMessage(
        id: 'upgrade_pro_2024',
        title: 'Upgrade to Pro',
        body: 'Get unlimited servers and streaming access for just \$4.99/month',
        type: InAppMessageType.upgrade,
        position: InAppMessagePosition.topBanner,
        actionText: 'Upgrade Now',
        actionRoute: 'paywall',
        maxViews: 5,
      ),
      const InAppMessage(
        id: 'welcome_2024',
        title: 'Welcome to BULB VPN',
        body: 'Your privacy matters. Connect to stay protected.',
        type: InAppMessageType.feature,
        position: InAppMessagePosition.topBanner,
        actionText: 'Connect Now',
        maxViews: 1,
      ),
      InAppMessage(
        id: 'premium_gaming',
        title: 'Gaming Servers Available',
        body: 'Premium subscribers get access to low-latency gaming servers.',
        type: InAppMessageType.promotional,
        position: InAppMessagePosition.inline,
        actionText: 'Learn More',
        expiresAt: DateTime.now().add(const Duration(days: 14)),
        maxViews: 3,
      ),
    ];
  }

  List<InAppMessage> getMessagesForPosition(InAppMessagePosition position) {
    return _messages.where((m) =>
      m.position == position &&
      !m.isExpired &&
      _getViewCount(m.id) < m.maxViews &&
      !isDismissed(m.id),
    ).toList();
  }

  InAppMessage? getTopBannerMessage() {
    final messages = getMessagesForPosition(InAppMessagePosition.topBanner);
    return messages.isNotEmpty ? messages.first : null;
  }

  InAppMessage? getUpgradeMessage() {
    return _messages.where((m) =>
      m.type == InAppMessageType.upgrade &&
      !m.isExpired &&
      _getViewCount(m.id) < m.maxViews &&
      !isDismissed(m.id),
    ).firstOrNull;
  }

  Future<void> recordView(String messageId) async {
    final key = 'msg_view_$messageId';
    final count = StorageService().getInt(key);
    await StorageService().setInt(key, count + 1);
  }

  Future<void> dismissMessage(String messageId) async {
    await StorageService().setString('msg_dismissed_$messageId', DateTime.now().toIso8601String());
  }

  bool isDismissed(String messageId) {
    return StorageService().getString('msg_dismissed_$messageId') != null;
  }

  int _getViewCount(String messageId) {
    return StorageService().getInt('msg_view_$messageId');
  }
}
