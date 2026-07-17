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
  final String flag;

  VpnGateServer({
    required this.hostName,
    required this.ip,
    required this.ping,
    required this.countryLong,
    required this.countryShort,
    required this.openVpnConfig,
    this.speed = 0,
    this.sessions = 0,
    this.flag = '🌐',
  });

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
    try {
      final response = await http.get(Uri.parse(serverUrl)).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        final servers = _parseServers(jsonList);
        if (servers.isNotEmpty) {
          _pingServersInBackground(servers);
          return servers;
        }
      }
    } catch (e) {
      // API failed, use fallback
    }

    // Fallback: return hardcoded servers with standard OpenVPN configs
    return _getFallbackServers();
  }

  /// Hardcoded fallback servers with STANDARD OpenVPN configs (not SoftEther)
  /// These use the VPN Gate public relay servers with standard OpenVPN protocol
  static List<VpnGateServer> _getFallbackServers() {
    return [
      VpnGateServer(
        hostName: 'public-vpn-135.opengw.net',
        ip: '219.100.37.93',
        ping: 10,
        countryLong: 'Japan',
        countryShort: 'JP',
        flag: '🇯🇵',
        speed: 194870000,
        sessions: 108,
        openVpnConfig: '''
client
dev tun
proto tcp
remote 219.100.37.93 443
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-128-CBC
auth SHA1
verb 3
remote-cert-tls server
''',
      ),
      VpnGateServer(
        hostName: 'public-vpn-221.opengw.net',
        ip: '219.100.37.184',
        ping: 22,
        countryLong: 'Japan',
        countryShort: 'JP',
        flag: '🇯🇵',
        speed: 245590000,
        sessions: 58,
        openVpnConfig: '''
client
dev tun
proto tcp
remote 219.100.37.184 443
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-128-CBC
auth SHA1
verb 3
remote-cert-tls server
''',
      ),
      VpnGateServer(
        hostName: 'public-vpn-72.opengw.net',
        ip: '219.100.37.22',
        ping: 13,
        countryLong: 'Japan',
        countryShort: 'JP',
        flag: '🇯🇵',
        speed: 251790000,
        sessions: 167,
        openVpnConfig: '''
client
dev tun
proto tcp
remote 219.100.37.22 443
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-128-CBC
auth SHA1
verb 3
remote-cert-tls server
''',
      ),
      VpnGateServer(
        hostName: 'vpn211969447.opengw.net',
        ip: '118.41.236.148',
        ping: 24,
        countryLong: 'Korea Republic of',
        countryShort: 'KR',
        flag: '🇰🇷',
        speed: 82980000,
        sessions: 60,
        openVpnConfig: '''
client
dev tun
proto tcp
remote 118.41.236.148 1966
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-128-CBC
auth SHA1
verb 3
remote-cert-tls server
''',
      ),
      VpnGateServer(
        hostName: 'opengw.opengw.net',
        ip: '217.138.212.62',
        ping: 6,
        countryLong: 'Romania',
        countryShort: 'RO',
        flag: '🇷🇴',
        speed: 338890000,
        sessions: 142,
        openVpnConfig: '''
client
dev tun
proto tcp
remote 217.138.212.62 443
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-128-CBC
auth SHA1
verb 3
remote-cert-tls server
''',
      ),
      VpnGateServer(
        hostName: 'vpn566985610.opengw.net',
        ip: '38.34.238.19',
        ping: 10,
        countryLong: 'United States',
        countryShort: 'US',
        flag: '🇺🇸',
        speed: 0,
        sessions: 67,
        openVpnConfig: '''
client
dev tun
proto tcp
remote 38.34.238.19 1511
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-128-CBC
auth SHA1
verb 3
remote-cert-tls server
''',
      ),
      VpnGateServer(
        hostName: 'vpn536928802.opengw.net',
        ip: '171.6.9.46',
        ping: 5,
        countryLong: 'Thailand',
        countryShort: 'TH',
        flag: '🇹🇭',
        speed: 407260000,
        sessions: 113,
        openVpnConfig: '''
client
dev tun
proto tcp
remote 171.6.9.46 1631
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-128-CBC
auth SHA1
verb 3
remote-cert-tls server
''',
      ),
      VpnGateServer(
        hostName: 'vpn272636404.opengw.net',
        ip: '70.79.229.82',
        ping: 18,
        countryLong: 'Canada',
        countryShort: 'CA',
        flag: '🇨🇦',
        speed: 665540000,
        sessions: 41,
        openVpnConfig: '''
client
dev tun
proto tcp
remote 70.79.229.82 1734
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-128-CBC
auth SHA1
verb 3
remote-cert-tls server
''',
      ),
    ];
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
              flag: server.flag,
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

        // Check if this is a SoftEther config — skip it
        if (config.contains('SoftEther') || config.contains('PacketiX')) continue;

        final pingStr = item['Ping']?.toString() ?? '999';
        final ping = int.tryParse(pingStr) ?? 999;
        if (ping <= 0 || ping > 500) continue;

        final countryCode = item['CountryShort'] as String? ?? '';
        if (countryCode.isEmpty) continue;

        final flags = {
          'JP': '🇯🇵', 'KR': '🇰🇷', 'US': '🇺🇸', 'GB': '🇬🇧',
          'DE': '🇩🇪', 'FR': '🇫🇷', 'NL': '🇳🇱', 'SG': '🇸🇬',
          'AU': '🇦🇺', 'CA': '🇨🇦', 'BR': '🇧🇷', 'IN': '🇮🇳',
          'TH': '🇹🇭', 'VN': '🇻🇳', 'RU': '🇷🇺', 'UA': '🇺🇦',
          'RO': '🇷🇴', 'AE': '🇦🇪', 'DO': '🇩🇴',
        };

        servers.add(VpnGateServer(
          hostName: item['#HostName'] ?? item['HostName'] ?? '',
          ip: item['IP'] ?? '',
          ping: ping,
          countryLong: item['CountryLong'] ?? '',
          countryShort: countryCode,
          openVpnConfig: config,
          speed: int.tryParse(item['Speed']?.toString() ?? '0') ?? 0,
          sessions: int.tryParse(item['NumVpnSessions']?.toString() ?? '0') ?? 0,
          flag: flags[countryCode] ?? '🌐',
        ));
      } catch (_) {
        continue;
      }
    }

    servers.sort((a, b) => a.ping.compareTo(b.ping));
    return servers;
  }
}
