import 'package:bulbvpn/modules/core/relay_memory.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const wifi = 'wifi:wlan0:192.168.1';
  const cell = 'cell:rmnet_data0';

  const relay = RelayTarget(
    dial: '203.0.113.7',
    sni: 'public-vpn-1.opengw.net',
    countryCode: 'JP',
    countryName: 'Japan',
    pingMs: 42,
    source: 'softether',
  );

  test('remembers a relay per network', () async {
    await RelayMemory.remember(relay, network: wifi);

    final recalled = await RelayMemory.recall(network: wifi);
    expect(recalled?.dial, relay.dial);
    expect(recalled?.sni, relay.sni);
    expect(recalled?.countryCode, 'JP');
    expect(recalled?.countryName, 'Japan');
    expect(recalled?.source, 'network-memory');

    // A relay proven on Wi-Fi must not be the first pick on mobile data.
    expect(await RelayMemory.recall(network: cell), isNull);
  });

  test('an OpenVPN-only entry gets a dialable SNI', () async {
    await RelayMemory.remember(
      const RelayTarget(dial: '198.51.100.9', sni: ''),
      network: cell,
    );

    final recalled = await RelayMemory.recall(network: cell);
    expect(recalled?.sni, '198.51.100.9');
  });

  test('forget removes only the relay it names', () async {
    await RelayMemory.remember(relay, network: wifi);

    await RelayMemory.forget('198.51.100.9', network: wifi);
    expect((await RelayMemory.recall(network: wifi))?.dial, relay.dial);

    await RelayMemory.forget(relay.dial, network: wifi);
    expect(await RelayMemory.recall(network: wifi), isNull);
  });

  test('a newer success replaces the entry for the same network', () async {
    await RelayMemory.remember(relay, network: wifi);
    await RelayMemory.remember(
      relay.copyWith(dial: '203.0.113.8', sni: 'public-vpn-2.opengw.net'),
      network: wifi,
    );

    final recalled = await RelayMemory.recall(network: wifi);
    expect(recalled?.dial, '203.0.113.8');
    expect(recalled?.sni, 'public-vpn-2.opengw.net');
  });

  test('probe history sinks a relay that just failed', () async {
    const good = RelayTarget(dial: '203.0.113.10', sni: 'a.opengw.net');
    const dead = RelayTarget(dial: '203.0.113.11', sni: 'b.opengw.net');

    await RelayMemory.recordProbes({
      good.dial: true,
      dead.dial: false,
    }, network: wifi);

    final ordered = await RelayMemory.orderByHistory([
      dead,
      good,
    ], network: wifi);
    expect(ordered.map((t) => t.dial), [good.dial, dead.dial]);
  });

  test('dial failure is recorded like a failed probe', () async {
    const good = RelayTarget(dial: '203.0.113.10', sni: 'a.opengw.net');
    const dead = RelayTarget(dial: '203.0.113.11', sni: 'b.opengw.net');

    await RelayMemory.recordProbes({good.dial: true}, network: wifi);
    await RelayMemory.recordDialFailure(dead.dial, network: wifi);

    final ordered = await RelayMemory.orderByHistory([
      dead,
      good,
    ], network: wifi);
    expect(ordered.first.dial, good.dial);
  });

  test('history on one network does not reorder another', () async {
    const a = RelayTarget(dial: '203.0.113.10', sni: 'a.opengw.net');
    const b = RelayTarget(dial: '203.0.113.11', sni: 'b.opengw.net');

    await RelayMemory.recordProbes({
      a.dial: false,
      b.dial: true,
    }, network: wifi);

    final ordered = await RelayMemory.orderByHistory([a, b], network: cell);
    expect(ordered.map((t) => t.dial), [a.dial, b.dial]);
  });
}
