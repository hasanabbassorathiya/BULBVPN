import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
import 'package:bulbvpn/modules/core/server_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

void main() {
  testWidgets('relay sheet groups by country, fastest country on top', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final japanFast = _server('10.0.0.1', 'Japan', 'JP');
    final japanSlow = _server('10.0.0.2', 'Japan', 'JP');
    final us = _server('10.0.1.1', 'United States', 'US');
    final germany = _server('10.0.2.1', 'Germany', 'DE');

    await tester.pumpWidget(
      ProviderScope(
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
        child: const MaterialApp(home: Scaffold(body: ServerSheet())),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('4 relays · 3 countries · lowest ping first'),
      findsOneWidget,
    );

    final japanY = tester.getTopLeft(find.text('Japan')).dy;
    final usY = tester.getTopLeft(find.text('United States')).dy;
    final germanyY = tester.getTopLeft(find.text('Germany')).dy;
    expect(japanY, lessThan(usY));
    expect(usY, lessThan(germanyY));

    // Relay numbering restarts inside each country.
    expect(find.text('Relay 1'), findsNWidgets(3));
    expect(find.text('Relay 2'), findsOneWidget);
    // Country headers show the fastest measured relay, and the dead country
    // is honest about having no answer.
    expect(find.text('45 ms'), findsWidgets);
    expect(find.text('—'), findsWidgets);
  });
}
