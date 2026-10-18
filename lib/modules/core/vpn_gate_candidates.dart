import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

/// One connectable VPN Gate endpoint parsed out of a `.ovpn` config.
class Candidate {
  final String ip;
  final int port;
  final String protocol; // 'tcp' | 'udp'
  final int csvPing;
  final String b64;
  final String config;

  const Candidate({
    required this.ip,
    required this.port,
    required this.protocol,
    required this.csvPing,
    required this.b64,
    required this.config,
  });

  /// Parses host/port/proto out of a decoded `.ovpn` body.
  static Candidate? fromConfig(String config, {String? fallbackIp, int? csvPing = 0}) {
    String? ip;
    int? port;
    for (final line in config.split('\n')) {
      final m = RegExp(r'^\s*remote\s+(\S+)\s+(\d+)').firstMatch(line);
      if (m != null) {
        ip = m.group(1);
        port = int.tryParse(m.group(2)!);
        break;
      }
    }
    var proto = 'udp';
    final protoMatch = RegExp(r'^\s*proto\s+(tcp4?|udp4?)\b', multiLine: true).firstMatch(config);
    if (protoMatch != null) {
      proto = protoMatch.group(1)!.startsWith('tcp') ? 'tcp' : 'udp';
    }
    // OpenVPN without an explicit proto line defaults to UDP; SoftEther
    // generated configs always carry one, but be defensive.
    if (ip == null && (fallbackIp == null || fallbackIp.isEmpty)) return null;
    final resolvedIp = (ip != null && ip.isNotEmpty) ? ip : fallbackIp!;
    return Candidate(
      ip: resolvedIp,
      port: port ?? 1194,
      protocol: proto,
      csvPing: csvPing ?? 0,
      b64: '',
      config: config,
    );
  }

  /// Same endpoint forced onto TCP [port]. SoftEther VPN Gate servers also
  /// listen on TCP 443, which DPI-heavy networks treat far better than the
  /// random ports (and UDP) in the generated config. The `proto` line is
  /// rewritten to `tcp` — labeling the candidate TCP while leaving `proto udp`
  /// in the file makes the engine speak UDP, which IR networks drop.
  /// Returns null when the config has no `remote` line or the port is unchanged
  /// and the config is already TCP.
  static Candidate? withPort(Candidate c, int port) {
    if (c.port == port && c.protocol == 'tcp') return null;
    var replaced = c.config.replaceFirstMapped(
      RegExp(r'^(\s*remote\s+\S+\s+)\d+', multiLine: true),
      (m) => '${m.group(1)}$port',
    );
    replaced = replaced.replaceFirstMapped(
      RegExp(r'^(\s*proto\s+)udp4?\b', multiLine: true),
      (m) => '${m.group(1)}tcp',
    );
    if (replaced == c.config) return null;
    return Candidate(
      ip: c.ip,
      port: port,
      protocol: 'tcp',
      csvPing: c.csvPing,
      b64: c.b64,
      config: replaced,
    );
  }

  /// A TCP clone of a UDP candidate (SoftEther serves OpenVPN over TCP on the
  /// same listener set; TCP survives DPI far better than UDP).
  static Candidate? asTcp(Candidate c) {
    if (c.protocol == 'tcp') return null;
    final replaced = c.config.replaceFirstMapped(
      RegExp(r'^(\s*proto\s+)udp4?\b', multiLine: true),
      (m) => '${m.group(1)}tcp',
    );
    if (replaced == c.config) return null;
    return Candidate(
      ip: c.ip,
      port: c.port,
      protocol: 'tcp',
      csvPing: c.csvPing,
      b64: c.b64,
      config: replaced,
    );
  }

  @override
  String toString() => '$ip:$port($protocol)';
}

String _sanitizeBase64(String b64) {
  var s = b64.trim().replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');
  final mod = s.length % 4;
  if (mod != 0) s += '=' * (4 - mod);
  return s;
}

String? decodeOvpn(String b64) {
  try {
    return utf8.decode(base64.decode(_sanitizeBase64(b64)));
  } catch (_) {
    return null;
  }
}

