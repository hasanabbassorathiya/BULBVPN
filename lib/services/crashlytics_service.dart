import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class CrashlyticsService {
  static final CrashlyticsService _instance = CrashlyticsService._();
  factory CrashlyticsService() => _instance;
  CrashlyticsService._();

  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  // Initialize crashlytics
  Future<void> initialize() async {
    // Pass all errors to crashlytics
    FlutterError.onError = _crashlytics.recordFlutterFatalError;

    dev.log('Crashlytics initialized', name: 'BULB_VPN');
  }

  // Log non-fatal errors
  Future<void> recordError(dynamic error, StackTrace stackTrace, {String? reason}) async {
    await _crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      printDetails: true,
    );
  }

  // Set custom keys for crash context
  Future<void> setCustomKey({required String key, required dynamic value}) async {
    await _crashlytics.setCustomKey(key, value);
  }

  // Set user identifier (anonymized)
  Future<void> setUserIdentifier(String identifier) async {
    await _crashlytics.setUserIdentifier(identifier);
  }

  // Log messages
  Future<void> log(String message) async {
    await _crashlytics.log(message);
  }

  // Non-fatal exception
  Future<void> recordException(dynamic exception, StackTrace stack, {String? reason}) async {
    await _crashlytics.recordError(exception, stack, reason: reason);
  }

  // Crash (for testing only)
  void crash() {
    _crashlytics.crash();
  }
}
