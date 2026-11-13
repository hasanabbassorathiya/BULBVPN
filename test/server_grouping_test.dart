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

  test('a relay this device carried traffic beats a faster handshake', () {
    // The exact failure the user reported: the list put a 40 ms relay on top
    // and it carried nothing, while the 220 ms relay that actually worked sat
    // third. A proof outranks a round-trip time.
    final groups = groupServersByCountry(
      [germany, us, japanFast, japanSlow],
      {
        japanFast.ip: const ServerPing.ok(40),
        japanSlow.ip: const ServerPing.ok(220),
        us.ip: const ServerPing.ok(90),
        germany.ip: const ServerPing.ok(120),
      },
      proven: {japanSlow.ip},
    );

    expect(groups.map((g) => g.countryName).toList(), [
      'Japan',
      'United States',
      'Germany',
    ]);
    expect(groups.first.proven, isTrue);
    expect(groups.first.servers.first.ip, japanSlow.ip);
    expect(groups.first.bestPing?.ms, 40);
    expect(groups.skip(1).map((g) => g.proven), everyElement(isFalse));
  });

  test('a proven relay with no answer still leads its country', () {
    // The proof is a fact about the relay, not about this probe round. Losing
    // the ping must not demote a relay that has carried the user's traffic.
    final groups = groupServersByCountry(
      [japanFast, japanSlow],
      {japanFast.ip: const ServerPing.ok(40)},
      proven: {japanSlow.ip},
    );

    expect(groups.single.servers.map((s) => s.ip).toList(), [
      japanSlow.ip,
      japanFast.ip,
    ]);
    // The header still reports the honest measured figure, not the winner's.
    expect(groups.single.bestPing?.ms, 40);
  });

  test('no proven set leaves the old ping order untouched', () {
    final groups = groupServersByCountry(
      [japanSlow, japanFast, germany],
      {
        japanFast.ip: const ServerPing.ok(40),
        japanSlow.ip: const ServerPing.ok(220),
        germany.ip: const ServerPing.ok(10),
      },
    );

    expect(groups.map((g) => g.countryName).toList(), ['Germany', 'Japan']);
    expect(groups.last.servers.map((s) => s.ip).toList(), [
      japanFast.ip,
      japanSlow.ip,
    ]);
  });
}
