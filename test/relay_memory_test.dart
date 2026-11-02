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
    expect(recalled?.port, 443);
  });

  test(
    'a relay proven on an alternate listener is recalled on that port',
    () async {
      await RelayMemory.remember(
        const RelayTarget(dial: '203.0.113.7', sni: 'a.opengw.net', port: 992),
        network: cell,
      );

      expect((await RelayMemory.recall(network: cell))?.port, 992);
    },
  );

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

  test(
    'a trickle relay sinks below a relay with no throughput record',
    () async {
      const trickle = RelayTarget(
        dial: '203.0.113.20',
        sni: 'a.opengw.net',
        pingMs: 40,
      );
      const unmeasured = RelayTarget(
        dial: '203.0.113.21',
        sni: 'b.opengw.net',
        pingMs: 40,
      );

      await RelayMemory.recordThroughput(trickle.dial, 2000, network: wifi);

      final ordered = await RelayMemory.orderByHistory([
        trickle,
        unmeasured,
      ], network: wifi);
      expect(ordered.map((t) => t.dial), [unmeasured.dial, trickle.dial]);
    },
  );

  test(
    'a relay measured at zero throughput sinks below an unmeasured one',
    () async {
      const dead = RelayTarget(
        dial: '203.0.113.26',
        sni: 'a.opengw.net',
        pingMs: 30,
      );
      const unmeasured = RelayTarget(
        dial: '203.0.113.27',
        sni: 'b.opengw.net',
        pingMs: 30,
      );

      await RelayMemory.recordThroughput(dead.dial, 0, network: wifi);

      final ordered = await RelayMemory.orderByHistory([
        dead,
        unmeasured,
      ], network: wifi);
      expect(ordered.map((t) => t.dial), [unmeasured.dial, dead.dial]);
    },
  );

  test(
    'a relay that carried a fast session outranks an unmeasured one',
    () async {
      const fast = RelayTarget(
        dial: '203.0.113.22',
        sni: 'a.opengw.net',
        pingMs: 300,
      );
      const unmeasured = RelayTarget(
        dial: '203.0.113.23',
        sni: 'b.opengw.net',
        pingMs: 40,
      );

      await RelayMemory.recordThroughput(fast.dial, 900000, network: wifi);

      final ordered = await RelayMemory.orderByHistory([
        unmeasured,
        fast,
      ], network: wifi);
      expect(ordered.first.dial, fast.dial);
    },
  );

  test('throughput on one network does not reorder another', () async {
    const slow = RelayTarget(dial: '203.0.113.24', sni: 'a.opengw.net');
    const other = RelayTarget(dial: '203.0.113.25', sni: 'b.opengw.net');

    await RelayMemory.recordThroughput(slow.dial, 1000, network: wifi);

    final ordered = await RelayMemory.orderByHistory([
      slow,
      other,
    ], network: cell);
    expect(ordered.map((t) => t.dial), [slow.dial, other.dial]);
  });

  test('three failed sessions close an engine on that network', () async {
    for (var i = 0; i < 3; i++) {
      await RelayMemory.recordEngineOutcome('reality', false, network: wifi);
    }

    expect(
      await RelayMemory.engineRecentlyFailing('reality', network: wifi),
      isTrue,
    );
  });

  test('two failed sessions keep the engine in rotation', () async {
    for (var i = 0; i < 2; i++) {
      await RelayMemory.recordEngineOutcome('reality', false, network: wifi);
    }

    expect(
      await RelayMemory.engineRecentlyFailing('reality', network: wifi),
      isFalse,
    );
  });

  test('a working session reopens the engine at once', () async {
    for (var i = 0; i < 3; i++) {
      await RelayMemory.recordEngineOutcome('reality', false, network: wifi);
    }
    await RelayMemory.recordEngineOutcome('reality', true, network: wifi);

    expect(
      await RelayMemory.engineRecentlyFailing('reality', network: wifi),
      isFalse,
    );
  });

  test('engine health is scoped to the network', () async {
    for (var i = 0; i < 3; i++) {
      await RelayMemory.recordEngineOutcome('reality', false, network: cell);
    }

    expect(
      await RelayMemory.engineRecentlyFailing('reality', network: wifi),
      isFalse,
    );
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

  test('a session proof carries the dial plan across networks', () async {
    await RelayMemory.recordSessionProof(
      relay,
      engine: 'softether',
      bytesPerSecond: 400000,
      network: wifi,
    );

    final proven = await RelayMemory.provenRelays('softether');
    expect(proven, hasLength(1));
    expect(proven.single.dial, relay.dial);
    expect(proven.single.sni, relay.sni);
    expect(proven.single.countryCode, 'JP');
    expect(proven.single.source, 'proven-session');
    expect(proven.single.port, 443);
  });

  test('proofs are scoped to the engine that earned them', () async {
    await RelayMemory.recordSessionProof(relay, engine: 'reality');

    expect(await RelayMemory.provenDials('softether'), isEmpty);
    expect(await RelayMemory.provenDials('reality'), {relay.dial});
  });

  test('a proven relay outranks a lower-ping unproven one', () async {
    const proven = RelayTarget(
      dial: '203.0.113.30',
      sni: 'a.opengw.net',
      pingMs: 800,
    );
    const fastButUnproven = RelayTarget(
      dial: '203.0.113.31',
      sni: 'b.opengw.net',
      pingMs: 30,
    );

    final ordered = await RelayMemory.orderByHistory(
      [fastButUnproven, proven],
      network: cell,
      proven: {proven.dial},
    );
    expect(ordered.first.dial, proven.dial);
  });

  test('a proven relay that starts failing still sinks', () async {
    const proven = RelayTarget(dial: '203.0.113.32', sni: 'a.opengw.net');
    const fresh = RelayTarget(dial: '203.0.113.33', sni: 'b.opengw.net');

    await RelayMemory.recordDialFailure(proven.dial, network: wifi);
    await RelayMemory.recordDialFailure(proven.dial, network: wifi);
    await RelayMemory.recordDialFailure(proven.dial, network: wifi);

    final ordered = await RelayMemory.orderByHistory(
      [proven, fresh],
      network: wifi,
      proven: {proven.dial},
    );
    expect(ordered.first.dial, fresh.dial);
  });

  test('engines keep separate anchors on one network', () async {
    const reality = RelayTarget(
      dial: '165.154.63.139',
      sni: 'www.cloudflare.com',
      countryCode: 'HK',
      countryName: 'Hong Kong',
    );
    await RelayMemory.remember(relay, network: wifi, engine: 'softether');
    await RelayMemory.remember(reality, network: wifi, engine: 'reality');

    // The REALITY anchor must not evict the SoftEther relay this network
    // already proved, and a failure in one engine must not erase the other.
    await RelayMemory.forget(
      reality.dial,
      network: wifi,
      engine: 'softether',
    );
    expect((await RelayMemory.recall(network: wifi))?.dial, relay.dial);
    expect(
      (await RelayMemory.recall(network: wifi, engine: 'reality'))?.dial,
      reality.dial,
    );

    await RelayMemory.forget(
      reality.dial,
      network: wifi,
      engine: 'reality',
    );
    expect(
      await RelayMemory.recall(network: wifi, engine: 'reality'),
      isNull,
    );
    expect((await RelayMemory.recall(network: wifi))?.dial, relay.dial);
  });

  test('the network anchor is scoped to the engine too', () async {
    await RelayMemory.remember(relay, network: wifi, engine: 'reality');

    expect(await RelayMemory.recall(network: wifi, engine: 'reality'), isNotNull);
    expect(await RelayMemory.recall(network: wifi), isNull);
  });

  test('a legacy anchor without an engine tag stays SoftEther', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'bulb_relay_memory_v2',
      '{"$wifi":{"dial":"203.0.113.40","sni":"legacy.opengw.net",'
          '"port":443,"countryCode":"JP","countryName":"Japan","at":9999999999999}}',
    );

    expect((await RelayMemory.recall(network: wifi))?.dial, '203.0.113.40');
    expect(
      await RelayMemory.recall(network: wifi, engine: 'reality'),
      isNull,
    );
  });
}
