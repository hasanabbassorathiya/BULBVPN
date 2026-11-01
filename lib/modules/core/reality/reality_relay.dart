import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';

/// One VLESS+REALITY endpoint.
///
/// REALITY is the only transport in the app that is not a VPN handshake: the
/// relay answers like the TLS site named in [serverName] until the client
/// proves it knows [publicKey], so a DPI box that blocks VPN Gate/OpenVPN
/// sees an ordinary HTTPS session. That is why this path works on carriers
/// where every SoftEther relay is blackholed.
class RealityRelay {
  const RealityRelay({
    required this.id,
    required this.host,
    required this.port,
    required this.uuid,
    required this.publicKey,
    required this.serverName,
    this.shortId = '',
    this.fingerprint = 'chrome',
    this.flow = '',
    this.countryCode = '',
    this.countryName = '',
    this.city = '',
  });

  final String id;
  final String host;
  final int port;
  final String uuid;

  /// REALITY public key the relay derives its handshake from.
  final String publicKey;

  /// Camouflage target: the relay forwards unauthenticated TLS here.
  final String serverName;

  final String shortId;
  final String fingerprint;
  final String flow;
  final String countryCode;
  final String countryName;
  final String city;

  String get displayName {
    final name = countryName.trim();
    if (name.isNotEmpty) return name;
    final code = countryCode.trim().toUpperCase();
    return code.length == 2 ? code : 'Private relay';
  }

  String get label => city.trim().isEmpty ? displayName : '$displayName · $city';

  String get endpoint => port == 443 ? host : '$host:$port';

  /// The single outbound the tunnel uses.
  ///
  /// The tag must stay `proxy`: the native stats query reads
  /// `outbound>>>proxy>>>` and the DNS proxy policy addresses this outbound by
  /// tag. No inbound is emitted here; the plugin adds its own SOCKS listener
  /// and routes the TUN through it.
  Map<String, Object?> toXrayConfig() {
    final user = <String, Object?>{
      'id': uuid,
      'encryption': 'none',
      'level': 0,
      if (flow.trim().isNotEmpty) 'flow': flow.trim(),
    };
    return {
      'log': {'loglevel': 'warning'},
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': host,
                'port': port,
                'users': [user],
              },
            ],
          },
          'streamSettings': {
            'network': 'tcp',
            'security': 'reality',
            'realitySettings': {
              'serverName': serverName,
              'fingerprint': fingerprint,
              'publicKey': publicKey,
              'shortId': shortId,
            },
          },
        },
      ],
    };
  }

  String toXrayConfigJson() => jsonEncode(toXrayConfig());

  /// The relay as the connect contract knows it.
  ///
  /// Trust is [TrustTier.community]: the operator is a stranger, so every
  /// surface that shows this relay must say it is not private.
  RelayTarget toTarget({
    String source = 'reality',
    int pingMs = 0,
  }) {
    return RelayTarget(
      dial: host,
      sni: serverName,
      port: port,
      countryCode: countryCode.toUpperCase(),
      countryName: countryName,
      pingMs: pingMs,
      source: source,
      trustTier: TrustTier.community,
    );
  }

  /// Returns null for an entry that cannot be dialled: a REALITY session
  /// without a key or camouflage name would either leak or fail the handshake.
  static RealityRelay? fromJson(Map<String, Object?> json) {
    String text(String key) => json[key]?.toString().trim() ?? '';
    final host = text('host');
    final uuid = text('uuid');
    final publicKey = text('public_key');
    final serverName = text('server_name');
    final rawPort = text('port');
    // 443 is the default only when the entry omits the field. An unparsable
    // value is a broken entry, not a reason to guess a port.
    final port = rawPort.isEmpty ? 443 : int.tryParse(rawPort);
    if (host.isEmpty ||
        uuid.isEmpty ||
        publicKey.isEmpty ||
        serverName.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    final id = text('id');
    return RealityRelay(
      id: id.isEmpty ? host : id,
      host: host,
      port: port,
      uuid: uuid,
      publicKey: publicKey,
      serverName: serverName,
      shortId: text('short_id'),
      fingerprint: text('fingerprint').isEmpty
          ? 'chrome'
          : text('fingerprint'),
      flow: text('flow'),
      countryCode: text('country_code').toUpperCase(),
      countryName: text('country_name'),
      city: text('city'),
    );
  }
}

/// The bundled REALITY catalog.
///
/// Relays are community-contributed, opt-in, and never fed into the automatic
/// SoftEther/VPN Gate rotation.
class RealityCatalog {
  RealityCatalog._();

  static const assetPath = 'assets/relays/community_reality.json';

  static List<RealityRelay>? _cached;

  static Future<List<RealityRelay>> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString(assetPath);
      final relays = parse(raw);
      _cached = relays;
      return relays;
    } catch (_) {
      return const <RealityRelay>[];
    }
  }

  /// Pure parser, so catalog validation is testable without a Flutter binding.
  /// A malformed asset yields an empty catalog rather than an exception at the
  /// call site.
  static List<RealityRelay> parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const <RealityRelay>[];
    }
    if (decoded is! Map) return const <RealityRelay>[];
    final list = decoded['relays'];
    if (list is! List) return const <RealityRelay>[];
    final relays = <RealityRelay>[];
    final seen = <String>{};
    for (final entry in list) {
      if (entry is! Map) continue;
      final relay = RealityRelay.fromJson(
        entry.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (relay == null) continue;
      if (!seen.add(relay.id)) continue;
      relays.add(relay);
    }
    return relays;
  }

  static RealityRelay? findByHost(
    List<RealityRelay> relays,
    String? host,
  ) {
    final wanted = (host ?? '').trim();
    if (wanted.isEmpty) return null;
    for (final relay in relays) {
      if (relay.host == wanted) return relay;
    }
    return null;
  }
}
