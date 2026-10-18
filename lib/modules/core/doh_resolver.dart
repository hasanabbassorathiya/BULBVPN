import 'dart:convert';

import 'package:http/http.dart' as http;

/// Resolves hostnames over DNS-over-HTTPS so connect works when system DNS
/// is blocked or poisoned. Used before OpenVPN dials a remote.
class DohResolver {
  DohResolver._();

  static final Map<String, String> _cache = <String, String>{};
  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  static bool isIpv4(String host) => _ipv4.hasMatch(host);

  /// Returns an IPv4 address for [host], or null when DoH fails.
  static Future<String?> resolve(String host) async {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return null;
    if (isIpv4(trimmed)) return trimmed;
    final cached = _cache[trimmed];
    if (cached != null) return cached;

    final endpoints = <Uri>[
      Uri.https('cloudflare-dns.com', '/dns-query', {
        'name': trimmed,
        'type': 'A',
      }),
      Uri.https('dns.google', '/resolve', {
        'name': trimmed,
        'type': 'A',
      }),
    ];

    for (final uri in endpoints) {
      try {
        final response = await http
            .get(uri, headers: const {'Accept': 'application/dns-json'})
            .timeout(const Duration(seconds: 4));
        if (response.statusCode != 200) continue;
        final ip = _firstA(response.body);
        if (ip == null) continue;
        _cache[trimmed] = ip;
        return ip;
      } catch (_) {
        // Try the next resolver.
      }
    }
    return null;
  }

  /// Rewrites the first `remote` host in an OpenVPN profile to [ip].
  static String rewriteRemoteHost(String config, String ip) {
    return config.replaceFirstMapped(
      RegExp(r'^(\s*remote\s+)\S+(\s+\d+)', multiLine: true),
      (match) => '${match.group(1)}$ip${match.group(2)}',
    );
  }

  static String? remoteHost(String config) {
    final match = RegExp(
      r'^\s*remote\s+(\S+)\s+\d+',
      multiLine: true,
    ).firstMatch(config);
    return match?.group(1);
  }

  static String? _firstA(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is! Map) return null;
      final answers = decoded['Answer'];
      if (answers is! List) return null;
      for (final row in answers) {
        if (row is! Map) continue;
        final type = row['type'];
        final data = row['data']?.toString();
        if (data == null || data.isEmpty) continue;
        // Cloudflare/Google type 1 = A record.
        if (type == 1 && isIpv4(data)) return data;
      }
    } catch (_) {}
    return null;
  }
}
