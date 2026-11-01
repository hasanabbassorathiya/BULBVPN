import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Traffic block that survives an unexpected tunnel drop. Off by default: with
/// it on, a failed connect leaves the phone without internet until the user
/// reconnects or disconnects.
class KillSwitchStore {
  static const _key = 'kill_switch';

  static bool? _cached;

  static bool? get cached => _cached;

  static Future<bool> load() async {
    final memo = _cached;
    if (memo != null) return memo;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_key) ?? false;
      _cached = value;
      return value;
    } catch (_) {
      return false;
    }
  }

  static Future<void> save(bool enabled) async {
    _cached = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
      await SoftEtherVpn.setKillSwitch(enabled);
    } catch (_) {}
  }

  @visibleForTesting
  static void resetCache() => _cached = null;
}

class KillSwitchNotifier extends StateNotifier<bool> {
  KillSwitchNotifier() : super(KillSwitchStore.cached ?? false) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final loaded = await KillSwitchStore.load();
    if (!mounted || loaded == state) return;
    state = loaded;
    await SoftEtherVpn.setKillSwitch(loaded);
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled == state) return;
    state = enabled;
    await KillSwitchStore.save(enabled);
  }
}

final killSwitchProvider = StateNotifierProvider<KillSwitchNotifier, bool>(
  (ref) => KillSwitchNotifier(),
);
