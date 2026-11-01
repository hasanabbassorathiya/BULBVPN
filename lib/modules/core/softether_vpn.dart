import 'dart:async';
import 'dart:convert';

import 'package:bulbvpn/modules/core/split_tunnel.dart';
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

  /// Routing actually installed on this tunnel, not the saved preference.
  final TunnelMode routeMode;
  final int routeAppCount;

  /// Kill switch is holding a blocking TUN after an unexpected drop.
  final bool lockedDown;

  const SoftEtherStatus({
    required this.running,
    required this.host,
    this.reason = '',
    this.carrierUp = true,
    this.effectiveIp = '',
    this.routeMode = TunnelMode.all,
    this.routeAppCount = 0,
    this.lockedDown = false,
  });

  static const down = SoftEtherStatus(running: false, host: '', reason: '');

  bool get isLive => running && carrierUp;
}

class InstalledApp {
  final String package;
  final String label;

  const InstalledApp({required this.package, required this.label});
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
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        if (decoded is! List) continue;
        final byCountry = <String, String>{};
        for (final raw in decoded) {
          if (raw is! Map) continue;
          final country = raw['CountryLong']?.toString() ?? '';
          final host = fqdn(raw['#HostName']?.toString() ?? '');
          if (country.isEmpty ||
              host.isEmpty ||
              byCountry.containsKey(country)) {
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
  /// `.opengw.net` name, used only for the TLS certificate. [port] is the TCP
  /// listener, 443 unless a relay was reached on an alternate port. [split]
  /// defaults to the saved routing choice.
  static Future<({bool ok, String detail})> connect({
    required String dial,
    required String sni,
    int port = 443,
    SplitTunnelConfig? split,
  }) async {
    final route = split ?? await SplitTunnelStore.load();
    final applied = route.appliedMode;
    try {
      final raw = await _channel
          .invokeMethod<dynamic>('connect', {
            'host': dial,
            'sni': sni,
            'port': port,
            'mode': applied.name,
            'apps': applied == TunnelMode.all
                ? const <String>[]
                : route.packages.toList(growable: false),
          })
          .timeout(const Duration(seconds: 40));
      if (raw is! Map) return (ok: false, detail: 'bad response');
      return (ok: raw['ok'] == true, detail: raw['detail']?.toString() ?? '');
    } on TimeoutException {
      return (ok: false, detail: 'timeout');
    } on PlatformException catch (error) {
      return (ok: false, detail: error.message ?? error.code);
    }
  }

  /// Stops the engine. Only a user-initiated stop passes [reason] `user`; any
  /// other teardown counts as a drop, so the kill switch can keep blocking.
  static Future<void> disconnect({String reason = 'cleanup'}) async {
    try {
      await _channel.invokeMethod<void>('disconnect', {'reason': reason});
    } catch (_) {}
  }

  /// Re-installs the blocking TUN after a failed connect or a fallback engine
  /// that replaced it. Starts the service when it is no longer alive, so a
  /// dead tunnel fails closed. The native side no-ops when the switch is off.
  static Future<bool> engageLockdown() async {
    try {
      return await _channel.invokeMethod<bool>('engageLockdown') == true;
    } catch (_) {
      return false;
    }
  }

  /// Mirrors the kill switch toggle into the prefs the native service reads.
  static Future<void> setKillSwitch(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKillSwitch', {'enabled': enabled});
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
          routeMode: TunnelMode.fromName(raw['routeMode']?.toString()),
          routeAppCount: (raw['routeAppCount'] as num?)?.toInt() ?? 0,
          lockedDown: raw['lockedDown'] == true,
        );
      }
    } catch (_) {}
    return SoftEtherStatus.down;
  }

  /// Launchable apps on this phone, for the routing picker. Empty where the
  /// platform has no per-app tunnel control (Apple routes the whole device).
  static Future<List<InstalledApp>> installedApps() async {
    try {
      final raw = await _channel
          .invokeMethod<dynamic>('installedApps')
          .timeout(const Duration(seconds: 6));
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(
            (row) => InstalledApp(
              package: row['package']?.toString() ?? '',
              label: row['label']?.toString() ?? '',
            ),
          )
          .where((app) => app.package.isNotEmpty && app.label.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
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
