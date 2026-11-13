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
  String fingerprint = 'chrome',
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
    'fingerprint': fingerprint,
    'flow': flow,
    'country_code': country,
    'country_name': countryName,
    'city': city,
  };
}

// The connect loop now dials one relay at several ClientHello shapes, so a
// shape name that the bundled core does not recognise is not a formatting
// problem: Xray's GetFingerprint returns nil for an unknown name and the
// dial dies with "REALITY: failed to get fingerprint" before any packet
// leaves the phone. These are the names from that table, transcribed from
// transport/internet/tls/tls.go at Xray-core v26.10.21 — the release the
// bundled xray-android 26.10.17-protect1 is built from.
// The connect loop now dials one relay at several ClientHello shapes, so a
// shape name that the bundled core does not recognise is not a formatting
// problem: Xray's GetFingerprint returns nil for an unknown name and the
// dial dies with "REALITY: failed to get fingerprint" before any packet
// leaves the phone. These are the names from that table, transcribed from
// transport/internet/tls/tls.go at Xray-core v26.10.21 — the release the
// bundled xray-android 26.10.17-protect1 is built from.
const _coreFingerprints = <String>{
  'chrome',
  'firefox',
  'safari',
  'ios',
  'android',
  'edge',
  '360',
  'qq',
  'random',
  'randomized',
  'randomizednoalpn',
  'unsafe',
  'hellofirefox_120',
  'hellofirefox_148',
  'hellochrome_120',
  'hellochrome_131',
  'hellochrome_133',
  'helloios_13',
  'helloios_14',
  'helloedge_106',
  'hellosafari_26_3',
  'hello360_11_0',
  'helloqq_11_1',
  'hellogolang',
  'hellorandomized',
  'hellorandomizedalpn',
  'hellorandomizednoalpn',
  'hellofirefox_auto',
  'hellofirefox_55',
  'hellofirefox_56',
  'hellofirefox_63',
  'hellofirefox_65',
  'hellofirefox_99',
  'hellofirefox_102',
  'hellofirefox_105',
  'hellochrome_auto',
  'hellochrome_58',
  'hellochrome_62',
  'hellochrome_70',
  'hellochrome_72',
  'hellochrome_83',
  'hellochrome_87',
  'hellochrome_96',
  'hellochrome_100',
  'hellochrome_102',
  'hellochrome_106_shuffle',
  'helloios_auto',
  'helloios_11_1',
  'helloios_12_1',
  'helloandroid_11_okhttp',
  'helloedge_85',
  'helloedge_auto',
  'hellosafari_16_0',
  'hellosafari_auto',
  'hello360_auto',
  'hello360_7_5',
  'helloqq_auto',
  'hellochrome_100_psk',
  'hellochrome_112_psk_shuf',
  'hellochrome_114_padding_psk_shuf',
  'hellochrome_115_pq',
  'hellochrome_115_pq_psk',
  'hellochrome_120_pq',
};

