import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_vless/flutter_vless.dart';

import 'package:bulbvpn/modules/core/reality/reality_relay.dart';

/// A server the user brought, turned into something the dial contract already
/// knows how to start.
///
/// The share link is the source of truth, not a re-typed form. Every field the
/// engine needs to *describe* the relay (host, port, SNI, label) is read off
/// the parsed link, and the field it needs to *dial* it is the link itself:
/// `RealityRelay.toXrayConfig` hands the link back to the same Xray config
/// generator that produced it. A hand-built form could express fewer mistakes,
/// but it would also express fewer servers — and the whole reason this path
/// exists is that the bundled pool is too small and too already-blocked.
///
/// `allowInsecure` cannot be set from a link and is stripped again on the way
/// down (once in Dart, once in the native runtime), so an imported server is
/// always certificate-verified.
RealityRelay? relayFromLink(String link, {String? id}) {
  final FlutterVlessURL parsed;
  try {
    parsed = FlutterVless.parse(link);
  } catch (_) {
    return null;
  }
  return _importedRelay(parsed, id: id);
}

/// Every profile in a subscription body.
///
/// The plugin skips protocols it has no verified Xray mapping for, and it does
/// not report what it skipped, so a caller that wants an honest count compares
/// its own line count with the length of this list.
List<RealityRelay> relaysFromSubscription(String body) {
  final List<FlutterVlessURL> parsed;
  try {
    parsed = FlutterVless.parseMany(body);
  } catch (_) {
    return const <RealityRelay>[];
  }
  final relays = <RealityRelay>[];
  final seen = <String>{};
  for (final entry in parsed) {
    final relay = _importedRelay(entry);
    if (relay == null) continue;
    if (!seen.add(relay.id)) continue;
    relays.add(relay);
  }
  return relays;
}

/// Fetches a subscription body.
///
/// This is the one place in the connect path that trusts an address the app did
/// not choose, so it is capped and https-only. A subscription served over
/// plain http can be rewritten in flight to hand the user a relay the network
/// controls, and an imported relay is labelled as the user's own — the app
/// cannot tell them their server was swapped, so the transport has to.
Future<String?> fetchSubscription(
  String url, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) return null;
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'bulbvpn-relay-import');
    final response = await request.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    // A subscription endpoint can answer with the whole internet. 2 MB is far
    // past any honest profile list and stops a hostile host from exhausting
    // the phone's memory through our import field.
    final body = await response
        .transform(const _LimitBytes(2 * 1024 * 1024))
        .transform(utf8.decoder)
        .join();
    return body;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Turns a parsed share link into the dial shape the engine already accepts.
RealityRelay? _importedRelay(
  FlutterVlessURL parsed, {
  String? id,
}) {
  final outbound = _asMap(parsed.outbound1);
  final dial = _dialOf(parsed, outbound);
  if (dial == null) return null;
  final host = dial.$1;
  final port = dial.$2;
  final remark = parsed.remark.trim();
  return RealityRelay(
    id: (id ?? '').trim().isEmpty
        ? (remark.isEmpty ? '$host:$port' : remark)
        : id!.trim(),
    host: host,
    port: port,
    // The catalog's own fields stay empty: an imported server has no country
    // claim we can vouch for, and the label is the user's remark.
    uuid: '',
    publicKey: '',
    serverName: _serverNameOf(outbound),
    countryCode: '',
    countryName: remark.isEmpty ? host : remark,
    link: parsed.url,
    private: true,
  );
}

/// Where this profile is actually dialled.
///
/// A share link states it in the URL. A raw Xray JSON profile does not: the
/// base class reports no address at all, and the real one lives inside the
/// outbound's settings, so an import that read only the URL would reject every
/// config-version subscription as undialable.
(String, int)? _dialOf(FlutterVlessURL parsed, Map<String, Object?> outbound) {
  final urlHost = parsed.address.trim();
  if (urlHost.isNotEmpty) return _dial(urlHost, parsed.port);
  final settings = _asMap(outbound['settings']);
  for (final key in const ['vnext', 'servers', 'peers']) {
    final list = settings[key];
    if (list is! List) continue;
    for (final item in list) {
      final entry = _asMap(item);
      final host = entry['address']?.toString().trim() ?? '';
      final port = switch (entry['port']) {
        final int value => value,
        final String value => int.tryParse(value) ?? 0,
        _ => 0,
      };
      if (host.isEmpty) continue;
      final dial = _dial(host, port);
      if (dial != null) return dial;
    }
  }
  final host = outbound['address']?.toString().trim() ?? '';
  final port = outbound['port'];
  return _dial(host, port is int ? port : 0);
}

/// A dial the core can open a socket to.
///
/// A port of 0 is not a typo to be forgiven: it is what a link reads as when
/// the remark carries a colon, and a tunnel that starts against it reports a
/// handshake and forwards nothing.
(String, int)? _dial(String host, int port) {
  if (host.isEmpty || port < 1 || port > 65535) return null;
  return (host, port);
}

