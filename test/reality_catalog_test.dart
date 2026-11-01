import 'dart:convert';

import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _entry({
  String id = 'r1',
  String host = '203.0.113.9',
  Object port = 443,
  String uuid = '055a1ce8-2a16-4a0d-a2c2-22826c9b2413',
  String key = 'Svl81isn16RPAFnjtmYw7A6TPnsEPLHuYYaJht65Rzc',
  String sni = 'www.cloudflare.com',
  String shortId = '',
  String flow = '',
  String country = 'US',
  String countryName = 'United States',
  String city = 'Ashburn',
}) {
  return {
    'id': id,
    'host': host,
    'port': port,
    'uuid': uuid,
    'public_key': key,
    'server_name': sni,
    'short_id': shortId,
    'fingerprint': 'chrome',
    'flow': flow,
    'country_code': country,
    'country_name': countryName,
    'city': city,
  };
}

void main() {
  test('bundled catalog parses into dialable relays', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final relays = await RealityCatalog.load();
    expect(relays, isNotEmpty);
    for (final relay in relays) {
      expect(relay.host, isNotEmpty);
      expect(relay.port, inInclusiveRange(1, 65535));
      expect(relay.uuid, isNotEmpty);
      expect(relay.publicKey, isNotEmpty);
      expect(relay.serverName, isNotEmpty);
    }
  });

  test('parse drops unusable entries and duplicate ids', () {
    final raw = jsonEncode({
      'relays': [
        _entry(),
        _entry(id: 'r1'),
        _entry(id: 'no-key', key: ''),
        _entry(id: 'no-sni', sni: ' '),
        _entry(id: 'bad-port', port: 'https'),
        _entry(id: 'r2', host: '198.51.100.4', port: 2053, country: 'pl'),
      ],
    });
    final relays = RealityCatalog.parse(raw);
    expect(relays.map((r) => r.id), ['r1', 'r2']);
    expect(relays.last.port, 2053);
    expect(relays.last.countryCode, 'PL');
    expect(relays.last.endpoint, '198.51.100.4:2053');
    expect(relays.first.endpoint, '203.0.113.9');
  });

  test('parse tolerates a missing or malformed relay list', () {
    expect(RealityCatalog.parse('not json'), isEmpty);
    expect(RealityCatalog.parse('{"relays": 3}'), isEmpty);
    expect(RealityCatalog.parse('{"relays": []}'), isEmpty);
  });

  test('config is one proxy-tagged VLESS outbound with REALITY stream', () {
    final relay = RealityRelay.fromJson(
      _entry(shortId: 'ca4aedd4', flow: 'xtls-rprx-vision'),
    )!;
    final config = jsonDecode(relay.toXrayConfigJson()) as Map<String, Object?>;
    final outbounds = config['outbounds'] as List;
    expect(outbounds, hasLength(1));
    final outbound = outbounds.single as Map<String, Object?>;

    // The native stats query and the DNS policy both address this exact tag.
    expect(outbound['tag'], 'proxy');
    expect(outbound['protocol'], 'vless');

    final vnext =
        ((outbound['settings'] as Map)['vnext'] as List).single as Map;
    expect(vnext['address'], '203.0.113.9');
    expect(vnext['port'], 443);
    final user = (vnext['users'] as List).single as Map;
    expect(user['id'], '055a1ce8-2a16-4a0d-a2c2-22826c9b2413');
    expect(user['encryption'], 'none');
    expect(user['flow'], 'xtls-rprx-vision');

    final stream = outbound['streamSettings'] as Map;
    expect(stream['network'], 'tcp');
    expect(stream['security'], 'reality');
    final reality = stream['realitySettings'] as Map;
    expect(reality['serverName'], 'www.cloudflare.com');
    expect(reality['publicKey'], 'Svl81isn16RPAFnjtmYw7A6TPnsEPLHuYYaJht65Rzc');
    expect(reality['shortId'], 'ca4aedd4');
    expect(reality['fingerprint'], 'chrome');
  });

  test('empty flow is omitted instead of serialized as an empty string', () {
    final relay = RealityRelay.fromJson(_entry())!;
    final config = relay.toXrayConfig();
    final outbound = (config['outbounds'] as List).single as Map;
    final vnext = (outbound['settings'] as Map)['vnext'] as List;
    final user = (vnext.single as Map)['users'] as List;
    expect((user.single as Map).containsKey('flow'), isFalse);
  });

  test('targets are community-trusted and never auto-default', () {
    final relay = RealityRelay.fromJson(_entry())!;
    final target = relay.toTarget(pingMs: 84);
    expect(target.trustTier, TrustTier.community);
    expect(target.dial, relay.host);
    expect(target.sni, relay.serverName);
    expect(target.port, relay.port);
    expect(target.countryCode, 'US');
    expect(target.pingMs, 84);
    expect(target.source, 'reality');
  });

  test('findByHost matches restored sessions only by exact host', () {
    final relays = [
      RealityRelay.fromJson(_entry())!,
      RealityRelay.fromJson(_entry(id: 'r2', host: '198.51.100.4'))!,
    ];
    expect(RealityCatalog.findByHost(relays, '198.51.100.4')?.id, 'r2');
    expect(RealityCatalog.findByHost(relays, '203.0.113.90'), isNull);
    expect(RealityCatalog.findByHost(relays, null), isNull);
  });
}