void main() {
  test('bundled catalog parses into dialable relays', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final relays = await RealityCatalog.load();
    expect(relays, isNotEmpty);
    for (final relay in relays) {
      expect(relay.host, isNotEmpty);
      expect(relay.port, inInclusiveRange(1, 65535));
      if (relay.link != null) {
        expect(relay.link, isNotEmpty);
      } else {
        expect(relay.uuid, isNotEmpty);
        expect(relay.publicKey, isNotEmpty);
        expect(relay.serverName, isNotEmpty);
      }
      // Every shipped entry must survive the config builder — a link the
      // bundled parser rejects would die on the phone, not in CI.
      final config = relay.toXrayConfig();
      final outbounds = config['outbounds'] as List;
      expect(outbounds, hasLength(1));
      expect((outbounds.single as Map)['tag'], 'proxy');
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

  test('catalog entries may carry a share link instead of REALITY fields', () {
    // XHTTP has no structured representation in this class; the link is the
    // profile, exactly as it is for an imported server. The generator emits
    // host/port beside it so ordering and dedupe never have to parse a URL.
    const link =
        'vless://111e808e-3628-42a4-b17f-5e3b0f4d2a55'
        '@203.0.113.7:443?type=xhttp&security=tls&sni=www.example.com'
        '&path=%2Fxhttp&host=www.example.com#DE%20xhttp';
    final relay = RealityRelay.fromJson({
      'id': 'x1',
      'host': '203.0.113.7',
      'port': 443,
      'link': link,
      'country_code': 'de',
      'country_name': 'Germany',
    });
    expect(relay, isNotNull);
    expect(relay!.link, link);
    expect(relay.countryCode, 'DE');
    expect(relay.private, isFalse);
    // A link is dialled exactly as published: one dial, no hello rewriting.
    final dials = RealityRelay.dialPlan([relay]);
    expect(identical(dials.single, relay), isTrue);
    expect(relay.toTarget().trustTier, TrustTier.community);
  });

  test('a catalog link entry can never claim the private trust tier', () {
    // The vault honors `private` because the user named that address; the
    // bundled asset is community-contributed no matter what a generator or a
    // tampered refresh writes into it.
    final relay = RealityRelay.fromJson({
      'id': 'x2',
      'host': '203.0.113.8',
      'port': 443,
      'link': 'vless://uuid@203.0.113.8:443?type=xhttp#x',
      'private': true,
    })!;
    expect(relay.private, isFalse);
    expect(relay.toTarget().trustTier, TrustTier.community);
  });

  test('an entry with neither a link nor REALITY fields is still dropped', () {
    expect(
      RealityRelay.fromJson({'id': 'empty', 'host': '203.0.113.9', 'port': 443}),
      isNull,
    );
    expect(
      RealityRelay.fromJson({'id': 'no-host', 'link': 'vless://x@y:443#z'}),
      isNull,
    );
  });

  test('a countryless community relay never borrows the private label', () {
    final community = RealityRelay.fromJson(_entry(country: '', countryName: ''))!;
    expect(community.displayName, 'Community relay');
    const imported = RealityRelay(
      id: 'home',
      host: '203.0.113.9',
      port: 443,
      uuid: 'u',
      publicKey: '',
      serverName: '',
      private: true,
    );
    expect(imported.displayName, 'Private relay');
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

  test('every hello shape the ladder dials is a name the core knows', () {
    expect(RealityRelay.handshakeLadder, isNotEmpty);
    for (final shape in RealityRelay.handshakeLadder) {
      expect(
        _coreFingerprints,
        contains(shape),
        reason:
            '$shape would fail REALITY dialling with "failed to get '
            'fingerprint" on every relay',
      );
    }
    // The shapes a fingerprint can take are not all usable: the core refuses a
    // hello with no TLS 1.3 ("REALITY handshake cannot establish"), which
    // excludes the android/360 presets measured in tool/hellosize.
    for (final shape in RealityRelay.handshakeLadder) {
      expect(const {
        'android',
        'helloandroid_11_okhttp',
        '360',
        'hello360_11_0',
      }, isNot(contains(shape)));
    }
  });

  test('a wide hello is re-dialled narrow, and only the hello changes', () {
    final relay = RealityRelay.fromJson(_entry(fingerprint: 'chrome'))!;
    expect(relay.helloIsWide, isTrue);

    final narrow = relay.withHelloShape('hellochrome_120');
    expect(narrow.helloIsWide, isFalse);

    Map<String, Object?> reality(RealityRelay r) =>
        ((r.toXrayConfig()['outbounds']! as List).single
                as Map<String, Object?>)['streamSettings']!
            as Map<String, Object?>;
    final before = reality(relay)['realitySettings']! as Map<String, Object?>;
    final after = reality(narrow)['realitySettings']! as Map<String, Object?>;
    expect(before['fingerprint'], 'chrome');
    expect(after['fingerprint'], 'hellochrome_120');
    // The address, key and camouflage target are the relay's identity; trying a
    // second shape must not look like trying a second server.
    expect(after['serverName'], before['serverName']);
    expect(after['publicKey'], before['publicKey']);
    expect(narrow.dialKey, relay.dialKey);
    expect(narrow.id, relay.id);
  });

  test('a relay whose author already publishes a narrow hello stays as-is', () {
    final relay = RealityRelay.fromJson(
      _entry(fingerprint: 'hellochrome_120'),
    )!;
    expect(relay.helloIsWide, isFalse);
  });

  test(
    'the head relay is dialled at every ladder shape before the next IP',
    () {
      final relays = [
        RealityRelay.fromJson(_entry())!,
        RealityRelay.fromJson(_entry(id: 'r2', host: '198.51.100.4'))!,
      ];
      final dials = RealityRelay.dialPlan(relays);
      expect(dials.take(3).map((d) => d.fingerprint).toList(), [
        'hellochrome_120',
        'ios',
        'hellochrome_106_shuffle',
      ]);
      // Shape is systemic, address is per-relay: the second address is still
      // reached, but with one narrow shape plus the published one rather than
      // the whole ladder again.
      expect(dials.length, 6);
      expect(dials[3].host, '203.0.113.9');
      expect(dials[3].fingerprint, 'chrome');
      expect(dials[4].host, '198.51.100.4');
      expect(dials[4].fingerprint, 'hellochrome_120');
      expect(dials[5].fingerprint, 'chrome');
    },
  );

  test('a narrow published hello is not re-dialled as itself twice', () {
    final relay = RealityRelay.fromJson(
      _entry(fingerprint: 'hellochrome_120'),
    )!;
    final dials = RealityRelay.dialPlan([relay, relay]);
    expect(dials.map((d) => d.fingerprint).toSet(), {
      'hellochrome_120',
      'ios',
      'hellochrome_106_shuffle',
    });
  });

  test('imported links are dialled exactly as their author wrote them', () {
    final link =
        'vless://111e808e-3628-42a4-b17f-5e3b0f4d2a55'
        '@203.0.113.9:443?security=reality&sni=www.example.com'
        '&pbk=Svl81isn16RPAFnjtmYw7A6TPnsEPLHuYYaJht65Rzc'
        '&fp=chrome&flow=xtls-rprx-vision&type=tcp#Home';
    final relay = RealityRelay(
      id: 'home',
      host: '203.0.113.9',
      port: 443,
      uuid: '111e808e-3628-42a4-b17f-5e3b0f4d2a55',
      publicKey: '',
      serverName: '',
      link: link,
      private: true,
    );
    final dials = RealityRelay.dialPlan([relay]);
    expect(dials, hasLength(1));
    expect(dials.single.fingerprint, relay.fingerprint);
    expect(identical(dials.single, relay), isTrue);
  });

  test(
    'a hello this network already proved leads the plan, ladder behind it',
    () {
      final relay = RealityRelay.fromJson(_entry())!;
      final dials = RealityRelay.dialPlan([relay], preferredShape: 'ios');
      // The measured answer goes first; the guess stays behind it as the
      // insurance against a carrier that changed its mind mid-tunnel.
      expect(dials.map((d) => d.fingerprint).toList(), [
        'ios',
        'hellochrome_120',
        'hellochrome_106_shuffle',
        'chrome',
      ]);
    },
  );

  test(
    'a remembered hello leaves later relays to walk addresses, not shapes',
    () {
      final relays = [
        RealityRelay.fromJson(_entry())!,
        RealityRelay.fromJson(_entry(id: 'r2', host: '198.51.100.4'))!,
      ];
      final dials = RealityRelay.dialPlan(relays, preferredShape: 'ios');
      expect(dials.length, 6);
      expect(dials.skip(4).map((d) => '${d.host} ${d.fingerprint}').toList(), [
        '198.51.100.4 ios',
        '198.51.100.4 chrome',
      ]);
    },
  );

  test('a remembered hello never rewrites a link the user pasted', () {
    final relay = RealityRelay.fromJson(_entry(fingerprint: 'ios'))!;
    final imported = RealityRelay(
      id: 'home',
      host: '203.0.113.9',
      port: 443,
      uuid: '111e808e-3628-42a4-b17f-5e3b0f4d2a55',
      publicKey: '',
      serverName: '',
      link:
          'vless://111e808e-3628-42a4-b17f-5e3b0f4d2a55'
          '@203.0.113.9:443?security=reality&sni=www.example.com'
          '&pbk=Svl81isn16RPAFnjtmYw7A6TPnsEPLHuYYaJht65Rzc'
          '&fp=chrome#Home',
      private: true,
    );
    final dials = RealityRelay.dialPlan([
      relay,
      imported,
    ], preferredShape: 'hellochrome_106_shuffle');
    expect(dials.first.fingerprint, 'hellochrome_106_shuffle');
    expect(dials.last.link, isNotNull);
    expect(identical(dials.last, imported), isTrue);
  });
}
