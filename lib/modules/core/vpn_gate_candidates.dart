import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One connectable VPN Gate endpoint parsed out of a `.ovpn` config.
class Candidate {
  final String ip;
  final int port;
  final String protocol; // 'tcp' | 'udp'
  final int csvPing;
  final String b64;
  final String config;

  /// `.opengw.net` name from the same catalog row. Used as SoftEther SNI when
  /// this candidate came from a fresh on-device fetch.
  final String sni;

  /// Country published in the catalog row, when known.
  final String countryCode;
  final String countryName;

  const Candidate({
    required this.ip,
    required this.port,
    required this.protocol,
    required this.csvPing,
    required this.b64,
    required this.config,
    this.sni = '',
    this.countryCode = '',
    this.countryName = '',
  });

  /// Parses host/port/proto out of a decoded `.ovpn` body.
  static Candidate? fromConfig(
    String config, {
    String? fallbackIp,
    int? csvPing = 0,
    String sni = '',
    String countryCode = '',
    String countryName = '',
  }) {
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
    final protoMatch = RegExp(
      r'^\s*proto\s+(tcp4?|udp4?)\b',
      multiLine: true,
    ).firstMatch(config);
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
      sni: sni,
      countryCode: countryCode,
      countryName: countryName,
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
      sni: c.sni,
      countryCode: c.countryCode,
      countryName: c.countryName,
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
      sni: c.sni,
      countryCode: c.countryCode,
      countryName: c.countryName,
    );
  }

  @override
  String toString() => '$ip:$port($protocol)';
}