/// Ensures credentials are inlined as `<auth-user-pass>` — the only form the
/// openvpn_dart engine accepts (no separate username/password params).
String ensureAuthUserPass(String config) {
  if (config.contains('<auth-user-pass>')) return config;
  final userPassBlock = '<auth-user-pass>\nvpn\nvpn\n</auth-user-pass>\n';
  if (config.contains('#auth-user-pass')) {
    return config.replaceFirst('#auth-user-pass', userPassBlock);
  }
  if (RegExp(r'^\s*auth-user-pass\s*$', multiLine: true).hasMatch(config)) {
    return config.replaceFirstMapped(
      RegExp(r'^\s*auth-user-pass\s*$', multiLine: true),
      (_) => userPassBlock.trimRight(),
    );
  }
  return '$config\n$userPassBlock';
}

/// VPN Gate servers are SoftEther. ics-openvpn 0.7.x (the Android engine
/// inside openvpn_dart) ignores `cipher AES-128-CBC` unless the profile is
/// in OpenVPN 2.4 compatibility mode, then sits in AUTH forever.
/// https://github.com/schwabe/ics-openvpn/discussions/1562
String ensureIcsOpenVpnCompat(String config) {
  final extra = StringBuffer();
  if (!RegExp(r'^\s*compat-mode\b', multiLine: true).hasMatch(config)) {
    extra.writeln('compat-mode 2.4.0');
  }
  if (!RegExp(r'^\s*data-ciphers\b', multiLine: true).hasMatch(config)) {
    extra.writeln('data-ciphers AES-128-CBC');
  }
  if (!RegExp(r'^\s*provider\b', multiLine: true).hasMatch(config)) {
    extra.writeln('provider legacy default');
  }
  if (extra.isEmpty) return config;
  return '${config.trimRight()}\n$extra';
}

/// Drops ics-openvpn-only lines. OpenVPN Adapter 0.7 (iOS/macOS) does not
/// implement them, and a rejected profile fails every connect the same way.
String stripIcsOpenVpnCompat(String config) {
  return config
      .replaceAll(
        RegExp(
          r'^\s*(compat-mode|data-ciphers|provider)\b.*$',
          multiLine: true,
        ),
        '',
      )
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
}

/// OpenVPN 2.6 (Android ics-openvpn and the Windows `openvpn.exe` bundled
/// by openvpn_dart) ignores `cipher AES-128-CBC` unless the profile is in
/// 2.4 compatibility mode, then sits in AUTH. OpenVPN 3 / mbed TLS on
/// iOS, iPad, and macOS rejects those directives, so they must be stripped.
/// That Apple build finishes SoftEther only when TLS 1.0 is both the
/// minimum and the maximum (`patches/openvpn_adapter`). `sslDebug` does
/// not change the handshake; it only prints it.
String configForCurrentEngine(String config) {
  final withAuth = ensureAuthUserPass(config);
  if (Platform.isAndroid || Platform.isWindows) {
    return ensureIcsOpenVpnCompat(withAuth);
  }
  return stripIcsOpenVpnCompat(withAuth);
}

/// Fetches VPN Gate server configs — official CSV first (http + https), then
/// community JSON mirrors — and returns them TCP-first, lowest CSV ping first.
class VpnGateCandidates {
  static const _officialUrls = <String>[
    'http://www.vpngate.net/api/iphone/',
    'https://www.vpngate.net/api/iphone/',
  ];
  static const _mirrorUrls = <String>[
    'https://raw.githubusercontent.com/alihusains/apigate/main/response.json',
  ];

  static Future<List<Candidate>> fetchAll({void Function(String message)? onLog}) async {
    final log = onLog ?? (_) {};
    // Official http and https together. On networks that blackhole
    // vpngate.net, waiting for them one after another burns the whole
    // connect press before the mirror is tried.
    final official = await Future.wait([
      for (final url in _officialUrls) _fetchOfficial(url, log),
    ]);
    for (final candidates in official) {
      if (candidates.isNotEmpty) return candidates;
    }
    for (final url in _mirrorUrls) {
      try {
        log('Fallback JSON mirror $url');
        final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
        if (resp.statusCode != 200) {
          log('Mirror HTTP ${resp.statusCode} ($url)');
          continue;
        }
        final candidates = _fromJsonMirror(resp.body, log);
        if (candidates.isNotEmpty) return candidates;
        log('Mirror produced no candidates ($url)');
      } catch (e) {
        log('Mirror error ($url): $e');
      }
    }
    return const [];
  }

