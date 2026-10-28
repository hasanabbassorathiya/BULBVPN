import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firebase Remote Config key that turns AdMob inventory on.
const adsEnabledKey = 'ads_enabled';

/// Remote switch for ads, default OFF.
///
/// The app ships ad-free: [state] stays false until `ads_enabled` is published
/// as `true` in Firebase Remote Config. The fetch runs in the background and
/// never blocks the first frame; the last activated value is reused on the
/// next launch, so flipping the console flag needs no app update. Any failure
/// (Firebase not initialized, no network, throttled fetch) leaves ads off.
class AdsRemoteConfigNotifier extends StateNotifier<bool> {
  AdsRemoteConfigNotifier() : super(false);

  static const _firebaseAppName = 'bulbvpn';

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final remote = FirebaseRemoteConfig.instanceFor(app: _firebaseApp());
      await remote.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          // Debug builds refetch every launch so the flag can be tested;
          // release respects Remote Config's production throttle.
          minimumFetchInterval: kDebugMode
              ? Duration.zero
              : const Duration(minutes: 30),
        ),
      );
      await remote.setDefaults(const {adsEnabledKey: false});
      // A failed fetch keeps the last activated value; a first launch without
      // network keeps the false default.
      await remote.fetchAndActivate();
      if (!mounted) return;
      state = remote.getBool(adsEnabledKey);
      debugPrint('[Ads] remote ads_enabled=$state');
    } catch (error) {
      debugPrint('[Ads] remote config unavailable, ads stay off: $error');
    }
  }

  /// `main.dart` registers Firebase under the name `bulbvpn`; fall back to the
  /// default app if that ever changes.
  FirebaseApp _firebaseApp() {
    try {
      return Firebase.app(_firebaseAppName);
    } on FirebaseException {
      return Firebase.app();
    }
  }
}

final adsEnabledProvider = StateNotifierProvider<AdsRemoteConfigNotifier, bool>(
  (ref) {
    final notifier = AdsRemoteConfigNotifier();
    unawaited(notifier.start());
    return notifier;
  },
);
