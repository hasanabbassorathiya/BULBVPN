import 'package:flutter_test/flutter_test.dart';

import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';

VpnServer _server(int i) => VpnServer(
  hostName: 'vpn$i.example',
  ip: '203.0.113.$i',
  countryLong: 'Testland',
  countryShort: 'ts',
  score: 1,
  ping: 0,
  speed: 0,
  numVpnSessions: 1,
  uptime: 0,
  openVpnConfigBase64: '',
);

void main() {
  // The home screen and the server sheet both watch this provider, so every
  // emission is a full rebuild of a 106-row list plus the connect face. One
  // emission per measured relay meant one tap on "Measure" cost ~106 rebuilds.
  test('a full sweep emits a bounded number of states, not one per relay',
      () async {
    final servers = List.generate(106, _server);
    final notifier = ServerPingNotifier(
      probe: (server) async => ServerPing.ok(server.ip.length),
    );
    addTearDown(notifier.dispose);

    var emissions = 0;
    notifier.addListener((_) => emissions++);
    await notifier.pingAll(servers);

    expect(notifier.state.byIp.length, 106);
    expect(emissions, lessThan(20), reason: 'one sweep must not rebuild the '
        'screen once per relay');
  });

  test('every relay still lands in the published map', () async {
    final servers = List.generate(106, _server);
    final notifier = ServerPingNotifier(
      probe: (server) async => ServerPing.ok(40),
    );
    addTearDown(notifier.dispose);

    await notifier.pingAll(servers);

    expect(
      notifier.state.byIp.values.where((p) => p.status == PingStatus.ok).length,
      106,
    );
    for (final server in servers) {
      expect(notifier.state.byIp[server.ip]?.ms, 40);
    }
  });

}
