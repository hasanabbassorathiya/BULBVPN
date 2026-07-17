import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class IPInfo {
  final String ip;
  final String city;
  final String region;
  final String country;
  final String countryCode;
  final String org;
  final double lat;
  final double lon;
  final String timezone;
  final String flagEmoji;
  final String connectionType;

  IPInfo({
    required this.ip,
    required this.city,
    required this.region,
    required this.country,
    required this.countryCode,
    required this.org,
    required this.lat,
    required this.lon,
    required this.timezone,
    required this.flagEmoji,
    required this.connectionType,
  });

  factory IPInfo.fromJson(Map<String, dynamic> json) {
    final flag = json['flag'] as Map<String, dynamic>? ?? {};
    final connection = json['connection'] as Map<String, dynamic>? ?? {};
    final tz = json['timezone'] as Map<String, dynamic>? ?? {};

    return IPInfo(
      ip: json['ip'] ?? '',
      city: json['city'] ?? '',
      region: json['region'] ?? '',
      country: json['country'] ?? '',
      countryCode: json['country_code'] ?? '',
      org: connection['org'] ?? '',
      lat: (json['latitude'] ?? 0).toDouble(),
      lon: (json['longitude'] ?? 0).toDouble(),
      timezone: tz['utc'] ?? '',
      flagEmoji: flag['emoji'] ?? '🌐',
      connectionType: connection['isp'] ?? '',
    );
  }

  String get flag {
    const flags = {
      'JP': '🇯🇵', 'KR': '🇰🇷', 'US': '🇺🇸', 'GB': '🇬🇧',
      'DE': '🇩🇪', 'FR': '🇫🇷', 'NL': '🇳🇱', 'SG': '🇸🇬',
      'AU': '🇦🇺', 'CA': '🇨🇦', 'BR': '🇧🇷', 'IN': '🇮🇳',
      'TH': '🇹🇭', 'VN': '🇻🇳', 'RU': '🇷🇺', 'UA': '🇺🇦',
      'RO': '🇷🇴', 'AE': '🇦🇪', 'BY': '🇧🇾',
    };
    return flags[countryCode] ?? flagEmoji;
  }
}

class IPInfoService {
  static const String _url = 'https://ipwho.is/';

  static Future<IPInfo?> fetchIPInfo() async {
    try {
      final response = await http.get(Uri.parse(_url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          return IPInfo.fromJson(json);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
