import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'network_identity.dart';
import 'relay_target.dart';

/// Remembers which relay actually carried traffic on each network.
///
/// A SoftEther relay that works on home Wi-Fi is frequently dead on a carrier,
/// and the reverse. The single global last-good entry made every handover start
/// by redialling a relay from the other network. Entries are written only after
/// a successful native dial and removed as soon as that relay fails again.
class RelayMemory {
  RelayMemory._();

  static const _key = 'bulb_relay_memory_v2';
  static const _statsKey = 'bulb_relay_stats_v1';
  static const _healthKey = 'bulb_engine_health_v1';
  static const _proofKey = 'bulb_relay_proof_v1';
  static const _maxEntries = 8;
  static const _maxStats = 128;
  static const _maxHealth = 16;
  static const _maxProofs = 24;
  static const _maxAgeMs = 14 * 24 * 60 * 60 * 1000;
  static const _statsMaxAgeMs = 30 * 24 * 60 * 60 * 1000;
  static const _healthMaxAgeMs = 7 * 24 * 60 * 60 * 1000;
  static const _proofMaxAgeMs = 14 * 24 * 60 * 60 * 1000;

  /// Below this a relay can still complete a handshake but cannot carry a
  /// usable page. Measured rates under it are ranked behind unmeasured relays.
  static const int slowThroughputBps = 24000;

  /// One anchor per network *and engine*: a REALITY pick must not evict the
  /// SoftEther relay this network proved, and the reverse.
  static String _memoryKey(String network, String engine) =>
      '$network|$engine';

  static Future<RelayTarget?> recall({
    String? network,
    String engine = 'softether',
  }) async {
    final fingerprint = network ?? await NetworkIdentity.current();
    if (!_usable(fingerprint)) return null;
    final entries = await _read();
    final key = _memoryKey(fingerprint, engine);
    // Entries written before this split are keyed by the bare network and
    // belong to the SoftEther path, which was the only writer then.
    final entry = entries[key] ?? (engine == 'softether' ? entries[fingerprint] : null);
    if (entry == null) return null;
    final at = int.tryParse(entry['at']?.toString() ?? '') ?? 0;
    if (at > 0 && DateTime.now().millisecondsSinceEpoch - at > _maxAgeMs) {
      entries.remove(key);
      entries.remove(fingerprint);
      await _write(entries);
      return null;
    }
    final dial = entry['dial']?.toString() ?? '';
    if (dial.isEmpty) return null;
    final sni = entry['sni']?.toString().trim() ?? '';
    final port = (entry['port'] as num?)?.toInt() ?? 443;
    return RelayTarget(
      dial: dial,
      // An entry written by the OpenVPN path may have no catalog hostname.
      // SoftEther must never be dialled with an empty TLS name.
      sni: sni.isEmpty ? dial : sni,
      port: port >= 1 && port <= 65535 ? port : 443,
      countryCode: (entry['countryCode']?.toString() ?? '').toUpperCase(),
      countryName: entry['countryName']?.toString() ?? '',
      pingMs: int.tryParse(entry['pingMs']?.toString() ?? '') ?? 0,
      source: 'network-memory',
    );
  }

