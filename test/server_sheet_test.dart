import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/core/reality/reality_engine.dart';
import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/server_catalog.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
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
    expect(
      find.text('4 relays · 3 countries'),
      findsOneWidget,
    );
    expect(find.text('FASTEST NOW'), findsOneWidget);
    expect(find.text('BOOTSTRAP'), findsOneWidget);
    // Public relays are disclosed as such, in the persistent notice and on
    // every row that can be picked from Fastest now.
    expect(find.textContaining('not private'), findsOneWidget);
    expect(find.text('NOT PRIVATE'), findsWidgets);

    // The country header sits below the Fastest-now rows, so the ordering
    // check uses the last occurrence of each name.
    final japanY = tester.getTopLeft(find.text('Japan').last).dy;
    final usY = tester.getTopLeft(find.text('United States').last).dy;
    final germanyY = tester.getTopLeft(find.text('Germany').last).dy;
    expect(japanY, lessThan(usY));
    expect(usY, lessThan(germanyY));

    // Relay numbering restarts inside each country. The Fastest-now rows
    // reuse the same numbers, so the shortcut never shows one relay under
    // two names.
    expect(find.text('Relay 1'), findsNWidgets(5));
    expect(find.text('Relay 2'), findsNWidgets(2));
    expect(find.text('Japan · 1.0 Mbps'), findsNWidgets(2));
    expect(find.text('Germany · 1.0 Mbps'), findsNothing);
    // Country headers show the fastest measured relay, and the dead country
    // is honest about having no answer.
    expect(find.text('45 ms'), findsWidgets);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('reality engine is opt-in and lists its community relays', (
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
              (ref) => _FakePings({
                '10.0.0.1': const ServerPing.ok(45),
              }),
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
    // Off by default: a community relay must never be dialled unasked.
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('Frankfurt, Germany'), findsNothing);
    expect(find.text('91.107.179.0:10105'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Frankfurt, Germany'), findsOneWidget);
    expect(find.text('91.107.179.0:10105'), findsOneWidget);
    // The disclosure ships with the list, not as a dismissible one-time dialog.
    expect(find.textContaining('Community relays'), findsOneWidget);
    expect(find.text('NOT PRIVATE'), findsWidgets);
  });
}
