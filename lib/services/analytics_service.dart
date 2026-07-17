import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._();
  factory AnalyticsService() => _instance;
  AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // App lifecycle
  Future<void> logAppOpen() async {
    await _analytics.logAppOpen();
  }

  Future<void> logLogin({required String method}) async {
    await _analytics.logLogin(loginMethod: method);
  }

  Future<void> logSignUp({required String method}) async {
    await _analytics.logSignUp(signUpMethod: method);
  }

  // Screen views
  Future<void> logScreenView({required String screenName, String? screenClass}) async {
    await _analytics.logScreenView(
      screenName: screenName,
      screenClass: screenClass,
    );
  }

  // VPN events
  Future<void> logConnected({required String server, required String country, required String protocol}) async {
    await _analytics.logEvent(name: 'vpn_connected', parameters: {
      'server': server,
      'country': country,
      'protocol': protocol,
    });
  }

  Future<void> logDisconnected({required int durationSeconds, required double dataUsedMB}) async {
    await _analytics.logEvent(name: 'vpn_disconnected', parameters: {
      'duration_seconds': durationSeconds,
      'data_used_mb': dataUsedMB,
    });
  }

  Future<void> logConnectionFailed({required String reason}) async {
    await _analytics.logEvent(name: 'vpn_connection_failed', parameters: {
      'reason': reason,
    });
  }

  Future<void> logServerSelected({required String server, required String country}) async {
    await _analytics.logEvent(name: 'server_selected', parameters: {
      'server': server,
      'country': country,
    });
  }

  Future<void> logQuickConnect() async {
    await _analytics.logEvent(name: 'quick_connect');
  }

  // Subscription events
  Future<void> logSubscriptionViewed({required String tier}) async {
    await _analytics.logEvent(name: 'subscription_viewed', parameters: {
      'tier': tier,
    });
  }

  Future<void> logSubscriptionPurchased({required String tier, required String period}) async {
    await _analytics.logEvent(name: 'subscription_purchased', parameters: {
      'tier': tier,
      'period': period,
    });
  }

  Future<void> logRestorePurchased({required bool success}) async {
    await _analytics.logEvent(name: 'restore_purchased', parameters: {
      'success': success ? 'true' : 'false',
    });
  }

  // Ad events
  Future<void> logAdShown({required String type}) async {
    await _analytics.logEvent(name: 'ad_shown', parameters: {
      'type': type,
    });
  }

  Future<void> logRewardCompleted({required String reward}) async {
    await _analytics.logEvent(name: 'reward_completed', parameters: {
      'reward': reward,
    });
  }

  // Settings events
  Future<void> logSettingsChanged({required String setting, required dynamic value}) async {
    await _analytics.logEvent(name: 'settings_changed', parameters: {
      'setting': setting,
      'value': value.toString(),
    });
  }

  Future<void> logThemeChanged({required String theme}) async {
    await _analytics.logEvent(name: 'theme_changed', parameters: {
      'theme': theme,
    });
  }

  Future<void> logLanguageChanged({required String language}) async {
    await _analytics.logEvent(name: 'language_changed', parameters: {
      'language': language,
    });
  }

  // User properties
  Future<void> setUserProperty({required String name, required String? value}) async {
    await _analytics.setUserProperty(name: name, value: value);
  }

  Future<void> setUserId({required String? userId}) async {
    await _analytics.setUserId(id: userId);
  }

  // Error logging
  Future<void> logError({required String message, String? stackTrace}) async {
    await _analytics.logEvent(name: 'app_error', parameters: {
      'message': message,
      if (stackTrace != null) 'stack_trace': stackTrace,
    });
  }

  // Generic event logging
  Future<void> logEvent({required String name, Map<String, Object>? parameters}) async {
    await _analytics.logEvent(name: name, parameters: parameters);
  }

  Future<void> logNetworkError({required String endpoint, required int statusCode}) async {
    await _analytics.logEvent(name: 'network_error', parameters: {
      'endpoint': endpoint,
      'status_code': statusCode,
    });
  }
}