  static Future<void> remember(
    RelayTarget target, {
    String? network,
    String engine = 'softether',
  }) async {
    if (target.dial.isEmpty) return;
    final fingerprint = network ?? await NetworkIdentity.current();
    if (!_usable(fingerprint)) return;
    final entries = await _read();
    entries[_memoryKey(fingerprint, engine)] = {
      'dial': target.dial,
      'sni': target.sni.trim().isEmpty ? target.dial : target.sni,
      'port': target.port,
      'countryCode': target.countryCode,
      'countryName': target.countryName,
      'pingMs': target.pingMs,
      'engine': engine,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    while (entries.length > _maxEntries) {
      String? oldest;
      var oldestAt = 1 << 62;
      entries.forEach((key, value) {
        final at = int.tryParse(value['at']?.toString() ?? '') ?? 0;
        if (at < oldestAt) {
          oldestAt = at;
          oldest = key;
        }
      });
      if (oldest == null) break;
      final victim = oldest;
      entries.remove(victim);
    }
    await _write(entries);
    await _bumpStats(
      target.dial,
      success: true,
      network: fingerprint,
      rttMs: target.pingMs > 0 ? target.pingMs : null,
    );
  }

  /// Removes [dial] for the current network if it is still the remembered
  /// relay. A newer successful relay must not be deleted by an older failure,
  /// and [engine] keeps one engine's failure from erasing another's anchor.
  static Future<void> forget(
    String dial, {
    String? network,
    String? engine,
  }) async {
    final fingerprint = network ?? await NetworkIdentity.current();
    if (!_usable(fingerprint)) return;
    final entries = await _read();
    final prefix = '$fingerprint|';
    final keys = [
      for (final key in entries.keys)
        if (key == fingerprint || key.startsWith(prefix)) key,
    ];
    var changed = false;
    for (final key in keys) {
      if (entries[key]?['dial']?.toString() != dial) continue;
      if (engine != null) {
        final tagged = entries[key]?['engine']?.toString() ?? 'softether';
        if (tagged != engine) continue;
      }
      entries.remove(key);
      changed = true;
    }
    if (changed) await _write(entries);
  }

  static bool _usable(String fingerprint) =>
      fingerprint != 'offline' && fingerprint != 'unknown';

  /// Records a whole probe round with one disk write. [rttMs] is keyed by dial.
  static Future<void> recordProbes(
    Map<String, bool> results, {
    String? network,
    Map<String, int> rttMs = const {},
  }) async {
    if (results.isEmpty) return;
    final fingerprint = network ?? await NetworkIdentity.current();
    if (!_usable(fingerprint)) return;
    final stats = await _readStats();
    final now = DateTime.now().millisecondsSinceEpoch;
    results.forEach((dial, ok) {
      if (dial.isEmpty) return;
      final key = '$fingerprint|$dial';
      final entry = stats[key] ?? <String, dynamic>{};
      final streak = int.tryParse(entry['streak']?.toString() ?? '') ?? 0;
      entry['ok'] =
          (int.tryParse(entry['ok']?.toString() ?? '') ?? 0) + (ok ? 1 : 0);
      entry['fail'] =
          (int.tryParse(entry['fail']?.toString() ?? '') ?? 0) + (ok ? 0 : 1);
      entry['streak'] = ok ? 0 : streak + 1;
      entry[ok ? 'lastOk' : 'lastFail'] = now;
      final rtt = rttMs[dial] ?? 0;
      if (rtt > 0) entry['rtt'] = rtt;
      entry['at'] = now;
      stats[key] = entry;
    });
    _pruneStats(stats, now);
    await _writeStats(stats);
  }

  /// Records that [target] carried a real transfer with [engine] on some
  /// network.
  ///
  /// This is deliberately global rather than per-network. A relay that
  /// forwarded traffic at all is a better first guess on a new carrier than a
  /// server that merely answered a TLS ping: ping proves reachability, not
  /// that a SoftEther hub or a REALITY relay will move packets. The entry is
  /// only written after a data gate passed, so it cannot be earned by a
  /// handshake alone.
  static Future<void> recordSessionProof(
    RelayTarget target, {
    required String engine,
    int bytesPerSecond = 0,
    String? network,
  }) async {
    if (target.dial.isEmpty || engine.isEmpty) return;
    final proofs = await _readMap(_proofKey);
    final previousBps =
        int.tryParse(proofs[target.dial]?['bps']?.toString() ?? '') ?? 0;
    proofs[target.dial] = {
      'sni': target.sni.trim().isEmpty ? target.dial : target.sni,
      'port': target.port,
      'countryCode': target.countryCode,
      'countryName': target.countryName,
      'engine': engine,
      'bps': bytesPerSecond > 0 ? bytesPerSecond : previousBps,
      'network': network ?? '',
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    _pruneMap(proofs, _maxProofs, _proofMaxAgeMs);
    await _writeMap(_proofKey, proofs);
  }

  /// Endpoints that carried a verified transfer with [engine], most recent
  /// first. The returned targets are valid dial plans on their own: the SNI,
  /// country and port were captured at proof time, so a relay that has since
  /// dropped out of the catalog is still dialable.
  static Future<List<RelayTarget>> provenRelays(String engine) async {
    if (engine.isEmpty) return const <RelayTarget>[];
    final proofs = await _readMap(_proofKey);
    final entries = <(int, RelayTarget)>[];
    proofs.forEach((dial, entry) {
      if (entry['engine']?.toString() != engine) return;
      final at = int.tryParse(entry['at']?.toString() ?? '') ?? 0;
      if (at == 0) return;
      if (DateTime.now().millisecondsSinceEpoch - at > _proofMaxAgeMs) return;
      final sni = entry['sni']?.toString().trim() ?? '';
      final port = (entry['port'] as num?)?.toInt() ?? 443;
      entries.add((
        at,
        RelayTarget(
          dial: dial,
          sni: sni.isEmpty ? dial : sni,
          port: port >= 1 && port <= 65535 ? port : 443,
          countryCode: (entry['countryCode']?.toString() ?? '').toUpperCase(),
          countryName: entry['countryName']?.toString() ?? '',
          pingMs: 0,
          source: 'proven-session',
        ),
      ));
    });
    entries.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final entry in entries) entry.$2];
  }

