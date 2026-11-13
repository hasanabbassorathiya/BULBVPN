import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/reality/relay_link.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';

/// The whole point of the import path is that one pasted line can express a
/// transport this app could not express before. These tests read the JSON the
/// core is handed, because that string is the only part of the feature that is
/// verifiable without a phone on a censored network: a dial failure on device
/// cannot tell a bad config from a blocked relay, but a bad key here is
/// provable on a laptop.
void main() {
  group('xray config from a share link', () {
    test('the envelope always holds exactly one proxy outbound', () {
      for (final link in _allLinks) {
        final relay = relayFromLink(link);
        expect(relay, isNotNull, reason: link);
        final config = relay!.toXrayConfig();
        expect(config.containsKey('inbounds'), isFalse, reason: link);
        expect(config.containsKey('routing'), isFalse, reason: link);
        expect(config.containsKey('dns'), isFalse, reason: link);
        final outbounds = config['outbounds']! as List;
        expect(outbounds, hasLength(1), reason: link);
        final outbound = outbounds.single as Map<String, Object?>;
        expect(outbound['tag'], 'proxy', reason: link);
        _assertNoNulls(outbound, link);
        expect(
          jsonEncode(config).contains('allowInsecure'),
          isFalse,
          reason: link,
        );
      }
    });

    test('vless + reality + tcp keeps the camouflage and the key', () {
      final config = _configOf(
        'vless://b831381d-f64f-4dc6-9c91-cf7b5c3b5c1a'
        '@reality.example.ir:443'
        '?encryption=none&security=reality&sni=www.speedtest.net'
        '&pbk=SlUZh1XUEGqrbPZ1cQ3lGCzV-9xOR9zFm7-y0dJWEVE'
        '&sid=6ba47dcf&fp=chrome&flow=xtls-rprx-vision&type=tcp#Tehran-1',
      );
      final outbound = _outbound(config);
      expect(outbound['protocol'], 'vless');
      final stream = outbound['streamSettings']! as Map<String, Object?>;
      expect(stream['network'], 'tcp');
      expect(stream['security'], 'reality');
      final reality = stream['realitySettings']! as Map<String, Object?>;
      expect(reality['serverName'], 'www.speedtest.net');
      expect(reality['publicKey'], 'SlUZh1XUEGqrbPZ1cQ3lGCzV-9xOR9zFm7-y0dJWEVE');
      expect(reality['shortId'], '6ba47dcf');
      expect(reality['fingerprint'], 'chrome');
      final settings = outbound['settings']! as Map<String, Object?>;
      final vnext = settings['vnext']! as List;
      final users = (vnext.single as Map<String, Object?>)['users']! as List;
      final user = users.single as Map<String, Object?>;
      expect(user['flow'], 'xtls-rprx-vision');
      expect(user['encryption'], 'none');
    });

    test('vless + tls + websocket carries path and host', () {
      final config = _configOf(
        'vless://15c4ff1c-8c0a-4c0e-bb7f-4d3f0a4f2f11'
        '@ws.example.net:2053'
        '?encryption=none&security=tls&sni=cdn.example.net'
        '&type=ws&path=%2Fws-path&host=cdn.example.net#WS-2053',
      );
      final stream = _outbound(config)['streamSettings']! as Map<String, Object?>;
      expect(stream['network'], 'ws');
      expect(stream['security'], 'tls');
      final ws = stream['wsSettings']! as Map<String, Object?>;
      expect(ws['path'], '/ws-path');
      expect((ws['headers']! as Map<String, Object?>)['Host'], 'cdn.example.net');
      final tls = stream['tlsSettings']! as Map<String, Object?>;
      expect(tls['serverName'], 'cdn.example.net');
    });

    test('trojan + grpc keeps the service name', () {
      final config = _configOf(
        'trojan://s3cret@grpc.example.net:443'
        '?security=tls&sni=grpc.example.net&type=grpc&serviceName=video'
        '&mode=multi#gRPC',
      );
      final outbound = _outbound(config);
      expect(outbound['protocol'], 'trojan');
      final servers = (outbound['settings']!
              as Map<String, Object?>)['servers']!
          as List;
      expect((servers.single as Map<String, Object?>)['password'], 's3cret');
      final stream = outbound['streamSettings']! as Map<String, Object?>;
      expect(stream['network'], 'grpc');
      final grpc = stream['grpcSettings']! as Map<String, Object?>;
      expect(grpc['serviceName'], 'video');
      expect(grpc['multiMode'], true);
    });

    test('xhttp passes its extra knobs through instead of dropping them', () {
      final config = _configOf(
        'vless://9a1a1e5c-1d0f-4f2a-9b1e-3f2a1c5d7e11'
        '@xhttp.example.net:443'
        '?encryption=none&security=tls&type=xhttp&mode=auto'
        '&path=%2Fxhttp&host=xhttp.example.net'
        '&extra=%7B%22prefetchBytes%22%3A2000%7D#XHTTP',
      );
      final stream = _outbound(config)['streamSettings']! as Map<String, Object?>;
      expect(stream['network'], 'xhttp');
      final xhttp = stream['xhttpSettings']! as Map<String, Object?>;
      expect(xhttp['mode'], 'auto');
      expect(xhttp['path'], '/xhttp');
      expect((xhttp['extra']! as Map<String, Object?>)['prefetchBytes'], 2000);
    });

    test('h2 settings are renamed to the key the core actually reads', () {
      // The bundled builder serializes h2 transport settings as `h2Setting`.
      // Xray reads `httpSettings`, so an unrenamed import dials a bare h2
      // tunnel with no path and no host: a relay that connects and forwards
      // nothing, which is the failure this app is not allowed to ship.
      final config = _configOf(
        'vless://2b7d4f2a-8a1e-4c9f-b0d2-6f1a2e3c4d5b'
        '@h2.example.net:443'
        '?encryption=none&security=tls&type=http'
        '&host=h2.example.net&path=%2Fh2#H2',
      );
      final stream = _outbound(config)['streamSettings']! as Map<String, Object?>;
      expect(stream['network'], 'h2');
      expect(stream.containsKey('h2Setting'), isFalse);
      final http = stream['httpSettings']! as Map<String, Object?>;
      expect(http['path'], '/h2');
      expect(http['host'], ['h2.example.net']);
    });

    test('vmess and ss import with their own credentials', () {
      final vmessConfig = _configOf(_vmessLink());
      final vmessOutbound = _outbound(vmessConfig);
      expect(vmessOutbound['protocol'], 'vmess');
      final vmessSettings =
          vmessOutbound['settings']! as Map<String, Object?>;
      final vmessVnext = vmessSettings['vnext']! as List;
      final vmessUser =
          ((vmessVnext.single as Map<String, Object?>)['users']! as List).single
              as Map<String, Object?>;
      expect(vmessUser['id'], '1e2f8f9a-2b4d-4c9e-9f2a-7d6c5b4a3928');
      expect(vmessUser['alterId'], 0);

      final ssConfig = _configOf(_ssLink());
      expect(_outbound(ssConfig)['protocol'], 'shadowsocks');
    });
  });

  group('describing an imported relay', () {
    test('the dial and SNI are read off the link', () {
      final relay = relayFromLink(
        'vless://b831381d-f64f-4dc6-9c91-cf7b5c3b5c1a'
        '@203.0.113.9:8443?encryption=none&security=reality'
        '&pbk=abc&sni=target.example&fp=chrome&type=tcp#TEH-2',
      )!;
      expect(relay.host, '203.0.113.9');
      expect(relay.port, 8443);
      expect(relay.serverName, 'target.example');
      expect(relay.countryName, 'TEH-2');
      expect(relay.displayName, 'TEH-2');
      expect(relay.endpoint, '203.0.113.9:8443');
    });

    test('a server the user chose is private', () {
      final relay = relayFromLink(_wsLink())!;
      final target = relay.toTarget();
      expect(target.trustTier, TrustTier.byos);
      expect(target.trustTier!.isPrivate, isTrue);
      expect(target.trustTier!.disclosure, isNot(contains('not private')));
    });

    test('a catalog relay is still not private', () {
      const relay = RealityRelay(
        id: 'c1',
        host: 'community.example',
        port: 443,
        uuid: 'u',
        publicKey: 'k',
        serverName: 'www.cloudflare.com',
        countryName: 'Estonia',
      );
      expect(relay.toTarget().trustTier, TrustTier.community);
      expect(relay.private, isFalse);
      expect(relay.link, isNull);
    });

    test('a link with nowhere to dial is refused, not stored', () {
      expect(relayFromLink('not a link'), isNull);
      expect(relayFromLink('vless://uuid@:443?type=tcp'), isNull);
      expect(relayFromLink('trojan://pass@'), isNull);
    });

    test('a link that omits the port dials the protocol default', () {
      // 443 is a fallback the server actually listens on, not a guess. What has
      // to be refused is a profile with no address: a `:0` port reads as no
      // port at all, and storing the resulting relay would spend a connect
      // attempt on a host that cannot answer.
      expect(relayFromLink('trojan://pass@relay.example.net')!.port, 443);
      expect(relayFromLink('trojan://pass@relay.example.net:0')!.port, 443);
    });
  });

  group('describing what a relay becomes', () {
    test('the shape is read off the config, not the link', () {
      final shape = DialShape.of(relayFromLink(_grpcLink())!);
      expect(shape.protocol, 'trojan');
      expect(shape.transport, 'grpc');
      expect(shape.security, 'tls');
      expect(shape.serverName, 'grpc.example.net');
      expect(shape.camouflagesAs, 'grpc.example.net');
      expect(shape.isUnprotected, isFalse);
      expect(shape.summary, 'Trojan · gRPC · TLS');
    });

    test('a catalog relay reports the hard-wired reality shape', () {
      const relay = RealityRelay(
        id: 'c1',
        host: 'community.example',
        port: 443,
        uuid: 'u',
        publicKey: 'k',
        serverName: 'www.apple.com',
      );
      final shape = DialShape.of(relay);
      expect(shape.summary, 'VLESS · TCP · REALITY');
      expect(shape.isUnprotected, isFalse);
    });

    test('a transport the parser has no name for is reported, not invented', () {
      // `type=wg` reaches the core as `network: wg`. Showing the user the token
      // the config really carries is the only way a mistyped profile is visible
      // before it spends a connect attempt; silently calling it TCP would make a
      // broken link look like a working server.
      final shape = DialShape.of(
        relayFromLink(
          'vless://15c4ff1c-8c0a-4c0e-bb7f-4d3f0a4f2f11'
          '@ws.example.net:2053?encryption=none&security=tls'
          '&sni=cdn.example.net&type=wg#Bogus',
        )!,
      );
      expect(shape.transport, 'wg');
      expect(shape.summary, 'VLESS · WG · TLS');
    });

    test('a relay without TLS is called unprotected', () {
      final shape = DialShape.of(
        relayFromLink(
          'vless://15c4ff1c-8c0a-4c0e-bb7f-4d3f0a4f2f11'
          '@plain.example.net:8080?encryption=none&type=ws#NoTls',
        )!,
      );
      expect(shape.security, isEmpty);
      expect(shape.isUnprotected, isTrue);
      expect(shape.camouflagesAs, isNull);
      expect(shape.summary, 'VLESS · WebSocket');
    });

    test('shadowsocks carries no SNI and no TLS claim', () {
      final shape = DialShape.of(relayFromLink(_ssLink())!);
      expect(shape.protocol, 'shadowsocks');
      expect(shape.serverName, isEmpty);
      expect(shape.isUnprotected, isTrue);
      expect(shape.summary, 'Shadowsocks · TCP');
    });
  });

  group('subscriptions', () {
    test('every profile in a base64 body is kept', () {
      final body = base64Encode(utf8.encode('${_wsLink()}\n${_grpcLink()}\n'));
      final relays = relaysFromSubscription(body);
      expect(relays, hasLength(2));
      expect(relays.map((relay) => relay.host), [
        'ws.example.net',
        'grpc.example.net',
      ]);
    });

    test('a duplicate profile is stored once', () {
      final body = base64Encode(utf8.encode('${_wsLink()}\n${_wsLink()}\n'));
      expect(relaysFromSubscription(body), hasLength(1));
    });

    test('a raw xray json profile is dialled from inside its own outbound', () {
      // A config-version subscription states no address at the URL level, so
      // reading only the link would report an import of zero profiles.
      final json = jsonEncode({
        'log': {'loglevel': 'warning'},
        'outbounds': [
          {
            'protocol': 'vless',
            'tag': 'proxy',
            'settings': {
              'vnext': [
                {
                  'address': 'json.example.net',
                  'port': 443,
                  'users': [
                    {'id': 'd5a1c8f2-1e2b-4c3d-9e0f-a1b2c3d4e5f6'},
                  ],
                },
              ],
            },
            'streamSettings': {
              'network': 'tcp',
              'security': 'reality',
              'realitySettings': {
                'serverName': 'json.example.net',
                'publicKey': 'rKey',
                'fingerprint': 'chrome',
              },
            },
          },
        ],
      });
      final relay = relayFromLink(json)!;
      expect(relay.host, 'json.example.net');
      expect(relay.port, 443);
      expect(relay.serverName, 'json.example.net');
      final outbound = _outbound(relay.toXrayConfig());
      expect(outbound['tag'], 'proxy');
      expect(outbound['protocol'], 'vless');
    });

    test('a subscription url must be https', () async {
      // Guarded before the socket opens, so this reaches no network.
      expect(await fetchSubscription('http://sub.example.net/abc'), isNull);
      expect(await fetchSubscription('sub.example.net/abc'), isNull);
      expect(await fetchSubscription('https://'), isNull);
    });
  });

  test('catalog entries still build the hard-wired reality outbound', () {
    const relay = RealityRelay(
      id: 'c1',
      host: 'community.example',
      port: 443,
      uuid: 'the-uuid',
      publicKey: 'the-key',
      serverName: 'www.apple.com',
      shortId: 'ab',
      flow: 'xtls-rprx-vision',
    );
    final outbound = _outbound(relay.toXrayConfig());
    expect(outbound['protocol'], 'vless');
    final stream = outbound['streamSettings']! as Map<String, Object?>;
    expect(stream['security'], 'reality');
    final reality = stream['realitySettings']! as Map<String, Object?>;
    expect(reality['publicKey'], 'the-key');
    expect(reality['shortId'], 'ab');
  });
}

