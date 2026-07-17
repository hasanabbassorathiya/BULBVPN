import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class VpnGateServer {
  final String hostName;
  final String ip;
  final int ping;
  final String countryLong;
  final String countryShort;
  final String openVpnConfig;
  final int speed;
  final int sessions;

  VpnGateServer({
    required this.hostName,
    required this.ip,
    required this.ping,
    required this.countryLong,
    required this.countryShort,
    required this.openVpnConfig,
    required this.speed,
    required this.sessions,
  });

  String get flag {
    const flags = {
      'JP': '🇯🇵', 'KR': '🇰🇷', 'US': '🇺🇸', 'GB': '🇬🇧',
      'DE': '🇩🇪', 'FR': '🇫🇷', 'NL': '🇳🇱', 'SG': '🇸🇬',
      'AU': '🇦🇺', 'CA': '🇨🇦', 'BR': '🇧🇷', 'IN': '🇮🇳',
      'TH': '🇹🇭', 'VN': '🇻🇳', 'RU': '🇷🇺', 'UA': '🇺🇦',
      'RO': '🇷🇴', 'AE': '🇦🇪', 'DO': '🇩🇴',
    };
    return flags[countryShort] ?? '🌐';
  }

  String get speedLabel {
    if (speed > 1000000000) return '${(speed / 1000000000).toStringAsFixed(1)} Gbps';
    if (speed > 1000000) return '${(speed / 1000000).toStringAsFixed(0)} Mbps';
    if (speed > 1000) return '${(speed / 1000).toStringAsFixed(0)} Kbps';
    return '$speed bps';
  }
}

class VpnGateApi {
  static const String serverUrl = 'https://raw.githubusercontent.com/alihusains/apigate/main/response.json';

  static Future<List<VpnGateServer>> fetchServers() async {
    final response = await http.get(Uri.parse(serverUrl)).timeout(
      const Duration(seconds: 15),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch servers: ${response.statusCode}');
    }

    final List<dynamic> jsonList = json.decode(response.body);
    final servers = _parseServers(jsonList);

    _pingServersInBackground(servers);

    return servers;
  }

  static void _pingServersInBackground(List<VpnGateServer> servers) {
    Future.microtask(() async {
      for (final server in servers) {
        if (server.ip.isEmpty) continue;
        final pingMs = await _tcpPing(server.ip, 443);
        if (pingMs > 0) {
          final index = servers.indexOf(server);
          if (index >= 0) {
            servers[index] = VpnGateServer(
              hostName: server.hostName,
              ip: server.ip,
              ping: pingMs,
              countryLong: server.countryLong,
              countryShort: server.countryShort,
              openVpnConfig: server.openVpnConfig,
              speed: server.speed,
              sessions: server.sessions,
            );
          }
        }
      }
      servers.sort((a, b) => a.ping.compareTo(b.ping));
    });
  }

  static Future<int> _tcpPing(String host, int port) async {
    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(host, port,
        timeout: const Duration(seconds: 3),
      );
      stopwatch.stop();
      socket.destroy();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  static List<VpnGateServer> _parseServers(List<dynamic> jsonList) {
    final servers = <VpnGateServer>[];

    for (final item in jsonList) {
      try {
        if (item is! Map<String, dynamic>) continue;

        final configB64 = item['OpenVPN_ConfigData_Base64'] as String? ?? '';
        if (configB64.isEmpty) continue;

        final config = utf8.decode(base64.decode(configB64));
        if (!config.contains('remote ')) continue;

        final pingStr = item['Ping']?.toString() ?? '999';
        final ping = int.tryParse(pingStr) ?? 999;
        if (ping <= 0 || ping > 500) continue;

        final countryCode = item['CountryShort'] as String? ?? '';
        if (countryCode.isEmpty) continue;

        servers.add(VpnGateServer(
          hostName: item['#HostName'] ?? item['HostName'] ?? '',
          ip: item['IP'] ?? '',
          ping: ping,
          countryLong: item['CountryLong'] ?? '',
          countryShort: countryCode,
          openVpnConfig: config,
          speed: int.tryParse(item['Speed']?.toString() ?? '0') ?? 0,
          sessions: int.tryParse(item['NumVpnSessions']?.toString() ?? '0') ?? 0,
        ));
      } catch (_) {
        continue;
      }
    }

    servers.sort((a, b) => a.ping.compareTo(b.ping));
    return servers;
  }
}
