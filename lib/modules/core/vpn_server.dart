/// One public relay from a VPN Gate catalog row.
class VpnServer {
  final String hostName;
  final String ip;
  final String countryLong;
  final String countryShort;
  final int score;
  final int ping;
  final int speed;
  final int numVpnSessions;
  final int uptime;
  final String openVpnConfigBase64;

  VpnServer({
    required this.hostName,
    required this.ip,
    required this.countryLong,
    required this.countryShort,
    required this.score,
    required this.ping,
    required this.speed,
    required this.numVpnSessions,
    required this.uptime,
    required this.openVpnConfigBase64,
  });

  factory VpnServer.fromJson(Map<String, dynamic> json) {
    return VpnServer(
      hostName: json['#HostName']?.toString() ?? '',
      ip: json['IP']?.toString() ?? '',
      countryLong: json['CountryLong']?.toString() ?? '',
      countryShort: json['CountryShort']?.toString() ?? '',
      score: int.tryParse(json['Score']?.toString() ?? '0') ?? 0,
      ping: int.tryParse(json['Ping']?.toString() ?? '0') ?? 0,
      speed: int.tryParse(json['Speed']?.toString() ?? '0') ?? 0,
      numVpnSessions: int.tryParse(json['NumVpnSessions']?.toString() ?? '0') ?? 0,
      uptime: int.tryParse(json['Uptime']?.toString() ?? '0') ?? 0,
      openVpnConfigBase64: json['OpenVPN_ConfigData_Base64']?.toString() ?? '',
    );
  }

  String get speedMbps => (speed / 1024 / 1024).toStringAsFixed(1);

  /// Catalog rows sometimes store `Croatia (LOCAL Name: Hrvatska)`.
  String get displayCountry {
    final cut = countryLong.indexOf(' (');
    if (cut > 0) return countryLong.substring(0, cut);
    return countryLong;
  }

  /// Country only. Hostnames and addresses stay off the private-app UI.
  String get publicLabel =>
      displayCountry.isEmpty ? 'Private relay' : displayCountry;
}

/// Turns a stored `host · ip` session label into a country name.
String publicRelayLabel(String? stored, Iterable<VpnServer> catalog) {
  if (stored == null || stored.isEmpty) return 'Private relay';
  final ip = RegExp(r'\d{1,3}(?:\.\d{1,3}){3}').firstMatch(stored)?.group(0);
  if (ip != null) {
    for (final server in catalog) {
      if (server.ip == ip && server.displayCountry.isNotEmpty) {
        return server.displayCountry;
      }
    }
    return 'Private relay';
  }
  final lower = stored.toLowerCase();
  if (lower.contains('opengw') ||
      lower.contains('vpngate') ||
      lower.contains('public-vpn')) {
    return 'Private relay';
  }
  return stored;
}

/// Hides catalog hostnames from the on-screen log.
String redactRelayDetail(String line) {
  return line
      .replaceAll(RegExp(r'[\w.-]*opengw\.net'), 'relay')
      .replaceAll(RegExp(r'public-vpn-\d+'), 'relay')
      .replaceAll(RegExp(r'\bvpn\d+\b'), 'relay')
      .replaceAll(RegExp(r'vpngate', caseSensitive: false), 'catalog');
}
