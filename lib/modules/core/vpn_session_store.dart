import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the tunnel that is still up after the UI process restarts.
class VpnSessionSnapshot {
  final String label;
  final String host;
  final int startedMs;

  /// Country as published by the catalog, so a restored session shows the
  /// relay that is really up instead of whatever the picker happens to hold.
  final String countryCode;
  final String countryName;

  const VpnSessionSnapshot({
    required this.label,
    required this.host,
    required this.startedMs,
    this.countryCode = '',
    this.countryName = '',
  });
}

class VpnSessionStore {
  static const _key = 'bulb_vpn_session_v1';

  static Future<void> save({
    required String label,
    required String host,
    String countryCode = '',
    String countryName = '',
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
        'countryCode': countryCode,
        'countryName': countryName,
      }),
    );
  }

  static Future<VpnSessionSnapshot?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final host = map['host']?.toString() ?? '';
      if (host.isEmpty) return null;
      return VpnSessionSnapshot(
        label: map['label']?.toString() ?? host,
        host: host,
        startedMs:
            int.tryParse(map['startedMs']?.toString() ?? '') ??
            DateTime.now().millisecondsSinceEpoch,
        countryCode: map['countryCode']?.toString() ?? '',
        countryName: map['countryName']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