  /// Dial keys that carried a verified transfer with [engine]. Used as a
  /// ranking bonus where only the membership matters.
  static Future<Set<String>> provenDials(String engine) async {
    if (engine.isEmpty) return const <String>{};
    return {for (final target in await provenRelays(engine)) target.dial};
  }

  /// A relay-level failure (TLS/auth/hub) after the TCP probe succeeded.
  static Future<void> recordDialFailure(String dial, {String? network}) {
    return recordProbes({dial: false}, network: network);
  }

  /// Records how much data this relay actually carried after the tunnel came
  /// up. A completed handshake with a trickle behind it is still unreachable
  /// from the user's point of view, so a low rate sinks the relay in
  /// [orderByHistory] instead of being hidden by a fast TLS round trip.
  ///
  /// Zero is a real measurement (the tunnel forwarded nothing), not an absent
  /// one, and is ranked as the worst possible result.
  static Future<void> recordThroughput(
    String dial,
    int bytesPerSecond, {
    String? network,
  }) async {
    if (dial.isEmpty || bytesPerSecond < 0) return;
    final fingerprint = network ?? await NetworkIdentity.current();
    if (!_usable(fingerprint)) return;
    final stats = await _readStats();
    final key = '$fingerprint|$dial';
    final entry = stats[key] ?? <String, dynamic>{};
    entry['bps'] = bytesPerSecond;
    entry['at'] = DateTime.now().millisecondsSinceEpoch;
    stats[key] = entry;
    _pruneStats(stats, DateTime.now().millisecondsSinceEpoch);
    await _writeStats(stats);
  }

  /// Records whether a whole connect attempt with [engine] produced a working
  /// tunnel on this network.
  ///
  /// A streak of failed attempts means the engine is being throttled here,
  /// not that one relay is unlucky: redialling the fleet on every recovery
  /// would spend the connect budget before the fallback is reached. A success
  /// resets the streak, and a new network has its own entry.
  static Future<void> recordEngineOutcome(
    String engine,
    bool ok, {
    String? network,
  }) async {
    final fingerprint = network ?? await NetworkIdentity.current();
    if (!_usable(fingerprint) || engine.isEmpty) return;
    final health = await _readMap(_healthKey);
    final key = '$fingerprint|$engine';
    final entry = health[key] ?? <String, dynamic>{};
    final streak = int.tryParse(entry['streak']?.toString() ?? '') ?? 0;
    entry['streak'] = ok ? 0 : streak + 1;
    entry['at'] = DateTime.now().millisecondsSinceEpoch;
    health[key] = entry;
    _pruneMap(health, _maxHealth, _healthMaxAgeMs);
    await _writeMap(_healthKey, health);
  }

  /// True when [engine] failed the last [minStreak] attempts on this network
  /// within [window]. An explicit relay pick bypasses this so the user can
  /// always retry by hand.
  static Future<bool> engineRecentlyFailing(
    String engine, {
    String? network,
    Duration window = const Duration(minutes: 20),
    int minStreak = 3,
  }) async {
    final fingerprint = network ?? await NetworkIdentity.current();
    if (!_usable(fingerprint) || engine.isEmpty) return false;
    final health = await _readMap(_healthKey);
    final entry = health['$fingerprint|$engine'];
    if (entry == null) return false;
    final streak = int.tryParse(entry['streak']?.toString() ?? '') ?? 0;
    final at = int.tryParse(entry['at']?.toString() ?? '') ?? 0;
    if (streak < minStreak || at == 0) return false;
    return DateTime.now().millisecondsSinceEpoch - at <= window.inMilliseconds;
  }

