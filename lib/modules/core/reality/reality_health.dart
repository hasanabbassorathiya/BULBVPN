import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bulbvpn/modules/core/log.dart';

/// One relay's last end-to-end measurement from the scheduled GitHub Action.
class RealityHealthEntry {
  const RealityHealthEntry({
    required this.id,
    required this.ok,
    required this.bytes,
    required this.ms,
  });

  final String id;
  final bool ok;
  final int bytes;
  final int ms;

  int get bps => ms <= 0 ? 0 : (bytes * 1000) ~/ ms;
}

/// Measured health for the bundled REALITY relays.
///
/// The GitHub Action dials each relay with Xray and downloads a fixed payload,
/// so an entry is evidence of a forwarding session rather than a TLS probe.
/// Entries are keyed by the bundled catalog id and are only used as a ranking
/// prior: local per-network proof and the app's own data gate still win.
class RealityHealth {
  RealityHealth._(this.generatedAt, this.byId);

  final DateTime generatedAt;
  final Map<String, RealityHealthEntry> byId;

  static const schema = 1;

  /// A measurement older than this is ignored. The workflow publishes every
  /// three hours; 18 hours tolerates several missed runs without letting a
  /// week-old ranking steer a connection.
  static const maxAge = Duration(hours: 18);

  static const _maxBytes = 8 * 1024 * 1024;
  static const _maxMs = 120000;

  bool get usable => DateTime.now().difference(generatedAt) < maxAge;

  int get healthyCount => byId.values.where((entry) => entry.ok).length;

  static RealityHealth? parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schema'] != schema) return null;
      final at = DateTime.tryParse(decoded['generated_at']?.toString() ?? '');
      if (at == null) return null;
      final probes = decoded['probes'];
      if (probes is! List) return null;
      final byId = <String, RealityHealthEntry>{};
      for (final probe in probes) {
        if (probe is! Map) continue;
        final id = probe['id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        final bytes = int.tryParse(probe['bytes']?.toString() ?? '') ?? -1;
        final ms = int.tryParse(probe['ms']?.toString() ?? '') ?? -1;
        if (bytes < 0 || bytes > _maxBytes || ms < 0 || ms > _maxMs) {
          continue;
        }
        byId[id] = RealityHealthEntry(
          id: id,
          ok: probe['ok'] == true,
          bytes: bytes,
          ms: ms,
        );
      }
      if (byId.isEmpty) return null;
      return RealityHealth._(at, byId);
    } catch (_) {
      return null;
    }
  }

  /// Ranking adjustment for [RelayMemory.orderByHistory].
  ///
  /// Healthy relays get a bonus that scales with measured throughput; failed
  /// ones get a penalty smaller than one local failure streak, so a relay that
  /// just failed on this phone still sinks regardless of what a datacenter
  /// measured hours ago.
  double? scoreFor(String relayId) {
    final entry = byId[relayId];
    if (entry == null) return null;
    if (!entry.ok) return 45000;
    final kib = entry.bps / 1024;
    return -40000 - kib.clamp(0, 20000).toDouble();
  }

  /// Health is only meaningful for relays this build ships. Unknown ids in a
  /// fetched file are ignored here, so a tampered response cannot introduce a
  /// relay the app would then dial.
  Map<String, double> scoresFor(Iterable<String> relayIds) {
    final scores = <String, double>{};
    for (final id in relayIds) {
      final score = scoreFor(id);
      if (score != null) scores[id] = score;
    }
    return scores;
  }
}

class RealityHealthStore {
  RealityHealthStore._();

  static const _cacheKey = 'bulb_reality_health_v1';

  /// Bundled with the build, so the first press on a fresh install still has
  /// measured data. The scheduled workflow refreshes it in the repository.
  static const _asset = 'data/reality_health.json';

  /// Same publishing pattern as the VPN Gate list. jsDelivr is usually
  /// reachable when raw.githubusercontent is not; raw is fresher.
  static const urls = <String>[
    'https://raw.githubusercontent.com/hasanabbassorathiya/BULBVPN/main/data/reality_health.json',
    'https://cdn.jsdelivr.net/gh/hasanabbassorathiya/BULBVPN@main/data/reality_health.json',
  ];

  static RealityHealth? _cached;

  static Future<RealityHealth?> load() async {
    final cached = _cached;
    if (cached != null) return cached.usable ? cached : null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final health = RealityHealth.parse(raw);
        if (health != null && health.usable) {
          _cached = health;
          return health;
        }
      }
    } catch (_) {}
    try {
      final raw = await rootBundle.loadString(_asset);
      final health = RealityHealth.parse(raw);
      if (health != null && health.usable) {
        _cached = health;
        return health;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> refresh() async {
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) continue;
        final health = RealityHealth.parse(response.body);
        if (health == null || !health.usable) {
          Log().addLog(
            '[RealityHealth] rejected payload from ${Uri.parse(url).host}',
          );
          continue;
        }
        _cached = health;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, response.body);
        Log().addLog(
          '[RealityHealth] ${health.healthyCount}/${health.byId.length} '
          'healthy via ${Uri.parse(url).host}',
        );
        return;
      } catch (_) {
        // A blocked host or a slow CDN must never fail the caller.
      }
    }
    Log().addLog('[RealityHealth] no usable measurements; local order kept');
  }

  @visibleForTesting
  static void resetCache() => _cached = null;
}
