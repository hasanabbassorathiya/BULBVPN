import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Analytics, Crashlytics, and screen tracking.
///
/// Every entry point is nullable on purpose: Firebase can be absent on a build
/// without configuration or when initialization failed, and telemetry must
/// never take the app down. The VPN does not depend on this class.
class FirebaseAnalyticsService {
  FirebaseAnalyticsService._internal();
  static final FirebaseAnalyticsService _instance =
      FirebaseAnalyticsService._internal();
  factory FirebaseAnalyticsService() => _instance;

  /// The default app, resolved lazily. Initializing only a named app (the old
  /// `name: 'bulbvpn'` call) leaves `Firebase.app()` empty and made every
  /// event, crash report, and screen view a silent no-op on iOS.
  FirebaseAnalytics? get _analytics {
    if (Firebase.apps.isEmpty) return null;
    try {
      return FirebaseAnalytics.instance;
    } catch (error) {
      debugPrint('Analytics unavailable: $error');
      return null;
    }
  }

  FirebaseCrashlytics? get _crashlytics {
    if (Firebase.apps.isEmpty) return null;
    try {
      return FirebaseCrashlytics.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseAnalyticsObserver? getAnalyticsObserver() {
    final analytics = _analytics;
    if (analytics == null) return null;
    try {
      return FirebaseAnalyticsObserver(analytics: analytics);
    } catch (error) {
      debugPrint('Analytics observer unavailable: $error');
      return null;
    }
  }

  Future<void> _log(String name, [Map<String, Object>? parameters]) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.logEvent(name: name, parameters: parameters ?? const {});
    } catch (error) {
      debugPrint('Analytics error: $error');
    }
  }

  Future<void> logVpnConnectAttempt(String connectionMethod) =>
      _log('vpn_connect_attempt', {'connection_method': connectionMethod});

  Future<void> logVpnConnected(
    String connectionMethod,
    String? server,
    int durationSeconds,
  ) => _log('vpn_connected', {
    'connection_method': connectionMethod,
    'connection_duration_seconds': durationSeconds,
    if (server != null) 'server': server,
  });

  Future<void> logVpnDisconnected() => _log('vpn_disconnected');

  Future<void> logConnectionMethodChanged(String newMethod) =>
      _log('connection_method_changed', {'method': newMethod});

  Future<void> logServerSelected(String serverName) =>
      _log('server_selected', {'server': serverName});

  Future<void> logPaywallViewed() => _log('premium_paywall_viewed');

  Future<void> logPremiumPurchase(String productId) =>
      _log('premium_purchase', {'product_id': productId});

  Future<void> logPremiumRestore() => _log('premium_restore');

  Future<void> logSupportOpened(String channel) =>
      _log('support_opened', {'channel': channel});

  Future<void> logVpnFailed({
    required String ip,
    required int ping,
    required String rawStage,
    required String serverLabel,
  }) async {
    await _log('vpn_failed', {
      'ip': ip,
      'ping': ping,
      'raw_stage': rawStage,
      'server_label': serverLabel,
    });
    final crashlytics = _crashlytics;
    if (crashlytics == null) return;
    try {
      await crashlytics.recordError(
        'VPN failed $rawStage $ip $ping',
        StackTrace.current,
        reason: serverLabel,
        fatal: false,
      );
      crashlytics.log('vpn_failed $rawStage $ip $ping $serverLabel');
    } catch (_) {}
  }

  Future<void> setUserId(String? userId) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.setUserId(id: userId);
    } catch (error) {
      debugPrint('Analytics error: $error');
    }
  }

  Future<void> setUserProperty(String name, String? value) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.setUserProperty(name: name, value: value);
    } catch (error) {
      debugPrint('Analytics error: $error');
    }
  }
}