  /// Stable, per-network ordering used instead of raw catalog order.
  ///
  /// A relay that recently failed is pushed back but never removed: when a
  /// whole country is blocked, every relay is penalised and the least-bad
  /// order must still be attempted.
  static Future<List<RelayTarget>> orderByHistory(
    List<RelayTarget> targets, {
    String? network,
    Set<String> proven = const <String>{},
    Map<String, double> extraScore = const <String, double>{},
  }) async {
    if (targets.length < 2) return targets;
    final fingerprint = network ?? await NetworkIdentity.current();
    if (!_usable(fingerprint)) return targets;
    final stats = await _readStats();
    if (stats.isEmpty && proven.isEmpty && extraScore.isEmpty) return targets;
    final now = DateTime.now().millisecondsSinceEpoch;
    final indexed = targets.indexed.toList();
    indexed.sort((a, b) {
      final result = _score(
        a.$2,
        fingerprint,
        stats,
        now,
        proven,
        extraScore,
      ).compareTo(_score(b.$2, fingerprint, stats, now, proven, extraScore));
      return result != 0 ? result : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  static double _score(
    RelayTarget target,
    String network,
    Map<String, Map<String, dynamic>> stats,
    int now,
    Set<String> proven,
    Map<String, double> extraScore,
  ) {
    final entry = stats['$network|${target.dial}'];
    var value = (target.pingMs > 0 ? target.pingMs : 5000).toDouble();
    // A relay that already moved real bytes with this engine outranks one
    // that only answered a probe. The bonus is smaller than two failure
    // streaks, so a proven relay that started failing still sinks.
    if (proven.contains(target.dial)) value -= 80000;
    value += extraScore[target.dial] ?? 0;
    if (entry == null) return value;
    int read(String key) => int.tryParse(entry[key]?.toString() ?? '') ?? 0;
    final streak = read('streak');
    final failures = read('fail');
    final successes = read('ok');
    final lastFail = read('lastFail');
    final lastOk = read('lastOk');
    final rtt = read('rtt');
    final bps = read('bps');
    value += streak * 60000;
    value += failures * 2000;
    value -= (successes > 8 ? 8 : successes) * 1500;
    if (lastFail > 0 && now - lastFail < 10 * 60 * 1000) value += 30000;
    if (lastOk > 0 && now - lastOk < 24 * 60 * 60 * 1000) value -= 8000;
    if (rtt > 0) value += rtt.clamp(0, 5000);
    if (entry.containsKey('bps')) {
      // A relay that completed TLS but carried almost nothing must lose to
      // relays that have not been measured yet, otherwise every reconnect
      // returns to the same trickle. Zero is a measurement, not a blank.
      if (bps < 8000) {
        value += 45000;
      } else if (bps < slowThroughputBps) {
        value += 12000;
      } else if (bps > 250000) {
        value -= 10000;
      } else if (bps > 100000) {
        value -= 4000;
      }
    }
    return value;
  }

  static Future<void> _bumpStats(
    String dial, {
    required bool success,
    required String network,
    int? rttMs,
  }) async {
    if (!_usable(network)) return;
    final stats = await _readStats();
    final key = '$network|$dial';
    final entry = stats[key] ?? <String, dynamic>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    final streak = int.tryParse(entry['streak']?.toString() ?? '') ?? 0;
    entry['ok'] =
        (int.tryParse(entry['ok']?.toString() ?? '') ?? 0) + (success ? 1 : 0);
    entry['fail'] =
        (int.tryParse(entry['fail']?.toString() ?? '') ?? 0) +
        (success ? 0 : 1);
    entry['streak'] = success ? 0 : streak + 1;
    entry[success ? 'lastOk' : 'lastFail'] = now;
    if (rttMs != null && rttMs > 0) entry['rtt'] = rttMs;
    entry['at'] = now;
    stats[key] = entry;
    _pruneStats(stats, now);
    await _writeStats(stats);
  }

  static void _pruneStats(Map<String, Map<String, dynamic>> stats, int now) {
    _pruneMap(stats, _maxStats, _statsMaxAgeMs, now: now);
  }

  static void _pruneMap(
    Map<String, Map<String, dynamic>> map,
    int maxEntries,
    int maxAgeMs, {
    int? now,
  }) {
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    map.removeWhere((_, entry) {
      final updated = int.tryParse(entry['at']?.toString() ?? '') ?? 0;
      return updated > 0 && at - updated > maxAgeMs;
    });
    while (map.length > maxEntries) {
      String? oldest;
      var oldestAt = 1 << 62;
      map.forEach((key, value) {
        final updated = int.tryParse(value['at']?.toString() ?? '') ?? 0;
        if (updated < oldestAt) {
          oldestAt = updated;
          oldest = key;
        }
      });
      if (oldest == null) break;
      map.remove(oldest);
    }
  }

  static Future<Map<String, Map<String, dynamic>>> _readStats() async {
    return _readMap(_statsKey);
  }

  static Future<void> _writeStats(
    Map<String, Map<String, dynamic>> stats,
  ) async {
    await _writeMap(_statsKey, stats);
  }

  static Future<Map<String, Map<String, dynamic>>> _read() {
    return _readMap(_key);
  }

  static Future<void> _write(Map<String, Map<String, dynamic>> entries) {
    return _writeMap(_key, entries);
  }

  static Future<Map<String, Map<String, dynamic>>> _readMap(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map)
            entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeMap(
    String key,
    Map<String, Map<String, dynamic>> entries,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(entries));
    } catch (_) {}
  }
}