String _sanitizeBase64(String b64) {
  var s = b64
      .trim()
      .replaceAll('\n', '')
      .replaceAll('\r', '')
      .replaceAll(' ', '');
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

String _fqdn(String host) {
  final value = host.trim();
  if (value.isEmpty || value.contains('.')) return value;
  return '$value.opengw.net';
}

String _displayCountry(String raw) {
  final cut = raw.indexOf(' (');
  return cut > 0 ? raw.substring(0, cut) : raw;
}

/// Fetches VPN Gate server configs from every official/mirror source at once
/// and returns the first non-empty answer, TCP-first, lowest CSV ping first.
class VpnGateCandidates {
  static const _officialUrls = <String>[
    'http://www.vpngate.net/api/iphone/',
    'https://www.vpngate.net/api/iphone/',
  ];
  static const _mirrorUrls = <String>[
    'https://raw.githubusercontent.com/alihusains/apigate/main/response.json',
  ];

  static Future<List<Candidate>> fetchAll({
    void Function(String message)? onLog,
  }) async {
    final log = onLog ?? (_) {};
    var live = await _raceSources(log);
    if (live.isNotEmpty) {
      unawaited(VpnGateCatalogCache.save(live));
      return live;
    }
    log('Every live VPN Gate source failed; reading the disk catalog');
    live = await VpnGateCatalogCache.load();
    if (live.isNotEmpty) log('Disk catalog: ${live.length} endpoints');
    return live;
  }

  /// The official CSV and the mirrors answer on different networks: vpngate.net
  /// is frequently blackholed on Iranian carriers while GitHub raw is not, and
  /// the reverse happens elsewhere. Waiting for sources in sequence spent most
  /// of a connect press on the blocked one, so every source starts together and
  /// the first usable list wins.
  static Future<List<Candidate>> _raceSources(void Function(String) log) {
    final completer = Completer<List<Candidate>>();
    var pending = _officialUrls.length + _mirrorUrls.length;
    void settle(List<Candidate> candidates) {
      if (candidates.isNotEmpty && !completer.isCompleted) {
        completer.complete(candidates);
      }
      pending -= 1;
      if (pending == 0 && !completer.isCompleted) {
        completer.complete(const []);
      }
    }

    for (final url in _officialUrls) {
      unawaited(_fetchOfficial(url, log).then(settle));
    }
    for (final url in _mirrorUrls) {
      unawaited(_fetchMirror(url, log).then(settle));
    }
    return completer.future;
  }

  static Future<List<Candidate>> _fetchMirror(
    String url,
    void Function(String) log,
  ) async {
    try {
      log('Fallback JSON mirror $url');
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        log('Mirror HTTP ${resp.statusCode} ($url)');
        return const [];
      }
      final candidates = _fromJsonMirror(resp.body, log);
      if (candidates.isEmpty) log('Mirror produced no candidates ($url)');
      return candidates;
    } catch (e) {
      log('Mirror error ($url): $e');
      return const [];
    }
  }

  static Future<List<Candidate>> _fetchOfficial(
    String url,
    void Function(String) log,
  ) async {
    try {
      log('Fetching VPNGate official CSV $url');
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200 ||
          !resp.body.contains('OpenVPN_ConfigData_Base64')) {
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
    final hostIdx = cols.indexOf('HostName');
    final countryLongIdx = cols.indexOf('CountryLong');
    final countryShortIdx = cols.indexOf('CountryShort');
    if (b64Idx < 0) return const [];

    String cell(List<String> parts, int index) =>
        index >= 0 && index < parts.length ? parts[index].trim() : '';

    final candidates = <Candidate>[];
    for (final line in lines) {
      final l = line.trim();
      if (l.isEmpty || l.startsWith('*') || l.startsWith('#')) continue;
      final parts = l.split(',');
      if (parts.length <= b64Idx) continue;
      final b64 = parts[b64Idx].trim();
      if (b64.isEmpty) continue;
      final csvPing = pingIdx >= 0 && pingIdx < parts.length
          ? (int.tryParse(parts[pingIdx].trim()) ?? 0)
          : 0;
      final decoded = decodeOvpn(b64);
      if (decoded == null || !decoded.contains('<ca>')) continue;
      final c = Candidate.fromConfig(
        configForCurrentEngine(decoded),
        fallbackIp: parts[1].trim(),
        csvPing: csvPing,
        sni: _fqdn(cell(parts, hostIdx)),
        countryCode: cell(parts, countryShortIdx).toUpperCase(),
        countryName: _displayCountry(cell(parts, countryLongIdx)),
      );
      if (c != null) {
        candidates.add(
          Candidate(
            ip: c.ip,
            port: c.port,
            protocol: c.protocol,
            csvPing: c.csvPing,
            b64: b64,
            config: c.config,
            sni: c.sni,
            countryCode: c.countryCode,
            countryName: c.countryName,
          ),
        );
      }
    }
    log('Parsed ${candidates.length} candidate endpoints from CSV');
    return _prioritize(candidates);
  }

  static List<Candidate> _fromJsonMirror(
    String body,
    void Function(String) log,
  ) {
    try {
      final List<dynamic> servers = jsonDecode(body) as List<dynamic>;
      final candidates = <Candidate>[];
      for (final raw in servers) {
        if (raw is! Map<String, dynamic>) continue;
        final b64 = raw['OpenVPN_ConfigData_Base64']?.toString() ?? '';
        if (b64.isEmpty) continue;
        final csvPing = int.tryParse(raw['Ping']?.toString() ?? '') ?? 0;
        final hostName =
            raw['#HostName']?.toString() ?? raw['HostName']?.toString() ?? '';
        final decoded = decodeOvpn(b64);
        if (decoded == null || !decoded.contains('<ca>')) continue;
        final c = Candidate.fromConfig(
          configForCurrentEngine(decoded),
          fallbackIp: raw['IP']?.toString(),
          csvPing: csvPing,
          sni: _fqdn(hostName),
          countryCode: (raw['CountryShort']?.toString() ?? '').toUpperCase(),
          countryName: _displayCountry(raw['CountryLong']?.toString() ?? ''),
        );
        if (c != null) {
          candidates.add(
            Candidate(
              ip: c.ip,
              port: c.port,
              protocol: c.protocol,
              csvPing: c.csvPing,
              b64: b64,
              config: c.config,
              sni: c.sni,
              countryCode: c.countryCode,
              countryName: c.countryName,
            ),
          );
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

/// The last live catalog, on disk.
///
/// When every source fails on a filtered carrier the app still has to dial
/// something after a restart; the bundled asset can be weeks old. The cache
/// keeps the newest 60 already-prioritised endpoints for a week. Only the
/// engine-ready config is stored — it is per-platform and the original base64
/// would double the size for no benefit.
class VpnGateCatalogCache {
  VpnGateCatalogCache._();

  static const _key = 'bulb_vpngate_catalog_v1';
  static const _maxEntries = 60;
  static const _maxAgeMs = 7 * 24 * 60 * 60 * 1000;

  static Future<void> save(List<Candidate> candidates, {DateTime? now}) async {
    if (candidates.isEmpty) return;
    try {
      final entries = <Map<String, Object>>[];
      for (final c in candidates) {
        if (entries.length >= _maxEntries) break;
        if (c.ip.isEmpty || c.config.isEmpty) continue;
        entries.add({
          'ip': c.ip,
          'port': c.port,
          'proto': c.protocol,
          'ping': c.csvPing,
          'sni': c.sni,
          'cc': c.countryCode,
          'cn': c.countryName,
          'config': c.config,
        });
      }
      if (entries.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'at': (now ?? DateTime.now()).millisecondsSinceEpoch,
          'entries': entries,
        }),
      );
    } catch (_) {}
  }

  static Future<List<Candidate>> load({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final at = int.tryParse(decoded['at']?.toString() ?? '') ?? 0;
      if (at <= 0) return const [];
      final age = (now ?? DateTime.now()).millisecondsSinceEpoch - at;
      if (age > _maxAgeMs) return const [];
      final entries = decoded['entries'];
      if (entries is! List) return const [];
      final candidates = <Candidate>[];
      for (final entry in entries) {
        if (entry is! Map) continue;
        final ip = entry['ip']?.toString() ?? '';
        final config = entry['config']?.toString() ?? '';
        if (ip.isEmpty || config.isEmpty) continue;
        candidates.add(
          Candidate(
            ip: ip,
            port: int.tryParse(entry['port']?.toString() ?? '') ?? 1194,
            protocol: entry['proto']?.toString() == 'tcp' ? 'tcp' : 'udp',
            csvPing: int.tryParse(entry['ping']?.toString() ?? '') ?? 0,
            b64: '',
            config: config,
            sni: entry['sni']?.toString() ?? '',
            countryCode: (entry['cc']?.toString() ?? '').toUpperCase(),
            countryName: entry['cn']?.toString() ?? '',
          ),
        );
      }
      return candidates;
    } catch (_) {
      return const [];
    }
  }
}
