import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the tunnel that is still up after the UI process restarts.
class VpnSessionSnapshot {
  final String label;
  final String host;
  final int startedMs;

  const VpnSessionSnapshot({
    required this.label,
    required this.host,
    required this.startedMs,
  });
}

class VpnSessionStore {
  static const _key = 'bulb_vpn_session_v1';

  static Future<void> save({
    required String label,
    required String host,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await read();
    final sameTunnel = existing != null && existing.host == host;
    final started = sameTunnel
        ? existing.startedMs
        : DateTime.now().millisecondsSinceEpoch;
    await prefs.setString(
      _key,
      jsonEncode({
        'label': label,
        'host': host,
        'startedMs': started,
      }),
    );
  }

  static Future<VpnSessionSnapshot?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return VpnSessionSnapshot(
        label: map['label']?.toString() ?? '',
        host: map['host']?.toString() ?? '',
        startedMs: (map['startedMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
