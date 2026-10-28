import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/main/application/server_grouping.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:flutter_test/flutter_test.dart';

VpnServer _server(String ip, String country, {String short = 'XX'}) {
  return VpnServer(
    hostName: 'relay-$ip',
    ip: ip,
    countryLong: country,
    countryShort: short,
    score: 0,
    ping: 0,
    speed: 0,
    numVpnSessions: 0,
    uptime: 0,
    openVpnConfigBase64: '',
  );
}

void main() {
  final japanSlow = _server('10.0.0.3', 'Japan', short: 'JP');
  final japanFast = _server('10.0.0.1', 'Japan', short: 'JP');
  final japanLocal = _server(
    '10.0.0.2',
    'Japan (LOCAL Name: Nippon)',
    short: 'JP',
  );
  final us = _server('10.0.1.1', 'United States', short: 'US');
  final germany = _server('10.0.2.1', 'Germany', short: 'DE');
  final spain = _server('10.0.3.1', 'Spain', short: 'ES');

  test('countries are ordered by their fastest measured relay', () {
    final groups = groupServersByCountry(
      [germany, us, japanSlow, japanFast, spain, japanLocal],
      {
        japanSlow.ip: const ServerPing.ok(220),
        japanFast.ip: const ServerPing.ok(40),
        us.ip: const ServerPing.ok(90),
        // Spain only timed out: it must not outrank a reachable country.
        spain.ip: ServerPing.timeout,
      },
    );

    expect(groups.map((g) => g.countryName).toList(), [
      'Japan',
      'United States',
      'Germany',
      'Spain',
    ]);
    // Inside a country, measured relays come first in ping order; an
    // unprobed relay cannot claim a slot above a relay that answered.
    expect(groups.first.servers.map((s) => s.ip).toList(), [
      japanFast.ip,
      japanSlow.ip,
      japanLocal.ip,
    ]);
    expect(groups.first.bestPing?.ms, 40);
    // Countries without a successful probe sort alphabetically at the bottom.
    expect(groups[2].bestPing, isNull);
    expect(groups[3].bestPing, isNull);
  });

  test('locale suffix in the country name does not split the group', () {
    final groups = groupServersByCountry(
      [japanLocal, japanFast],
      {japanFast.ip: const ServerPing.ok(80)},
    );

    expect(groups, hasLength(1));
    expect(groups.single.countryName, 'Japan');
    expect(groups.single.servers, hasLength(2));
  });
}
