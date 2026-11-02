import 'dart:convert';

import 'package:bulbvpn/modules/core/reality/reality_health.dart';
import 'package:bulbvpn/modules/core/relay_memory.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String payload({
  String generatedAt = '',
  List<Map<String, Object?>>? probes,
}) {
  final at = generatedAt.isEmpty
      ? DateTime.now().toUtc().toIso8601String()
      : generatedAt;
  return jsonEncode({
    'schema': 1,
    'generated_at': at,
    'probes':
        probes ??
        [
          {'id': 'hk', 'ok': true, 'bytes': 65536, 'ms': 2000},
          {'id': 'ee', 'ok': false, 'bytes': 0, 'ms': 400},
        ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses a published measurements file', () {
    final health = RealityHealth.parse(payload());
    expect(health, isNotNull);
    expect(health!.byId.length, 2);
    expect(health.healthyCount, 1);
    expect(health.usable, isTrue);
    expect(health.byId['hk']!.bps, 32768);
  });

  test('rejects an unknown schema', () {
    expect(
      RealityHealth.parse(
        '{"schema":2,"generated_at":"2026-11-01T00:00:00Z","probes":[]}',
      ),
      isNull,
    );
  });

  test('rejects a payload without a usable timestamp', () {
    expect(
      RealityHealth.parse('{"schema":1,"probes":[{"id":"a","ok":true}]}'),
      isNull,
    );
  });

  test('drops absurd measurements instead of trusting them', () {
    final health = RealityHealth.parse(
      payload(
        probes: [
          {'id': 'big', 'ok': true, 'bytes': 999999999, 'ms': 10},
          {'id': 'ok', 'ok': true, 'bytes': 65536, 'ms': 1000},
        ],
      ),
    );
    expect(health, isNotNull);
    expect(health!.byId.containsKey('big'), isFalse);
    expect(health.byId.containsKey('ok'), isTrue);
  });

  test('an old measurement is not usable', () {
    final old = DateTime.now()
        .subtract(const Duration(days: 2))
        .toUtc()
        .toIso8601String();
    final health = RealityHealth.parse(payload(generatedAt: old));
    expect(health, isNotNull);
    expect(health!.usable, isFalse);
  });

  test('healthy scores beat unknown and failed scores', () {
    final health = RealityHealth.parse(payload())!;
    expect(health.scoreFor('hk'), lessThan(-40000));
    expect(health.scoreFor('ee'), greaterThan(0));
    expect(health.scoreFor('missing'), isNull);
  });

  test('measured health orders relays this phone has not tried', () async {
    SharedPreferences.setMockInitialValues({});
    final health = RealityHealth.parse(payload())!;
    const fastButUnmeasured = RelayTarget(
      dial: '203.0.113.1',
      sni: 'a.opengw.net',
      pingMs: 30,
    );
    const healthy = RelayTarget(
      dial: '203.0.113.2',
      sni: 'b.opengw.net',
      pingMs: 0,
    );

    final ordered = await RelayMemory.orderByHistory(
      [fastButUnmeasured, healthy],
      network: 'wifi:wlan0',
      extraScore: health.scoresFor(['hk']).map(
        (id, score) => MapEntry(healthy.dial, score),
      ),
    );
    expect(ordered.first.dial, healthy.dial);
  });

  test('a local failure still sinks a remotely healthy relay', () async {
    SharedPreferences.setMockInitialValues({});
    final health = RealityHealth.parse(payload())!;
    const healthy = RelayTarget(dial: '203.0.113.2', sni: 'b.opengw.net');
    const fresh = RelayTarget(dial: '203.0.113.3', sni: 'c.opengw.net');

    await RelayMemory.recordDialFailure(healthy.dial, network: 'wifi:wlan0');
    await RelayMemory.recordDialFailure(healthy.dial, network: 'wifi:wlan0');
    await RelayMemory.recordDialFailure(healthy.dial, network: 'wifi:wlan0');

    final ordered = await RelayMemory.orderByHistory(
      [healthy, fresh],
      network: 'wifi:wlan0',
      extraScore: {healthy.dial: health.scoreFor('hk')!},
    );
    expect(ordered.first.dial, fresh.dial);
  });
}