  static Future<List<Candidate>> _fetchOfficial(String url, void Function(String) log) async {
    try {
      log('Fetching VPNGate official CSV $url');
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200 || !resp.body.contains('OpenVPN_ConfigData_Base64')) {
        log('Official API unusable ($url): HTTP ${resp.statusCode}');
        return const [];
      }
      final candidates = _fromCsv(resp.body, log);
      if (candidates.isEmpty) log('Official API produced no candidates ($url)');
      return candidates;
    } catch (e) {
      log('Official API error ($url): $e');
      return const [];
    }
  }

  static List<Candidate> _fromCsv(String body, void Function(String) log) {
    final lines = body.split('\n');
    String? header;
    for (final l in lines) {
      if (l.startsWith('#') && l.contains('OpenVPN_ConfigData_Base64')) {
        header = l.replaceFirst(RegExp('^#+'), '');
        break;
      }
    }
    if (header == null) return const [];
    final cols = header.split(',');
    final pingIdx = cols.indexOf('Ping');
    final b64Idx = cols.indexOf('OpenVPN_ConfigData_Base64');
    if (b64Idx < 0) return const [];

    final candidates = <Candidate>[];
    for (final line in lines) {
      final l = line.trim();
      if (l.isEmpty || l.startsWith('*') || l.startsWith('#')) continue;
      final parts = l.split(',');
      if (parts.length <= b64Idx) continue;
      final b64 = parts[b64Idx].trim();
      if (b64.isEmpty) continue;
      final csvPing = pingIdx >= 0 && pingIdx < parts.length ? (int.tryParse(parts[pingIdx].trim()) ?? 0) : 0;
      final decoded = decodeOvpn(b64);
      if (decoded == null || !decoded.contains('<ca>')) continue;
      final c = Candidate.fromConfig(configForCurrentEngine(decoded), fallbackIp: parts[1].trim(), csvPing: csvPing);
      if (c != null) {
        candidates.add(Candidate(
          ip: c.ip,
          port: c.port,
          protocol: c.protocol,
          csvPing: c.csvPing,
          b64: b64,
          config: c.config,
        ));
      }
    }
    log('Parsed ${candidates.length} candidate endpoints from CSV');
    return _prioritize(candidates);
  }

  static List<Candidate> _fromJsonMirror(String body, void Function(String) log) {
    try {
      final List<dynamic> servers = jsonDecode(body) as List<dynamic>;
      final candidates = <Candidate>[];
      for (final raw in servers) {
        if (raw is! Map<String, dynamic>) continue;
        final b64 = raw['OpenVPN_ConfigData_Base64']?.toString() ?? '';
        if (b64.isEmpty) continue;
        final csvPing = int.tryParse(raw['Ping']?.toString() ?? '') ?? 0;
        final decoded = decodeOvpn(b64);
        if (decoded == null || !decoded.contains('<ca>')) continue;
        final c = Candidate.fromConfig(configForCurrentEngine(decoded), fallbackIp: raw['IP']?.toString(), csvPing: csvPing);
        if (c != null) {
          candidates.add(Candidate(
            ip: c.ip,
            port: c.port,
            protocol: c.protocol,
            csvPing: c.csvPing,
            b64: b64,
            config: c.config,
          ));
        }
      }
      log('Parsed ${candidates.length} candidate endpoints from mirror');
      return _prioritize(candidates);
    } catch (_) {
      return const [];
    }
  }

  /// TCP configs first (DPI-heavy networks), lowest CSV ping first within each
  /// protocol group. UDP candidates stay in the list — they still connect on
  /// permissive networks and the reachability probe filters dead ones.
  static List<Candidate> _prioritize(List<Candidate> input) {
    int score(Candidate c) {
      final ping = c.csvPing <= 0 ? 9999 : c.csvPing;
      return (c.protocol == 'tcp' ? 0 : 100000) + ping;
    }

    final sorted = [...input]..sort((a, b) => score(a).compareTo(score(b)));
    final withTcpClones = <Candidate>[];
    for (final c in sorted.take(40)) {
      withTcpClones.add(c);
      final tcp = Candidate.asTcp(c);
      if (tcp != null) withTcpClones.add(tcp);
      final c443 = Candidate.withPort(c, 443);
      if (c443 != null) withTcpClones.add(c443);
    }
    return withTcpClones;
  }
}