/// The SNI the relay is dialled with, read back out of the generated config
/// rather than re-derived from the link's query string.
///
/// `sni` defaults to the host the transport chose when the link omits it, so
/// asking the builder is the only way to report what will actually be sent on
/// the wire.
String _serverNameOf(Map<String, Object?> outbound) {
  final stream = _asMap(outbound['streamSettings']);
  for (final key in const ['realitySettings', 'tlsSettings']) {
    final sni = _asMap(stream[key])['serverName'];
    if (sni is String && sni.trim().isNotEmpty) return sni.trim();
  }
  return '';
}

Map<String, Object?> _asMap(Object? value) => value is Map
    ? value.map((k, v) => MapEntry(k.toString(), v))
    : const <String, Object?>{};

/// The tunnel a relay becomes, read back out of the config it generates.
///
/// The import preview shows this instead of echoing the link's own query
/// parameters. Two reasons: a raw JSON profile has no query string to echo at
/// all, and the config is what the core is told. A link whose `type` the parser
/// does not know is emitted verbatim — `type=wg` reports transport `wg`, not
/// the `tcp` a re-reading of the link would have implied — so a mistyped
/// profile shows up as a token no tunnel runs on rather than quietly costing
/// the user a connect attempt.
class DialShape {
  const DialShape({
    required this.protocol,
    required this.transport,
    required this.security,
    required this.serverName,
  });

  /// `vless`, `trojan`, `vmess`, `shadowsocks`, `socks`, `http`.
  final String protocol;

  /// `tcp`, `ws`, `grpc`, `xhttp`, `h2`, `httpupgrade`, `quic`.
  final String transport;

  /// `reality` or `tls` — empty when the link asks for no TLS at all.
  final String security;

  /// The name sent on the wire. Empty for a relay that sends none.
  final String serverName;

  factory DialShape.of(RealityRelay relay) {
    final config = relay.toXrayConfig();
    final outbound = config['outbounds'];
    final first = outbound is List && outbound.isNotEmpty
        ? _asMap(outbound.first)
        : const <String, Object?>{};
    final stream = _asMap(first['streamSettings']);
    return DialShape(
      protocol: first['protocol']?.toString().trim().toLowerCase() ?? '',
      transport: stream['network']?.toString().trim().toLowerCase() ?? '',
      security: stream['security']?.toString().trim().toLowerCase() ?? '',
      serverName: _serverNameOf(first),
    );
  }

  bool get isEmpty =>
      protocol.isEmpty && transport.isEmpty && security.isEmpty;

  /// `VLESS · gRPC · TLS`, the way the card prints it.
  String get summary => [
    if (protocol.isNotEmpty) _named(_protocols, protocol),
    if (transport.isNotEmpty) _named(_transports, transport),
    if (security.isNotEmpty && security != 'none')
      _named(_securities, security),
  ].join(' · ');

  /// What the relay is camouflaged as, or null when it is not camouflaged.
  ///
  /// A TLS session with no server name is worth saying out loud, and one with
  /// no TLS at all is worth saying louder: [isUnprotected] is the case where the
  /// user's traffic leaves the phone readable, which is the claim a VPN exists
  /// to make.
  String? get camouflagesAs => serverName.isEmpty ? null : serverName;

  bool get isUnprotected => security.isEmpty || security == 'none';

  static String _named(Map<String, String> names, String key) =>
      names[key] ?? key.toUpperCase();

  static const _protocols = {
    'vless': 'VLESS',
    'vmess': 'VMess',
    'trojan': 'Trojan',
    'shadowsocks': 'Shadowsocks',
    'socks': 'SOCKS',
    'http': 'HTTP',
  };

  static const _transports = {
    'tcp': 'TCP',
    'ws': 'WebSocket',
    'grpc': 'gRPC',
    'xhttp': 'XHTTP',
    'h2': 'HTTP/2',
    'httpupgrade': 'HTTPUpgrade',
    'quic': 'QUIC',
  };

  static const _securities = {'reality': 'REALITY', 'tls': 'TLS'};
}

/// Passes bytes through until [limit], then fails.
///
/// Deliberately an error rather than a silent truncation: half a subscription
/// parses into a shorter profile list, and a user would have no way to tell a
/// throttled host from a provider with fewer servers.
class _LimitBytes extends StreamTransformerBase<List<int>, List<int>> {
  const _LimitBytes(this.limit);

  final int limit;

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) {
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    var seen = 0;
    controller = StreamController<List<int>>(
      onListen: () {
        subscription = stream.listen(
          (chunk) {
            seen += chunk.length;
            if (seen > limit) {
              controller.addError(
                const _SubscriptionTooLarge(
                  'subscription body exceeds the import cap',
                ),
              );
              subscription?.cancel();
              controller.close();
              return;
            }
            controller.add(chunk);
          },
          onError: controller.addError,
          onDone: controller.close,
          cancelOnError: true,
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}

class _SubscriptionTooLarge implements Exception {
  const _SubscriptionTooLarge(this.message);

  final String message;
}
