import 'package:bulbvpn/modules/core/relay_port_agility.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const relays = <RelayTarget>[
    RelayTarget(dial: '203.0.113.7', sni: 'a.opengw.net', countryCode: 'JP'),
    RelayTarget(dial: '203.0.113.8', sni: 'b.opengw.net', countryCode: 'US'),
    RelayTarget(dial: '203.0.113.9', sni: 'c.opengw.net'),
  ];

  test('alternate ports keep the relay identity and only change the port', () {
    final alternates = alternatePortTargets(relays, const [992]);

    expect(alternates, hasLength(3));
    expect(alternates.first.dial, '203.0.113.7');
    expect(alternates.first.sni, 'a.opengw.net');
    expect(alternates.first.countryCode, 'JP');
    expect(alternates.first.port, 992);
    expect(alternates.first.endpoint, '203.0.113.7:992');
  });

  test('each alternate port is capped on its own', () {
    final alternates = alternatePortTargets(
      relays,
      const [992, 1194],
      perPort: 2,
    );

    expect(alternates.map((t) => '${t.dial}:${t.port}'), [
      '203.0.113.7:992',
      '203.0.113.8:992',
      '203.0.113.7:1194',
      '203.0.113.8:1194',
    ]);
  });

  test('a relay already dialled on the alternate port is not repeated', () {
    final onMail = <RelayTarget>[
      const RelayTarget(dial: '203.0.113.7', sni: 'a.opengw.net', port: 992),
      ...relays,
    ];

    final alternates = alternatePortTargets(onMail, const [992]);

    expect(alternates.map((t) => t.dial), ['203.0.113.8', '203.0.113.9']);
  });

  test('reachability is tracked per listener, not per host', () {
    expect(
      relayReachabilityKey('203.0.113.7', 443),
      '203.0.113.7:443',
    );
    expect(
      relayReachabilityKey('203.0.113.7', 992),
      isNot(relayReachabilityKey('203.0.113.7', 443)),
    );
  });

  test('the alternate list excludes the primary HTTPS port', () {
    expect(softEtherAlternatePorts, isNot(contains(443)));
    expect(softEtherAlternatePorts, containsAll(<int>[992, 1194]));
  });
}
