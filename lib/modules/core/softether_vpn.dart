import 'dart:async';
import 'dart:convert';

import 'package:bulbvpn/modules/core/vpngate_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Hostname of the SoftEther relay that currently owns the tunnel.
final softEtherHostProvider = StateProvider<String?>((ref) => null);

/// Snapshot of the native tunnel. The Flutter side must treat [running] as
/// authoritative; `assignedIp` can outlive a dead TCP session.
class SoftEtherStatus {
  final bool running;
  final String host;
  final String reason;
  final bool carrierUp;
  final String effectiveIp;

  const SoftEtherStatus({
    required this.running,
    required this.host,
    this.reason = '',
    this.carrierUp = true,
    this.effectiveIp = '',
  });

  static const down = SoftEtherStatus(
    running: false,
    host: '',
    reason: '',
  );

  bool get isLive => running && carrierUp;
}


/// SoftEther SSL-VPN (HTTPS) into a VPN Gate hub.
///
/// The phone can finish a TLS handshake to these servers on port 443.
/// OpenVPN on the same machines stalls in AUTH.
class SoftEtherVpn {
  static const _channel = MethodChannel('app.bulbvpn.com/softether');

  /// VPN Gate CSV stores `public-vpn-160` or `vpn918840683`, not a DNS name.
  static String fqdn(String hostName) {
    final host = hostName.trim();
    if (host.isEmpty || host.contains('.')) return host;
    return '$host.opengw.net';
  }

  static Future<List<String>> hosts() async {
    const fallback = <String>[
      'public-vpn-202.opengw.net',
      'public-vpn-206.opengw.net',
      'public-vpn-192.opengw.net',
    ];
    for (final url in vpnGatePublishedLists) {
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        if (decoded is! List) continue;
        final byCountry = <String, String>{};
        for (final raw in decoded) {
          if (raw is! Map) continue;
          final country = raw['CountryLong']?.toString() ?? '';
          final host = fqdn(raw['#HostName']?.toString() ?? '');
          if (country.isEmpty || host.isEmpty || byCountry.containsKey(country)) {
            continue;
          }
          byCountry[country] = host;
        }
        if (byCountry.isNotEmpty) return byCountry.values.toList();
      } catch (_) {}
    }
    return fallback;
  }

  /// [dial] is the server IP from the row you tapped. [sni] is its
  /// `.opengw.net` name, used only for the TLS certificate.
  static Future<({bool ok, String detail})> connect({
    required String dial,
    required String sni,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('connect', {
        'host': dial,
        'sni': sni,
      }).timeout(const Duration(seconds: 40));
      if (raw is! Map) return (ok: false, detail: 'bad response');
      return (
        ok: raw['ok'] == true,
        detail: raw['detail']?.toString() ?? '',
      );
    } on TimeoutException {
      return (ok: false, detail: 'timeout');
    } on PlatformException catch (error) {
      return (ok: false, detail: error.message ?? error.code);
    }
  }

  static Future<void> disconnect() async {
    try {
      await _channel.invokeMethod<void>('disconnect');
    } catch (_) {}
  }

  /// Whether the Android service still owns a tunnel after the UI restarts.
  static Future<SoftEtherStatus> status() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('status');
      if (raw is Map) {
        return SoftEtherStatus(
          running: raw['running'] == true,
          host: raw['host']?.toString() ?? '',
          reason: raw['reason']?.toString() ?? '',
          carrierUp: raw['carrierUp'] != false,
          effectiveIp: raw['effectiveIp']?.toString() ?? '',
        );
      }
    } catch (_) {}
    return SoftEtherStatus.down;
  }

  static Future<int> bytesReceived() async {
    try {
      final value = await _channel.invokeMethod<dynamic>('bytesDown');
      if (value is int) return value;
      if (value is num) return value.toInt();
    } catch (_) {}
    return 0;
  }

  /// Detailed native service snapshot for the support log. Android only; on
  /// Apple the packet tunnel owns the session, so the missing plugin yields
  /// null and the Dart log remains the diagnostic record.
  static Future<Map<String, dynamic>?> diagnostics() async {
    try {
      final raw = await _channel
          .invokeMethod<dynamic>('diagnostics')
          .timeout(const Duration(seconds: 3));
      if (raw is Map) {
        return raw.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }
}
