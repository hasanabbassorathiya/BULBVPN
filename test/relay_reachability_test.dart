import 'package:bulbvpn/modules/core/relay_reachability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a probe is trusted only inside its TTL', () {
    final cache = RelayReachability(ttl: const Duration(seconds: 45));
    cache.useNetwork('wifi:wlan0:192.168.1');
    final at = DateTime(2026, 10, 28, 12);
    cache.record('203.0.113.7', ok: true, at: at);

    expect(
      cache.lookup('203.0.113.7', now: at.add(const Duration(seconds: 44)))?.ok,
      isTrue,
    );
    expect(
      cache.lookup('203.0.113.7', now: at.add(const Duration(seconds: 45))),
      isNull,
    );
  });

  test('a network change throws the table away', () {
    final cache = RelayReachability();
    cache.useNetwork('wifi:wlan0:192.168.1');
    cache.record('203.0.113.7', ok: true);

    cache.useNetwork('cell:rmnet_data0');

    expect(cache.lookup('203.0.113.7'), isNull);
    expect(cache.network, 'cell:rmnet_data0');
  });

  test('a dead mark is readable and replaceable', () {
    final cache = RelayReachability();
    cache.markDead('198.51.100.9');
    expect(cache.lookup('198.51.100.9')?.ok, isFalse);

    cache.markAlive('198.51.100.9');
    expect(cache.lookup('198.51.100.9')?.ok, isTrue);
  });

  test('the cache is bounded and evicts the oldest probe', () {
    final cache = RelayReachability();
    final base = DateTime(2026, 10, 28, 12);
    for (var i = 0; i < 70; i++) {
      cache.record(
        '203.0.113.$i',
        ok: true,
        at: base.add(Duration(seconds: i)),
      );
    }

    expect(
      cache.lookup('203.0.113.0', now: base.add(const Duration(seconds: 70))),
      isNull,
    );
    expect(
      cache.lookup('203.0.113.69', now: base.add(const Duration(seconds: 70))),
      isNotNull,
    );
  });
}
