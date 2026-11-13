import 'dart:convert';

import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/core/reality/reality_engine.dart';
import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/reality/relay_vault.dart';
import 'package:bulbvpn/modules/core/relay_memory.dart';
import 'package:bulbvpn/modules/core/server_catalog.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/main/application/relay_evidence_provider.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
import 'package:bulbvpn/shared/metered/slip_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

VpnServer _server(String ip, String country, String short) {
  return VpnServer(
    hostName: 'relay-$ip',
    ip: ip,
    countryLong: country,
    countryShort: short,
    score: 0,
    ping: 0,
    speed: 1048576,
    numVpnSessions: 3,
    uptime: 0,
    openVpnConfigBase64: '',
  );
}

class _FakeCatalog extends ServerCatalog {
  _FakeCatalog(this.servers);
  final List<VpnServer> servers;

  @override
  Future<List<VpnServer>> build() async => servers;
}

class _FakePings extends ServerPingNotifier {
  _FakePings(Map<String, ServerPing> byIp) {
    state = ServerPingState(byIp: byIp);
  }

  @override
  Future<void> ensureFresh(List<VpnServer> servers) async {}

  @override
  Future<void> pingAll(List<VpnServer> servers) async {}
}

void main() {
  testWidgets('relay sheet groups by country, fastest country on top', (
    tester,
  ) async {
    // Tall enough that the lazy list builds every country, so ordering can be
    // asserted on real painted positions.
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final japanFast = _server('10.0.0.1', 'Japan', 'JP');
    final japanSlow = _server('10.0.0.2', 'Japan', 'JP');
    final us = _server('10.0.1.1', 'United States', 'US');
    final germany = _server('10.0.2.1', 'Germany', 'DE');

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => ProviderScope(
          overrides: [
            serversProvider.overrideWith(
              () => _FakeCatalog([germany, us, japanSlow, japanFast]),
            ),
            serverPingProvider.overrideWith(
              (ref) => _FakePings({
                japanFast.ip: const ServerPing.ok(45),
                japanSlow.ip: const ServerPing.ok(210),
                us.ip: const ServerPing.ok(95),
                germany.ip: ServerPing.timeout,
              }),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: ServerSheet()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('4 relays · 3 countries'), findsOneWidget);
    expect(find.text('BOOTSTRAP'), findsOneWidget);
    // Public relays are disclosed as such in a notice that is not dismissible.
    expect(find.textContaining('not private'), findsOneWidget);
    expect(find.text('NOT PRIVATE'), findsWidgets);

    // A country band is a heading, and the plate prints headings in caps.
    final japanY = tester.getTopLeft(find.text('JAPAN').last).dy;
    final usY = tester.getTopLeft(find.text('UNITED STATES').last).dy;
    final germanyY = tester.getTopLeft(find.text('GERMANY').last).dy;
    expect(japanY, lessThan(usY));
    expect(usY, lessThan(germanyY));

    // Relay numbering restarts inside each country.
    expect(find.text('Relay 1'), findsNWidgets(3));
    expect(find.text('Relay 2'), findsOneWidget);
    // The self-reported VPN Gate figure is gone: it described a server's own
    // claim about a network this phone had never crossed.
    expect(find.textContaining('Mbps'), findsNothing);

    // Every figure names the instrument that produced it. A TLS round trip is
    // printed as `45 ms / TLS only`, never as a speed, and a relay that never
    // answered is honest about that instead of showing a stale number.
    expect(find.text('45 ms'), findsWidgets);
    expect(find.text('TLS only'), findsWidgets);
    expect(find.text('no handshake'), findsWidgets);
    // The transport and the address are two lines of print, so neither one is
    // shrunk below the card's measured size to fit the column.
    expect(find.text('SoftEther SSL-VPN'), findsWidgets);
    expect(find.text('10.0.0.1'), findsOneWidget);
    // The Auto row names the engine this platform actually dials. Android
    // exits the REALITY/XHTTP loop with a verdict, so a row that still read
    // `SoftEther SSL-VPN` would promise a fallback that no longer exists.
    final autoRow = find.ancestor(
      of: find.text('AUTO'),
      matching: find.byType(SlipRow),
    );
    expect(autoRow, findsOneWidget);
    expect(
      find.descendant(of: autoRow, matching: find.text('REALITY/XHTTP')),
      findsOneWidget,
    );
  });

  testWidgets('a relay this device carried traffic leads its country', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // 10.0.0.2 has the slowest handshake of the three and still leads, because
    // this phone completed a session through it. That is the ranking the old
    // list got backwards.
    final fast = _server('10.0.0.1', 'United States', 'US');
    final proven = _server('10.0.0.2', 'Japan', 'JP');
    final dead = _server('10.0.0.3', 'Germany', 'DE');

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => ProviderScope(
          overrides: [
            serversProvider.overrideWith(
              () => _FakeCatalog([dead, proven, fast]),
            ),
            serverPingProvider.overrideWith(
              (ref) => _FakePings({
                fast.ip: const ServerPing.ok(38),
                proven.ip: const ServerPing.ok(260),
                dead.ip: ServerPing.timeout,
              }),
            ),
            relayEvidenceProvider.overrideWith(
              (ref) async => RelayEvidence(
                proven: {
                  proven.ip: SessionProof(
                    dial: proven.ip,
                    bytesPerSecond: 900000,
                    at: DateTime.now(),
                  ),
                },
                health: null,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: ServerSheet()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // No parallel list of the same relays: the proof is printed in the row and
    // decides where the row sits, so a relay is never named twice.
    expect(find.text('CARRIED YOUR TRAFFIC BEFORE'), findsNothing);
    expect(find.text('879 KB/s'), findsOneWidget);
    expect(find.text('you · now'), findsOneWidget);

    // Japan holds the slowest handshake on screen and is still the first
    // country, because a session completed there.
    expect(
      tester.getTopLeft(find.text('JAPAN')).dy,
      lessThan(tester.getTopLeft(find.text('UNITED STATES')).dy),
    );
    expect(find.text('1 relay · yours'), findsOneWidget);
    // The proven relay leads its country.
    expect(find.text('Relay 1'), findsNWidgets(3));
    expect(find.textContaining('Mbps'), findsNothing);
  });

  testWidgets('reality is on by default and its switch gates the pool', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    RealitySettingsStore.resetCache();
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const relay = RealityRelay(
      id: 'community-de-2',
      host: '91.107.179.0',
      port: 10105,
      uuid: 'ad3f4a0a-a89f-498e-9869-a93c8fa185b1',
      publicKey: 'PFC3JN1er1JE2vAemwRhNjewz8I4NUWP4XHf2Dza4Es',
      serverName: 'play.google.com',
      shortId: '12e321badd07906e',
      countryCode: 'DE',
      countryName: 'Germany',
      city: 'Frankfurt',
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => ProviderScope(
          overrides: [
            serversProvider.overrideWith(
              () => _FakeCatalog([_server('10.0.0.1', 'Japan', 'JP')]),
            ),
            serverPingProvider.overrideWith(
              (ref) => _FakePings({'10.0.0.1': const ServerPing.ok(45)}),
            ),
            realitySupportedProvider.overrideWithValue(true),
            realityRelaysProvider.overrideWith((ref) async => [relay]),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: ServerSheet()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('CENSORSHIP-RESISTANT'), findsOneWidget);
    expect(find.text('TLS + REALITY'), findsOneWidget);
    // On by default: the network that blackholes the other protocol is the one
    // that needs this engine, so a device that never chose anything must not be
    // stranded on the path that cannot complete. The switch still gates the
    // pool, and it is a printed slip affordance, so it is keyed, not typed.
    expect(find.byKey(const ValueKey('reality-toggle')), findsOneWidget);
    expect(find.text('Frankfurt, Germany'), findsOneWidget);
    expect(find.textContaining('91.107.179.0:10105'), findsOneWidget);
    expect(find.text('VLESS · TCP · REALITY'), findsOneWidget);
    // The disclosure ships with the list, not as a dismissible one-time dialog.
    expect(find.textContaining('Community relays'), findsOneWidget);
    expect(find.text('NOT PRIVATE'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('reality-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Frankfurt, Germany'), findsNothing);
    expect(find.textContaining('91.107.179.0:10105'), findsNothing);
  });

  testWidgets("a server the user pasted is listed with the pool switched off", (
    tester,
  ) async {
    // The vault is seeded through preferences rather than a provider override,
    // so this asserts the real composition: an imported server reaches the
    // sheet through the same relay list the dial order reads.
    const stored = {
      'id': 'Home-1',
      'host': '203.0.113.7',
      'port': 2087,
      'link':
          'trojan://s3cret@203.0.113.7:2087?security=tls'
          '&sni=cdn.example.net&type=grpc&serviceName=video#Home-1',
      'private': true,
      'country_name': 'Home-1',
    };
    SharedPreferences.setMockInitialValues({
      'bulb_relay_vault_v1': jsonEncode([stored]),
      // The pool deliberately off, so the only relay on screen is one the user
      // named. Consent cannot be what puts an imported server in the list.
      'bulb_reality_v1': '{"enabled":false}',
    });
    RelayVault.resetCache();
    RealitySettingsStore.resetCache();
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => ProviderScope(
          overrides: [
            serversProvider.overrideWith(
              () => _FakeCatalog([_server('10.0.0.1', 'Japan', 'JP')]),
            ),
            serverPingProvider.overrideWith(
              (ref) => _FakePings({'10.0.0.1': const ServerPing.ok(45)}),
            ),
            realitySupportedProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: ServerSheet()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Own servers need no consent switch: the user named the address.
    expect(find.text('YOUR SERVERS'), findsOneWidget);
    expect(find.text('Home-1'), findsOneWidget);
    expect(find.text('YOURS'), findsOneWidget);
    expect(find.textContaining('203.0.113.7:2087'), findsOneWidget);
    // The shape is read off the config, so a grpc profile does not claim to be
    // the REALITY tunnel the bundled pool uses.
    expect(find.text('Trojan · gRPC · TLS'), findsOneWidget);
    expect(find.textContaining('Add your own server'), findsOneWidget);
    // Engine off: the community pool stays behind its switch. (The bootstrap
    // relays wear their own NOT PRIVATE pill, so the badge is not the tell —
    // the pool's disclosure is.)
    expect(find.text('Frankfurt, Germany'), findsNothing);
    expect(find.textContaining('Community relays'), findsNothing);

    // The remove key is printed in the destination column, not an icon.
    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle();

    expect(find.text('Home-1'), findsNothing);
  });
}