Map<String, Object?> _configOf(String link) =>
    relayFromLink(link)!.toXrayConfig();

Map<String, Object?> _outbound(Map<String, Object?> config) =>
    ((config['outbounds']! as List).single as Map<String, Object?>);

String _wsLink() =>
    'vless://15c4ff1c-8c0a-4c0e-bb7f-4d3f0a4f2f11@ws.example.net:2053'
    '?encryption=none&security=tls&sni=cdn.example.net'
    '&type=ws&path=%2Fws-path&host=cdn.example.net#WS-2053';

String _grpcLink() =>
    'trojan://s3cret@grpc.example.net:443?security=tls'
    '&sni=grpc.example.net&type=grpc&serviceName=video#gRPC';

String _vmessLink() {
  final payload = {
    'v': '2',
    'ps': 'VMess-WS',
    'add': 'vmess.example.net',
    'port': '443',
    'id': '1e2f8f9a-2b4d-4c9e-9f2a-7d6c5b4a3928',
    'aid': '0',
    'sc': 'auto',
    'net': 'ws',
    'type': 'none',
    'host': 'vmess.example.net',
    'path': '/vmess',
    'tls': 'tls',
    'sni': 'vmess.example.net',
  };
  return 'vmess://${base64Encode(utf8.encode(jsonEncode(payload)))}';
}

String _ssLink() {
  final credential = base64Encode(utf8.encode('chacha20-ietf-poly1305:p@ss'));
  return 'ss://$credential@ss.example.net:8388#SS-8388';
}

final _allLinks = [
  _wsLink(),
  _grpcLink(),
  _vmessLink(),
  _ssLink(),
];

void _assertNoNulls(Object? value, String reason) {
  if (value is Map) {
    for (final entry in value.entries) {
      expect(entry.value, isNot(isNull), reason: '$reason · ${entry.key}');
      _assertNoNulls(entry.value, reason);
    }
  } else if (value is List) {
    for (final item in value) {
      _assertNoNulls(item, reason);
    }
  }
}
