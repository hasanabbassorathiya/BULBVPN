import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_vless/flutter_vless.dart';

import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';

/// One dialable proxy endpoint.
///
/// Built-in entries are VLESS+REALITY, which is the only transport in the app
/// that is not a VPN handshake: the relay answers like the TLS site named in
/// [serverName] until the client proves it knows [publicKey], so a DPI box that
/// blocks VPN Gate/OpenVPN sees an ordinary HTTPS session. That is why this path
/// works on carriers where every SoftEther relay is blackholed.
///
/// Entries with a [link] are whatever the user pasted — any protocol,
/// transport and security combination the bundled core understands.
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
    this.link,
    this.private = false,
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

  /// A share link the user brought, or null for a catalog entry.
  ///
  /// When it is set, [toXrayConfig] regenerates the outbound from the link with
  /// the bundled Xray config builder instead of describing this relay with the
  /// REALITY fields above. That is what makes the import path able to express
  /// every protocol, transport and security combination the core supports —
  /// the shape this class could otherwise hard-code one at a time. The link is
  /// also what gets stored, so an imported server survives a restart without
  /// the app having re-typed any of its knobs.
  final String? link;

  /// True when the user chose this address, so the surface may call it private.
  ///
  /// The invariant is the one [TrustTier] states: traffic never passes an
  /// address the user has not chosen. A relay from a bought subscription
  /// satisfies it even though the operator is a stranger the app did not vet,
  /// because the user pointed the app at it deliberately.
  final bool private;

  String get displayName {
    final name = countryName.trim();
    if (name.isNotEmpty) return name;
    final code = countryCode.trim().toUpperCase();
    if (code.length == 2) return code;
    // A countryless community entry must not borrow the private label: the
    // operator is still a stranger, whatever the generator failed to look up.
    return private ? 'Private relay' : 'Community relay';
  }

  String get label =>
      city.trim().isEmpty ? displayName : '$displayName · $city';

  String get endpoint => port == 443 ? host : '$host:$port';

  /// What identifies this relay as a destination, independent of its label.
  ///
  /// The vault keys on this rather than on [id] so that re-importing a
  /// subscription replaces the server at that address instead of stacking a
  /// second row for it under a different remark.
  String get dialKey => '$host:$port';

  /// ClientHello shapes to dial a REALITY relay with, best evidence first.
  ///
  /// A handshake that never completes on one carrier and completes on the next
  /// is a packet-shape problem rather than a relay problem, because the shape
  /// comes from the fingerprint and every relay in a catalog inherits it at the
  /// same moment. `chrome` is uTLS' HelloChrome_Auto: since Chrome enabled
  /// post-quantum key agreement its key_share carries X25519MLKEM768, which
  /// pushes the hello past one MTU payload into two TCP segments. Sizes are
  /// measured against the uTLS revision the bundled core pins, by `go run
  /// main.go` in [tool/hellosize]:
  ///
  ///   hellochrome_120          597 B  one segment
  ///   ios                      512 B  one segment
  ///   hellochrome_106_shuffle  512 B  one segment
  ///   chrome                  1819 B  two segments
  ///
  /// `android` and `360` are absent on purpose: neither offers TLS 1.3, and the
  /// core refuses them with "REALITY handshake cannot establish".
  ///
  /// Fragmenting the hello instead is not a fallback here. Iran began dropping
  /// every fragmented ClientHello structurally around late July 2026, so a
  /// two-segment hello is a shape to avoid, not a shape to hide.
  static const handshakeLadder = <String>[
    'hellochrome_120',
    'ios',
    'hellochrome_106_shuffle',
  ];

  /// Fingerprint names whose ClientHello no longer fits one TCP segment.
  ///
  /// Anything absent here is dialled as-is; the names below are the ones
  /// [tool/hellosize] measured above 1448 B, which includes the aliases uTLS
  /// resolves to the same modern browsers.
  static const wideHelloShapes = <String>{
    'chrome',
    'hellochrome_auto',
    'hellochrome_131',
    'hellochrome_133',
    'hellochrome_115_pq',
    'hellochrome_115_pq_psk',
    'hellochrome_120_pq',
    'firefox',
    'hellofirefox_auto',
    'hellofirefox_148',
    'safari',
    'hellosafari_auto',
    'hellosafari_26_3',
  };

  /// True when this relay's own fingerprint sends a hello the network may split.
  bool get helloIsWide => wideHelloShapes.contains(fingerprint);

  /// The dial plan for one connect pass: relays in order, each at the hello
  /// shapes worth trying.
  ///
  /// The address and the ClientHello shape are two different failure axes. A
  /// carrier that drops the shape blackholes every relay at once, so walking
  /// IPs alone can never fix it; a carrier that blocks an IP needs the walk.
  /// The first relay therefore gets the whole ladder, which answers the shape
  /// question in one place, and later relays get the narrow hello followed by
  /// whatever their author published. Imported links keep the knobs the user
  /// pasted — rewriting a fingerprint there would override a deliberate
  /// choice, so each is dialled once as-is.
  ///
  /// [preferredShape] is the hello this network last carried a verified
  /// transfer. It leads, because a shape that moved bytes is evidence and the
  /// ladder is a guess; the head still walks the ladder behind it so a carrier
  /// that starts dropping the remembered hello is caught here rather than
  /// failing every address in the plan.
  static List<RealityRelay> dialPlan(
    List<RealityRelay> queue, {
    String preferredShape = '',
  }) {
    final dials = <RealityRelay>[];
    for (var i = 0; i < queue.length; i++) {
      final relay = queue[i];
      if (relay.link != null) {
        dials.add(relay);
        continue;
      }
      final shapes = <String>[];
      void add(String shape) {
        if (shape.isNotEmpty && !shapes.contains(shape)) shapes.add(shape);
      }

      if (preferredShape.isNotEmpty) {
        add(preferredShape);
        // A remembered hello settles the shape question, so only the head
        // keeps the ladder behind it — the insurance against a carrier that
        // changed its mind. Later relays are dialled at the one shape this
        // network already proved, because walking addresses is the only
        // question left for them.
        if (i == 0) {
          for (final shape in handshakeLadder) {
            add(shape);
          }
        }
      } else {
        for (final shape in handshakeLadder) {
          add(shape);
          // Only the head relay is worth three shapes: it is the one place the
          // ladder question gets answered, and the budget is shared with the
          // SoftEther fallback.
          if (i > 0) break;
        }
      }
      if (relay.helloIsWide || i > 0) add(relay.fingerprint);
      for (final shape in shapes) {
        dials.add(relay.withHelloShape(shape));
      }
    }
    return dials;
  }

  /// The same relay dialled with one of the [handshakeLadder] shapes.
  ///
  /// Only the hello changes: the address, key and short id are untouched, so a
  /// second shape is a second attempt at the same relay rather than a new
  /// relay, and nothing about the user's choice is rewritten.
  RealityRelay withHelloShape(String shape) => RealityRelay(
    id: id,
    host: host,
    port: port,
    uuid: uuid,
    publicKey: publicKey,
    serverName: serverName,
    shortId: shortId,
    fingerprint: shape,
    flow: flow,
    countryCode: countryCode,
    countryName: countryName,
    city: city,
    link: link,
    private: private,
  );

  /// The row as the vault stores it.
  ///
  /// A link is the whole profile and is stored verbatim; the remaining fields
  /// are what the sheet prints and what the dial order keys on before anything
  /// is parsed.
  Map<String, Object?> toStoredJson() => {
    'id': id,
    'host': host,
    'port': port,
    if (link != null) 'link': link,
    if (private) 'private': true,
    if (uuid.isNotEmpty) 'uuid': uuid,
    if (publicKey.isNotEmpty) 'public_key': publicKey,
    if (serverName.isNotEmpty) 'server_name': serverName,
    if (shortId.isNotEmpty) 'short_id': shortId,
    if (fingerprint.isNotEmpty && fingerprint != 'chrome')
      'fingerprint': fingerprint,
    if (flow.isNotEmpty) 'flow': flow,
    if (countryCode.isNotEmpty) 'country_code': countryCode,
    if (countryName.isNotEmpty) 'country_name': countryName,
    if (city.isNotEmpty) 'city': city,
  };

  /// A relay read back from the vault.
  ///
  /// The same rule the catalog uses applies: an entry that cannot be dialled is
  /// dropped, not half-restored. Anything this build can no longer parse stays
  /// addressable by [id] so the user can remove the row rather than having it
  /// silently vanish from a list they imported.
  static RealityRelay? fromStoredJson(Map<String, Object?> json) {
    String text(String key) => json[key]?.toString().trim() ?? '';
    final host = text('host');
    final port = int.tryParse(text('port'));
    final link = text('link');
    final uuid = text('uuid');
    final publicKey = text('public_key');
    if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
    // Either the link describes the dial, or the REALITY fields do. A row with
    // neither is a leftover from a format this build never wrote.
    if (link.isEmpty && (uuid.isEmpty || publicKey.isEmpty)) return null;
    final id = text('id');
    return RealityRelay(
      id: id.isEmpty ? host : id,
      host: host,
      port: port,
      uuid: uuid,
      publicKey: publicKey,
      serverName: text('server_name'),
      shortId: text('short_id'),
      fingerprint: text('fingerprint').isEmpty ? 'chrome' : text('fingerprint'),
      flow: text('flow'),
      countryCode: text('country_code').toUpperCase(),
      countryName: text('country_name'),
      city: text('city'),
      link: link.isEmpty ? null : link,
      private: json['private'] == true,
    );
  }

  /// The single outbound the tunnel uses.
  ///
  /// The tag must stay `proxy`: the native stats query reads
  /// `outbound>>>proxy>>>` and the DNS proxy policy addresses this outbound by
  /// tag. No inbound is emitted here; the plugin adds its own SOCKS listener
  /// and routes the TUN through it.
  ///
  /// The envelope is deliberately this small on both paths. The config builder
  /// can also emit a whole document, but that one carries `direct` and
  /// `blackhole` outbounds plus its own routing and DNS strategy — a second
  /// resolver the app would not be steering, which is exactly how a "private"
  /// tunnel leaks the lookup while still looking connected.
  Map<String, Object?> toXrayConfig() {
    final imported = link;
    if (imported != null && imported.trim().isNotEmpty) {
      return {
        'log': _log,
        'outbounds': [_proxyOutbound(imported.trim())],
      };
    }
    final user = <String, Object?>{
      'id': uuid,
      'encryption': 'none',
      'level': 0,
      if (flow.trim().isNotEmpty) 'flow': flow.trim(),
    };
    return {
      'log': _log,
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

  static const _log = {'loglevel': 'warning'};

  /// The outbound a share link describes, retagged for our envelope.
  static Map<String, Object?> _proxyOutbound(String link) {
    final outbound = Map<String, Object?>.from(
      FlutterVless.parse(link).outbound1,
    );
    outbound['tag'] = 'proxy';
    return _prune(outbound) as Map<String, Object?>;
  }

  /// Drops the nulls the config builder leaves in its maps.
  ///
  /// The native runtime sanitizes again before Xray sees the JSON, but this is
  /// the same string we log, persist and assert in tests, and a config that
  /// reads differently on paper than on the wire is how a dead transport gets
  /// defended for a week. It also corrects one key the builder mis-names: h2
  /// settings are emitted as `h2Setting`, which Xray ignores, so an imported
  /// `type=http` relay would dial a bare h2 tunnel with no path or host.
  static Object? _prune(Object? value) {
    if (value is Map) {
      final source = value.map((k, v) => MapEntry(k.toString(), v));
      final h2 = source.remove('h2Setting');
      if (h2 != null) source['httpSettings'] ??= h2;
      final kept = <String, Object?>{};
      source.forEach((key, entry) {
        if (key == 'allowInsecure') return;
        final pruned = _prune(entry);
        if (pruned != null) kept[key] = pruned;
      });
      return kept;
    }
    if (value is List) {
      final items = <Object?>[];
      for (final entry in value) {
        final pruned = _prune(entry);
        if (pruned != null) items.add(pruned);
      }
      return items;
    }
    return value;
  }

  String toXrayConfigJson() => jsonEncode(toXrayConfig());

  /// The relay as the connect contract knows it.
  ///
  /// An imported server is [TrustTier.byos]: the user chose the address, so it
  /// may be shown as private. Everything else is [TrustTier.community] — the
  /// operator is a stranger, and every surface that shows it must say it is not
  /// private.
  RelayTarget toTarget({String source = 'reality', int pingMs = 0}) {
    return RelayTarget(
      dial: host,
      sni: serverName,
      port: port,
      countryCode: countryCode.toUpperCase(),
      countryName: countryName,
      pingMs: pingMs,
      source: source,
      trustTier: private ? TrustTier.byos : TrustTier.community,
    );
  }

  /// Returns null for an entry that cannot be dialled: a REALITY session
  /// without a key or camouflage name would either leak or fail the handshake.
  ///
  /// An entry may instead carry a share [link] (XHTTP has no structured shape
  /// here); the link is the whole profile, as it is for an imported server.
  /// Catalog entries are always community-trusted — unlike [fromStoredJson],
  /// a `private` flag in the asset is ignored, because nobody named these
  /// addresses on this phone.
  static RealityRelay? fromJson(Map<String, Object?> json) {
    String text(String key) => json[key]?.toString().trim() ?? '';
    final host = text('host');
    final link = text('link');
    final uuid = text('uuid');
    final publicKey = text('public_key');
    final serverName = text('server_name');
    final rawPort = text('port');
    // 443 is the default only when the entry omits the field. An unparsable
    // value is a broken entry, not a reason to guess a port.
    final port = rawPort.isEmpty ? 443 : int.tryParse(rawPort);
    if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
    if (link.isEmpty &&
        (uuid.isEmpty || publicKey.isEmpty || serverName.isEmpty)) {
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
      fingerprint: text('fingerprint').isEmpty ? 'chrome' : text('fingerprint'),
      flow: text('flow'),
      countryCode: text('country_code').toUpperCase(),
      countryName: text('country_name'),
      city: text('city'),
      link: link.isEmpty ? null : link,
    );
  }
}

/// The bundled REALITY catalog.
///
/// Relays are community-contributed and on unless the user switches them off;
/// they are never fed into the automatic SoftEther/VPN Gate rotation.
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

  static RealityRelay? findByHost(List<RealityRelay> relays, String? host) {
    final wanted = (host ?? '').trim();
    if (wanted.isEmpty) return null;
    for (final relay in relays) {
      if (relay.host == wanted) return relay;
    }
    return null;
  }
}
