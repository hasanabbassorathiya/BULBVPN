import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

/// Initializes the Google Mobile Ads SDK behind the UMP consent flow.
///
/// Ads are only requested after [initialize] resolves `true`; a failure or a
/// user who has not consented keeps the banner widget empty rather than
/// showing a broken frame. The future is shared so every rebuilder and every
/// screen reuses one initialization.
class AdService {
  const AdService._();

  static Future<bool>? _ready;

  static Future<bool> initialize() {
    if (!AdConfig.canRequestAds) return Future.value(false);
    if (!(Platform.isAndroid || Platform.isIOS)) return Future.value(false);
    return _ready ??= _initialize();
  }

  static Future<bool> _initialize() async {
    try {
      await MobileAds.instance.initialize();
      await _collectConsent();
      final canRequest = await ConsentInformation.instance.canRequestAds();
      if (kDebugMode) {
        debugPrint('[Ads] initialized, canRequestAds=$canRequest');
      }
      return canRequest;
    } catch (error) {
      debugPrint('[Ads] initialization failed: $error');
      return false;
    }
  }

  static Future<void> _collectConsent() {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          if (await ConsentInformation.instance.isConsentFormAvailable()) {
            await ConsentForm.loadAndShowConsentFormIfRequired((error) {
              if (error != null) {
                debugPrint('[Ads] consent form error: ${error.message}');
              }
            });
          }
        } catch (error) {
          debugPrint('[Ads] consent flow failed: $error');
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (error) {
        debugPrint('[Ads] consent update failed: ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );
    // A slow network must not hold the first frame hostage; the banner simply
    // waits for a later retry when consent could not be resolved in time.
    return completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        if (!completer.isCompleted) {
          debugPrint('[Ads] consent update timed out');
          completer.complete();
        }
      },
    );
  }

  /// True when the user is in a region where a privacy options entry point is
  /// required (EEA/UK/Switzerland). Settings uses this to expose the link.
  static Future<bool> needsPrivacyOptions() async {
    if (!AdConfig.canRequestAds) return false;
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// Reopens Google's consent form so ads can switch between personalized and
  /// non-personalized after the first run.
  static Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((error) {
        if (error != null) {
          debugPrint('[Ads] privacy options error: ${error.message}');
        }
      });
    } catch (error) {
      debugPrint('[Ads] privacy options failed: $error');
    }
  }
}
