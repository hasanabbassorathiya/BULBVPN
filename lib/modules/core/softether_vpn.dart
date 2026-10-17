import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Hostname of the SoftEther relay that currently owns the tunnel.
final softEtherHostProvider = StateProvider<String?>((ref) => null);

/// SoftEther SSL-VPN (HTTPS) into a VPN Gate hub.
///
/// The phone can finish a TLS handshake to these servers on port 443.
/// OpenVPN on the same machines stalls in AUTH.
class SoftEtherVpn {
  static const _channel = MethodChannel('app.bulbvpn.com/softether');
  static const _mirror =
      'https://raw.githubusercontent.com/alihusains/apigate/main/response.json';

  static Future<List<String>> hosts() async {
    const preferred = <String>[
      'public-vpn-202.opengw.net',
      'public-vpn-206.opengw.net',
      'public-vpn-192.opengw.net',
    ];
    try {
      final response = await http
          .get(Uri.parse(_mirror))
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return preferred;
      final names = <String>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final host = raw['#HostName']?.toString() ?? '';
        if (host.endsWith('.opengw.net')) names.add(host);
      }
      final ordered = <String>[
        ...preferred.where(names.contains),
        ...names.where((host) => !preferred.contains(host)),
      ];
      if (ordered.isEmpty) return preferred;
      return ordered.take(4).toList();
    } catch (_) {
      return preferred;
    }
  }

  /// Returns true when the SSL tunnel is up. [detail] is the tunnel address
  /// or the native error code.
  static Future<({bool ok, String detail})> connect(String host) async {
    final raw = await _channel.invokeMethod<dynamic>('connect', {
      'host': host,
      'sni': host,
    });
    if (raw is! Map) return (ok: false, detail: 'bad response');
    return (
      ok: raw['ok'] == true,
      detail: raw['detail']?.toString() ?? '',
    );
  }

  static Future<void> disconnect() async {
    try {
      await _channel.invokeMethod<void>('disconnect');
    } catch (_) {}
  }

  static Future<int> bytesReceived() async {
    try {
      final value = await _channel.invokeMethod<dynamic>('bytesDown');
      if (value is int) return value;
      if (value is num) return value.toInt();
    } catch (_) {}
    return 0;
  }
}
