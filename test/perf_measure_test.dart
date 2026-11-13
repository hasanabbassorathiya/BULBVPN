// Scratch host-side measurement of the two candidate "UI heavy lifting" storms.
// Run: flutter test test/perf_measure_test.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bulbvpn/modules/core/vpn_gate_candidates.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';

void main() {
  test('measure', () {
    final raw = File('data/vpngate.json').readAsStringSync();
    print('catalog bytes: ${raw.length}');

    final t0 = Stopwatch()..start();
    final decoded = json.decode(raw) as List;
    t0.stop();
    final t0c = Stopwatch()..start();
    json.decode('[]');
    t0c.stop();
    print('json.decode catalog: ${t0.elapsedMilliseconds} ms '
        '(control "[]": ${t0c.elapsedMicroseconds} us)');

    final models = decoded
        .whereType<Map>()
        .map((r) => VpnServer.fromJson(Map<String, dynamic>.from(r)))
        .where((s) => s.ip.isNotEmpty && s.hostName.isNotEmpty)
        .toList();
    print('rows: ${models.length}');

    final t1 = Stopwatch()..start();
    final again = decoded
        .whereType<Map>()
        .map((r) => VpnServer.fromJson(Map<String, dynamic>.from(r)))
        .where((s) => s.ip.isNotEmpty && s.hostName.isNotEmpty)
        .toList();
    t1.stop();
    print('VpnServer.fromJson x${again.length}: ${t1.elapsedMilliseconds} ms');

    final b64Total = models.fold<int>(
      0,
      (a, s) => a + s.openVpnConfigBase64.length,
    );
    print('openvpn b64 total: $b64Total bytes '
        '(avg ${b64Total ~/ models.length})');

    final t2 = Stopwatch()..start();
    var built = 0;
    for (final s in models) {
      if (s.openVpnConfigBase64.isEmpty) continue;
      final d = decodeOvpn(s.openVpnConfigBase64);
      if (d == null || !d.contains('<ca>')) continue;
      if (Candidate.fromConfig(configForCurrentEngine(d)) != null) built++;
    }
    t2.stop();
    print('config parse x${models.length} (built $built): '
        '${t2.elapsedMilliseconds} ms');

    final t3 = Stopwatch()..start();
    for (final s in models) {
      final d = decodeOvpn(s.openVpnConfigBase64);
      if (d == null) continue;
      ensureIcsOpenVpnCompat(ensureAuthUserPass(d));
    }
    t3.stop();
    print('ANDROID branch x${models.length}: ${t3.elapsedMilliseconds} ms');

    final t4 = Stopwatch()..start();
    for (final s in models.take(1)) {
      final d = decodeOvpn(s.openVpnConfigBase64);
      if (d == null) continue;
      ensureIcsOpenVpnCompat(ensureAuthUserPass(d));
    }
    t4.stop();
    print('control 1 row: ${t4.elapsedMicroseconds} us');

    final byIp = <String, ServerPing>{
      for (final s in models) s.ip: ServerPing.pending,
    };
    final t5 = Stopwatch()..start();
    for (var i = 0; i < models.length; i++) {
      final cur = Map<String, ServerPing>.from(byIp);
      cur[models[i].ip] = ServerPing.ok(100 + i);
      byIp
        ..clear()
        ..addAll(cur);
      sortByMeasuredPing(models, byIp);
    }
    t5.stop();
    print('per-probe copy+sort x${models.length}: ${t5.elapsedMilliseconds} ms');

    final t6 = Stopwatch()..start();
    sortByMeasuredPing(models, byIp);
    t6.stop();
    print('control 1 copy+sort: ${t6.elapsedMicroseconds} us');
  });
}
