import 'dart:convert';
import 'dart:io';

import 'package:bulbvpn/modules/core/reality/reality_health.dart';
import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
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

  test('a stale measurement says where not to go, never where to go first', () {
    final old = DateTime.now()
        .subtract(const Duration(days: 5))
        .toUtc()
        .toIso8601String();
    final health = RealityHealth.parse(payload(generatedAt: old))!;
    final fresh = RealityHealth.parse(payload())!;

    // Young enough to promote: the control that keeps this test honest. If the
    // age gate were missing, the two stale expectations below would fail.
    expect(fresh.scoreFor('hk'), isNotNull);
    // Four of eight relays the Action called healthy on 2026-11-01 were dead
    // when probe_reality.py was re-run on 2026-11-06, so a five-day-old "ok"
    // must not buy a relay the first dial.
    expect(health.scoreFor('hk'), isNull);
    // The failure still holds: a dead VPS is rarely wrong within a week, and
    // avoiding it costs nothing if it came back.
    expect(health.scoreFor('ee'), isNotNull);
    expect(health.scoreFor('ee')!, greaterThan(0));
  });

  /// The copy sealed into the build cannot refresh itself, so a two-day-old
  /// probe still ranks the pool an installer is about to dial. The remote bar
  /// stays where it was, because a published file is expected to be hours old.
  test('a build-sealed measurement outlives the published bar, not forever', () {
    final twoDays = DateTime.now()
        .subtract(const Duration(days: 2))
        .toUtc()
        .toIso8601String();
    final month = DateTime.now()
        .subtract(const Duration(days: 30))
        .toUtc()
        .toIso8601String();
    expect(RealityHealth.parse(payload(generatedAt: twoDays))!.usable, isFalse);
    expect(
      RealityHealth.parse(payload(generatedAt: twoDays))!.usableAsBundledPrior,
      isTrue,
    );
    expect(
      RealityHealth.parse(payload(generatedAt: month))!.usableAsBundledPrior,
      isFalse,
    );
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

  /// The two artifacts a fresh install reads, checked against each other rather
  /// than against a fixture. Relay ids are the join key: rename one in the
  /// catalog and its measurement stops applying in silence, which is how a
  /// first press ends up dialling a decommissioned VPS.
  test('the shipped health file ranks the pool that ships beside it', () async {
    SharedPreferences.setMockInitialValues({});
    final catalog = RealityCatalog.parse(
      File(RealityCatalog.assetPath).readAsStringSync(),
    );
    final health = RealityHealth.parse(
      File('data/reality_health.json').readAsStringSync(),
    );
    expect(catalog, isNotEmpty);
    expect(health, isNotNull);
    expect(
      health!.byId.keys.toSet(),
      catalog.map((relay) => relay.id).toSet(),
    );
    // Scores are keyed by host, so one host behind two relays would hand both
    // the same rank.
    expect(
      catalog.map((relay) => relay.host).toSet().length,
      catalog.length,
      reason: 'two community relays share a host',
    );

    // The refresher ships only relays that passed the data gate, so a fresh
    // bundle has nothing to demote. The 3-hourly probe republishes failures
    // against the same ids later; when that file lands, every measured-dead
    // relay must sink below every measured-alive one.
    final dead = catalog
        .where((relay) => !health.byId[relay.id]!.ok)
        .map((relay) => relay.id)
        .toSet();
    final ordered = await RelayMemory.orderByHistory(
      [for (final relay in catalog) relay.toTarget()],
      network: 'wifi:wlan0',
      extraScore: {
        for (final relay in catalog)
          if (health.scoreFor(relay.id) != null)
            relay.host: health.scoreFor(relay.id)!,
      },
    );
    final rank = {
      for (var i = 0; i < ordered.length; i++) ordered[i].dial: i,
    };
    expect(ordered.length, catalog.length, reason: 'ordering dropped a relay');
    final hostOf = {for (final relay in catalog) relay.id: relay.host};
    for (final alive in catalog.where((relay) => !dead.contains(relay.id))) {
      for (final gone in dead) {
        expect(
          rank[hostOf[alive.id]],
          lessThan(rank[hostOf[gone]]!),
          reason: '$gone was measured dead yet still outranks ${alive.id}',
        );
      }
    }
    // Non-vacuity for the all-healthy bundle: the measured throughput bonus
    // must still move the order, or the join key is silently doing nothing.
    if (dead.isEmpty) {
      final scored = catalog
          .where((relay) => health.scoreFor(relay.id) != null)
          .toList();
      expect(scored, isNotEmpty, reason: 'no health score applies to the pool');
      final fastest = scored.reduce(
        (a, b) => health.byId[a.id]!.bps >= health.byId[b.id]!.bps ? a : b,
      );
      final baseline = await RelayMemory.orderByHistory(
        [for (final relay in catalog) relay.toTarget()],
        network: 'wifi:wlan0',
      );
      final baselineRank = {
        for (var i = 0; i < baseline.length; i++) baseline[i].dial: i,
      };
      expect(
        rank[fastest.host],
        lessThanOrEqualTo(baselineRank[fastest.host]!),
        reason: 'the fastest measured relay did not gain rank from its score',
      );
    }
  });
}
