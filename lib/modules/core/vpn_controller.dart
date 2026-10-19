import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Socket;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:openvpn_dart/vpn_status.dart' as engine;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bulbvpn/core/data/local/vpn_data/vpn_data.dart';
import 'package:bulbvpn/modules/core/vpn_service.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:bulbvpn/shared/providers/flow_line_provider.dart';
import 'package:bulbvpn/shared/providers/group_provider.dart';
import 'package:bulbvpn/shared/providers/logs_provider.dart';
import 'package:bulbvpn/shared/services/firebase_analytics_service.dart';
import 'package:bulbvpn/shared/services/vibration_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bulbvpn/modules/core/network.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/modules/core/doh_resolver.dart';
import 'package:bulbvpn/modules/core/vpn_gate_candidates.dart';
import 'package:bulbvpn/modules/core/vpn_session_store.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/modules/main/presentation/screens/main_screen.dart';

class VpnController {
  VpnController._internal();
  static final VpnController _instance = VpnController._internal();
  factory VpnController() => _instance;

  final Log _log = Log();
  final VpnService _vpnService = VpnService();
  final VibrationService _vibrationService = VibrationService();
  final FirebaseAnalyticsService _analyticsService = FirebaseAnalyticsService();

  ProviderContainer? _container;
  bool _initialized = false;

  String? _serverConfig;
  String _serverLabel = '';
  String? _serverHost;
  String? _serverIp;
  String get selectedServerLabel => _serverLabel;

  void selectServerConfig(
    String config,
    String label, {
    String? hostName,
    String? ip,
  }) {
    _serverConfig = config;
    _serverLabel = label;
    _serverHost = (hostName != null && hostName.isNotEmpty) ? hostName : null;
    _serverIp = (ip != null && ip.isNotEmpty) ? ip : null;
    _log.addLog(
      '[VpnController] Selected server: $label host=${_serverHost ?? '-'} ip=${_serverIp ?? '-'}',
    );
  }

  void clearServerConfig() {
    _serverConfig = null;
    _serverLabel = '';
    _serverHost = null;
    _serverIp = null;
    _log.addLog('[VpnController] Server selection cleared (auto)');
  }

  VpnService get vpnService => _vpnService;

  // ---------------------------------------------------------------------------
  // Rotation tuning
  // ---------------------------------------------------------------------------
  /// Time we allow one candidate to reach `connected` before moving on.
  static const _androidAttemptWatchdog = Duration(seconds: 18);
  static const _appleAttemptWatchdog = Duration(seconds: 50);

  /// OpenVPN on iOS does not report connected until the extension applies
  /// tunnel settings. 10s expired while that handshake was still running.
  Duration get _attemptWatchdog => Platform.isIOS || Platform.isMacOS
      ? _appleAttemptWatchdog
      : _androidAttemptWatchdog;

  /// Per-candidate TCP reachability probe budget.
  static const _probeTimeout = Duration(milliseconds: 800);

  /// How many OpenVPN relays we dial per connect press.
  static const _maxAttempts = 8;

  /// TCP 443 hosts probed before the first dial. The proven subnet is
  /// included whole; the rest of the budget is other subnets.
  static const _maxProbe = 16;

  /// Relays in this /24 are the ones that have reached CONNECTED on the
  /// Apple OpenVPN 3 stack (TLS 1.0, TCP 443). Other VPN Gate hosts often
  /// accept the socket, print VERIFY OK, and never PUSH.
  static const _provenSubnet = '219.100.37';

  /// The relay that reached CONNECTED on the iPhone (18 Oct 19:56Z).
  static const _provenFirstIp = '219.100.37.192';
  static const _lastGoodKey = 'bulbvpn_last_good_server_v1';
  static const _lastSslKey = 'bulbvpn_last_ssl_v1';

  /// Bumped by stop/disconnect to cancel an in-flight rotation loop.
  int _rotationGeneration = 0;

  Future<void> initialize(ProviderContainer container) async {
    if (_initialized) return;
    _container = container;
    _vibrationService.init();
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    _log.addLog(
      '[VpnController] Timezone offset: ${offset.inMinutes / 60.0} hours',
    );
    try {
      await _vpnService.initialize();
      _initialized = true;
      _log.addLog('[VpnController] VpnController initialized successfully');
    } catch (e, stackTrace) {
      _log.addLog('[VpnController] ERROR initializing: $e');
      try {
        FirebaseCrashlytics.instance.recordError(
          e,
          stackTrace,
          reason: 'VpnController initialize',
          fatal: false,
        );
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> handleConnectionButton() async {
    final container = _container;
    if (container == null) {
      _log.addLog('[VpnController] Not ready');
      return;
    }
    final connectionState = container.read(connectionStateProvider);
    _log.addLog(
      '[VpnController] handleConnectionButton called, current status: ${connectionState.status}',
    );
    switch (connectionState.status) {
      case ConnectionStatus.connected:
        await _disconnect();
        return;
      case ConnectionStatus.loading:
      case ConnectionStatus.connecting:
      case ConnectionStatus.disconnecting:
        await _stopVpn();
        return;
      case ConnectionStatus.disconnected:
      case ConnectionStatus.error:
      case ConnectionStatus.noInternet:
        await _connect();
        return;
      default:
        _log.addLog(
          '[VpnController] Unknown status: ${connectionState.status}',
        );
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Candidate plumbing
  // ---------------------------------------------------------------------------

  /// Decoded config for one candidate server, with inline `auth-user-pass`.
  Candidate? _candidateFromB64(String b64, {String? fallbackIp, int? csvPing}) {
    final decoded = decodeOvpn(b64);
    if (decoded == null || !decoded.contains('<ca>')) return null;
    final withAuth = configForCurrentEngine(decoded);
    return Candidate.fromConfig(
      withAuth,
      fallbackIp: fallbackIp,
      csvPing: csvPing,
    );
  }

  Future<String?> _readLastGood() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastGoodKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLastGood(Candidate c) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastGoodKey,
        jsonEncode({'ip': c.ip, 'port': c.port, 'b64': c.b64}),
      );
    } catch (_) {}
  }

  Future<({String dial, String sni})?> _readLastSsl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastSslKey);
      if (raw != null && raw.contains('|')) {
        final parts = raw.split('|');
        if (parts[0].isNotEmpty && parts[1].isNotEmpty) {
          return (dial: parts[0], sni: parts[1]);
        }
      }
    } catch (_) {}
    final session = await VpnSessionStore.read();
    final host = session?.host ?? '';
    if (host.isEmpty) return null;
    final sni = (session?.label ?? '').split(' · ').first;
    return (dial: host, sni: sni.isEmpty ? host : sni);
  }

  Future<void> _saveLastSsl(String dial, String sni) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSslKey, '$dial|$sni');
    } catch (_) {}
  }

  /// Lowest live ping first, one host per subnet, dialed by IP so carrier DNS
  /// cannot black-hole the relay name.
  Future<List<({String dial, String sni})>> _fastestSoftEtherTargets(
    ProviderContainer container,
  ) async {
    try {
      final servers = await container.read(serversProvider.future);
      final measured = container.read(serverPingProvider).byIp;
      final ordered = sortByMeasuredPing(servers, measured);
      final picked = <({String dial, String sni})>[];
      final seenSubnet = <String>{};
      // Relays that finished a SoftEther session on this network.
      const preferred = <({String dial, String sni})>[
        (dial: '219.100.37.105', sni: 'public-vpn-139.opengw.net'),
        (dial: '219.100.37.179', sni: 'public-vpn-187.opengw.net'),
        (dial: '219.100.37.192', sni: 'public-vpn-192.opengw.net'),
      ];
      for (final target in preferred) {
        picked.add(target);
        seenSubnet.add(_subnet(target.dial));
      }
      final remembered = await _readLastSsl();
      if (remembered != null && seenSubnet.add(_subnet(remembered.dial))) {
        picked.add(remembered);
      }
      for (final server in ordered) {
        if (server.ip.isEmpty) continue;
        final subnet = _subnet(server.ip);
        if (!seenSubnet.add(subnet)) continue;
        final sni = SoftEtherVpn.fqdn(server.hostName);
        picked.add((dial: server.ip, sni: sni.isEmpty ? server.ip : sni));
        if (picked.length >= 8) break;
      }
      if (picked.isNotEmpty) {
        _log.addLog(
          '[VpnController] SoftEther trying ${picked.length} measured relays',
        );
        return picked;
      }
    } catch (e) {
      _log.addLog('[VpnController] SoftEther target list failed: $e');
    }
    final hosts = await SoftEtherVpn.hosts();
    return [for (final host in hosts) (dial: host, sni: host)];
  }

  /// Builds the full candidate list: last-good first, then the on-device
  /// catalog, then a network fetch when the catalog is empty.
  /// (official CSV, then mirror), then the UI-cached server list.
  Future<List<Candidate>> _buildCandidates(ProviderContainer container) async {
    final candidates = <Candidate>[];
    final seen = <String>{};

    void addAll(Iterable<Candidate> list) {
      for (final c in list) {
        final key = '${c.ip}:${c.port}';
        if (seen.contains(key)) continue;
        seen.add(key);
        candidates.add(c);
      }
    }

    // 1) Last known-good server: fastest path on stable networks.
    final lastGoodRaw = await _readLastGood();
    if (lastGoodRaw != null) {
      try {
        final map = jsonDecode(lastGoodRaw) as Map<String, dynamic>;
        final c = _candidateFromB64(map['b64'] as String);
        if (c != null) {
          addAll([c]);
          _log.addLog(
            '[VpnController] Last-good server: ${map['ip']}:${map['port']}',
          );
        }
      } catch (_) {}
    }

    // 2) On-device catalog, ordered by the ping this phone just measured.
    try {
      final cachedServers = await container.read(serversProvider.future);
      final measured = container.read(serverPingProvider).byIp;
      final ordered = sortByMeasuredPing(cachedServers, measured);
      final fromCache = <Candidate>[];
      for (final s in ordered) {
        if (s.openVpnConfigBase64.isEmpty) continue;
        final live = measured[s.ip];
        final ping = live != null && live.status == PingStatus.ok
            ? live.ms
            : s.ping;
        final c = _candidateFromB64(
          s.openVpnConfigBase64,
          fallbackIp: s.ip,
          csvPing: ping,
        );
        if (c != null) fromCache.add(c);
      }
      addAll(fromCache);
    } catch (e) {
      _log.addLog('[VpnController] Cached server list unavailable: $e');
    }

    return candidates;
  }

  Future<bool> _probe(String ip, int port) {
    return Socket.connect(ip, port, timeout: _probeTimeout)
        .then((s) {
          s.destroy();
          return true;
        })
        .catchError((_) => false);
  }

  String _subnet(String ip) {
    final parts = ip.split('.');
    if (parts.length < 3) return ip;
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  bool _isProven(Candidate c) => _subnet(c.ip) == _provenSubnet;

  int _endpointRank(Candidate c) {
    if (c.ip == _provenFirstIp) return -1;
    final ping = c.csvPing <= 0 ? 9999 : c.csvPing;
    final tcp = c.protocol == 'tcp' ? 0 : 100000;
    // Non-443 ports accept TCP and then never finish. The relays that
    // reach CONNECTED are TCP 443 inside [_provenSubnet].
    final provenBias = _isProven(c) ? 0 : 50000;
    final portBias = c.port == 443 ? 0 : 800;
    return tcp + provenBias + portBias + ping;
  }

  /// One TCP 443 profile per relay. SoftEther listens there even when the
  /// published `.ovpn` uses a random port that stalls after VERIFY OK.
  List<Candidate> _tcp443DialList(List<Candidate> input) {
    final byIp = <String, Candidate>{};
    for (final candidate in input) {
      final on443 = candidate.protocol == 'tcp' && candidate.port == 443
          ? candidate
          : Candidate.withPort(candidate, 443);
      if (on443 == null) continue;
      byIp.putIfAbsent(on443.ip, () => on443);
    }
    final donor = byIp.values.cast<Candidate?>().firstWhere(
      (candidate) => candidate != null && _isProven(candidate),
      orElse: () => byIp.values.isEmpty ? null : byIp.values.first,
    );
    if (donor != null && !byIp.containsKey(_provenFirstIp)) {
      final pinned = _rewriteRemote(donor, _provenFirstIp);
      if (pinned != null) byIp[_provenFirstIp] = pinned;
    }
    final ordered = byIp.values.toList()
      ..sort((a, b) {
        if (a.ip == _provenFirstIp) return -1;
        if (b.ip == _provenFirstIp) return 1;
        return _endpointRank(a).compareTo(_endpointRank(b));
      });
    final proven = ordered.where(_isProven).take(8);
    final others = ordered.where((c) => !_isProven(c)).take(4);
    return [...proven, ...others];
  }

  /// Same OpenVPN profile, different `remote` address.
  Candidate? _rewriteRemote(Candidate donor, String ip) {
    final replaced = donor.config.replaceFirstMapped(
      RegExp(r'^(\s*remote\s+)\S+(\s+\d+)', multiLine: true),
      (match) => '${match.group(1)}$ip${match.group(2)}',
    );
    if (replaced == donor.config) return null;
    return Candidate(
      ip: ip,
      port: 443,
      protocol: 'tcp',
      csvPing: 0,
      b64: donor.b64,
      config: replaced,
    );
  }

  /// One endpoint per /24 per pass, best endpoint first inside each subnet.
  /// A single low-ping cluster (one operator, same dead path) otherwise
  /// fills the whole probe and attempt budget.
  List<Candidate> _spreadSubnets(List<Candidate> input, int limit) {
    final sorted = [...input]
      ..sort((a, b) => _endpointRank(a).compareTo(_endpointRank(b)));
    final groups = <String, List<Candidate>>{};
    for (final candidate in sorted) {
      groups.putIfAbsent(_subnet(candidate.ip), () => []).add(candidate);
    }
    final picked = <Candidate>[];
    final index = {for (final key in groups.keys) key: 0};
    while (picked.length < limit) {
      var added = false;
      for (final entry in groups.entries) {
        final i = index[entry.key]!;
        if (i >= entry.value.length) continue;
        picked.add(entry.value[i]);
        index[entry.key] = i + 1;
        added = true;
        if (picked.length >= limit) break;
      }
      if (!added) break;
    }
    return picked;
  }

  /// Probes candidates in parallel batches. Reachable endpoints are tried
  /// first, and both groups are spread across subnets.
  Future<List<Candidate>> _rankByReachability(List<Candidate> input) async {
    final shortlist = _spreadSubnets(input, _maxProbe);
    final subnets = shortlist.map((c) => _subnet(c.ip)).toSet().length;
    _log.addLog(
      '[VpnController] Probing ${shortlist.length} candidate endpoints across $subnets subnets...',
    );

    final results = <Candidate>[]; // reachable
    final dead = <Candidate>[]; // unreachable

    for (var i = 0; i < shortlist.length; i += 10) {
      final batch = shortlist.sublist(i, (i + 10).clamp(0, shortlist.length));
      final probes = await Future.wait([
        for (final c in batch) _probe(c.ip, c.port),
      ]);
      for (var j = 0; j < batch.length; j++) {
        if (probes[j]) {
          results.add(batch[j]);
        } else {
          dead.add(batch[j]);
        }
      }
    }

    List<Candidate> provenFirst(List<Candidate> list) {
      final proven = list.where(_isProven);
      final rest = list.where((c) => !_isProven(c));
      return [...proven, ...rest];
    }

    final orderedReachable = provenFirst(results);
    final orderedDead = provenFirst(dead);
    _log.addLog(
      '[VpnController] Probe results: ${orderedReachable.length} reachable, ${orderedDead.length} dead',
    );
    for (final c in orderedReachable.take(5)) {
      _log.addLog(
        '[VpnController]   reachable: ${c.ip}:${c.port} (ping ${c.csvPing})',
      );
    }
    if (orderedReachable.isEmpty) {
      for (final c in orderedDead.take(5)) {
        _log.addLog(
          '[VpnController]   will try (unprobed): ${c.ip}:${c.port} (ping ${c.csvPing})',
        );
      }
    }
    return [...orderedReachable, ...orderedDead];
  }

  // ---------------------------------------------------------------------------
  // Connect flow
  // ---------------------------------------------------------------------------

  Future<void> _connect() async {
    final container = _container;
    if (container == null) return;
    final connectionNotifier = container.read(connectionStateProvider.notifier);
    final loggerNotifier = container.read(loggerStateProvider.notifier);
    _log.addLog('[VpnController] Starting connection process...');
    connectionNotifier.setLoading();
    loggerNotifier.setLoading();
    _vibrationService.vibrateHeartbeat();

    final networkIsConnected = await NetworkStatus.checkConnectivity();
    if (!networkIsConnected) {
      _log.addLog('[VpnController] No internet connection');
      connectionNotifier.setNoInternet();
      _vibrationService.vibrateError();
      return;
    }

    // Profile install shows the system Allow dialog and must finish before any
    // candidate watchdog starts — otherwise a 10s timer cancels the prompt.
    if (Platform.isIOS || Platform.isMacOS) {
      final profile = await _vpnService.ensureAppleVpnProfile();
      _log.addLog('[VpnController] Apple VPN profile ready: $profile');
      if (!profile) {
        connectionNotifier.setError();
        _vibrationService.vibrateError();
        return;
      }
    }

    if (Platform.isAndroid) {
      final ok = await _vpnService.checkAndRequestPermissions();
      _log.addLog('[VpnController] Permissions result: $ok');
      if (!ok) {
        _log.addLog('[VpnController] VPN/notification permission denied');
        try {
          await FirebaseCrashlytics.instance.recordError(
            'VPN permission denied',
            StackTrace.current,
            fatal: false,
          );
          await _analyticsService.logVpnFailed(
            ip: 'permission',
            ping: 0,
            rawStage: 'permission_denied',
            serverLabel: _serverLabel,
          );
        } catch (_) {}
        connectionNotifier.setError();
        _vibrationService.vibrateError();
        return;
      }
    }

    // Fresh installs on 19 Oct 2026: macOS connected in one SoftEther dial
    // to 219.100.37.105. iPhone, iPad, and Android spent the whole attempt
    // on OpenVPN timeouts and never reached that session. Dial SoftEther
    // first on every platform. OpenVPN stays as the backup.
    if (Platform.isIOS || Platform.isMacOS) {
      if (await _tryAppleSoftEther(container, connectionNotifier)) {
        return;
      }
    }
    if (Platform.isAndroid) {
      await SoftEtherVpn.disconnect();
      if (await _tryOneSoftEther(container, connectionNotifier)) {
        return;
      }
    }

    // A picked server is tried first. It does not replace the rest of the
    // list: one stalled endpoint used to end the whole connect.
    final preferred = <Candidate>[];
    if (_serverConfig != null) {
      _log.addLog('[VpnController] Selected server tried first: $_serverLabel');
      final c = _candidateFromB64(base64Encode(utf8.encode(_serverConfig!)));
      if (c != null) {
        // UDP rarely dials on filtered paths. TCP 443 is the SoftEther
        // listener that finishes OpenVPN; keep the profile port as a backup.
        final on443 = c.port == 443 ? c : (Candidate.withPort(c, 443) ?? c);
        preferred.add(on443);
        if (c.port != 443) {
          final tcp = Candidate.asTcp(c) ?? c;
          preferred.add(tcp);
        }
      }
    }

    final fetchGen = ++_rotationGeneration;
    final built = await _buildCandidates(container);
    if (fetchGen != _rotationGeneration) return;

    final seen = <String>{};
    final candidates = <Candidate>[];
    void addCandidate(Candidate candidate) {
      if (seen.add('${candidate.ip}:${candidate.port}')) {
        candidates.add(candidate);
      }
    }

    for (final candidate in preferred) {
      addCandidate(candidate);
    }
    for (final candidate in built) {
      addCandidate(candidate);
    }
    if (candidates.isEmpty) {
      _log.addLog('[VpnController] ERROR: No server config available');
      try {
        await _analyticsService.logVpnFailed(
          ip: 'no_server',
          ping: 0,
          rawStage: 'no_config',
          serverLabel: _serverLabel,
        );
      } catch (_) {}
      connectionNotifier.setError();
      _vibrationService.vibrateError();
      return;
    }

    final dialable = _tcp443DialList(candidates);
    final ranked = await _rankByReachability(
      dialable.isEmpty ? candidates : dialable,
    );
    final pinned = ranked.where((c) => c.ip == _provenFirstIp).toList();
    if (pinned.isNotEmpty) {
      ranked.removeWhere((c) => c.ip == _provenFirstIp);
      ranked.insert(0, pinned.first);
    }
    if (ranked.isEmpty) {
      _log.addLog('[VpnController] ERROR: no candidates after ranking');
      connectionNotifier.setError();
      _vibrationService.vibrateError();
      return;
    }

    final gen = ++_rotationGeneration;
    for (final candidate in ranked.take(_maxAttempts)) {
      if (gen != _rotationGeneration) {
        _log.addLog('[VpnController] Rotation cancelled');
        return;
      }
      connectionNotifier.setConnecting();
      container.read(softEtherHostProvider.notifier).state =
          '${candidate.ip}:${candidate.port}';
      _log.addLog(
        '[VpnController] Attempt ${candidate.ip}:${candidate.port} (${candidate.protocol})...',
      );
      try {
        FirebaseCrashlytics.instance.log(
          'vpn attempt ${candidate.ip}:${candidate.port}',
        );
      } catch (_) {}

      final ok = await _attemptCandidate(candidate);
      if (gen != _rotationGeneration) return;

      if (ok) {
        _log.addLog(
          '[VpnController] CONNECTED via ${candidate.ip}:${candidate.port}',
        );
        connectionNotifier.holdEngineEvents(false);
        connectionNotifier.setConnected();
        await _saveLastGood(candidate);
        await VpnSessionStore.save(
          label: '${candidate.ip}:${candidate.port}',
          host: candidate.ip,
        );
        try {
          await _analyticsService.logVpnConnected(
            'vpn_gate',
            '${candidate.ip}:${candidate.port}',
            0,
          );
        } catch (_) {}
        // statusStream already flipped the notifier to connected.
        return;
      }
      _log.addLog(
        '[VpnController] Attempt failed: ${candidate.ip}:${candidate.port}, moving to next candidate',
      );
      try {
        await _analyticsService.logVpnFailed(
          ip: candidate.ip,
          ping: candidate.csvPing,
          rawStage: 'candidate_timeout',
          serverLabel: _serverLabel,
        );
      } catch (_) {}
    }

    if (gen != _rotationGeneration) return;
    final tried = ranked.take(_maxAttempts).length;
    _log.addLog('[VpnController] All $tried attempts failed');
    connectionNotifier.setError();
    _vibrationService.vibrateError();
    try {
      await _analyticsService.logVpnFailed(
        ip: 'rotation',
        ping: 0,
        rawStage: 'all_candidates_failed',
        serverLabel: _serverLabel,
      );
    } catch (_) {}
  }

  /// SoftEther inside the Apple packet tunnel. The profile is a marker the
  /// extension reads; OpenVPN never sees it when this path connects.
  Future<bool> _tryAppleSoftEther(
    ProviderContainer container,
    ConnectionStateNotifier connectionNotifier,
  ) async {
    final generation = _rotationGeneration;
    final targets = await _fastestSoftEtherTargets(container);
    if (targets.isEmpty || generation != _rotationGeneration) return false;
    for (final target in targets.take(3)) {
      if (generation != _rotationGeneration) return false;
      connectionNotifier.setConnecting();
      _log.addLog('[VpnController] Apple SoftEther ${target.dial}');
      final config =
          '''
# bulb-host ${target.dial}
# bulb-sni ${target.sni}
client
dev tun
proto tcp
remote ${target.dial} 443
nobind
<auth-user-pass>
vpn
vpn
</auth-user-pass>
''';
      final candidate = Candidate(
        ip: target.dial,
        port: 443,
        protocol: 'tcp',
        csvPing: 0,
        b64: '',
        config: config,
      );
      final ok = await _attemptCandidate(candidate);
      if (generation != _rotationGeneration) return false;
      if (ok) {
        _log.addLog('[VpnController] CONNECTED via SoftEther ${target.dial}');
        final label = '${target.sni} · ${target.dial}';
        await VpnSessionStore.save(label: label, host: target.dial);
        await _saveLastSsl(target.dial, target.sni);
        connectionNotifier.holdEngineEvents(false);
        connectionNotifier.setConnected();
        return true;
      }
      _log.addLog('[VpnController] Apple SoftEther failed ${target.dial}');
    }
    return false;
  }

  /// SoftEther dials tried before OpenVPN. Returns true when one comes up.
  Future<bool> _tryOneSoftEther(
    ProviderContainer container,
    ConnectionStateNotifier connectionNotifier,
  ) async {
    final sslGen = _rotationGeneration;
    final targets = await _fastestSoftEtherTargets(container);
    if (targets.isEmpty || sslGen != _rotationGeneration) return false;
    for (final target in targets.take(3)) {
      if (sslGen != _rotationGeneration) return false;
      connectionNotifier.setConnecting();
      _log.addLog('[VpnController] SoftEther fallback ${target.dial}');
      container.read(softEtherHostProvider.notifier).state =
          '${target.sni} · ${target.dial}';
      final result = await SoftEtherVpn.connect(
        dial: target.dial,
        sni: target.sni,
      );
      if (sslGen != _rotationGeneration) return false;
      if (result.ok || result.detail == 'already running') {
        _log.addLog('[VpnController] CONNECTED via SoftEther ${target.dial}');
        final label = '${target.sni} · ${target.dial}';
        container.read(softEtherHostProvider.notifier).state = label;
        await VpnSessionStore.save(label: label, host: target.dial);
        await _saveLastSsl(target.dial, target.sni);
        connectionNotifier.holdEngineEvents(true);
        connectionNotifier.setConnected();
        return true;
      }
      _log.addLog(
        '[VpnController] SoftEther fallback failed: ${result.detail}',
      );
      try {
        await SoftEtherVpn.disconnect();
      } catch (_) {}
    }
    connectionNotifier.holdEngineEvents(false);
    return false;
  }

  /// Connects to one candidate and waits up to [_attemptWatchdog] for the
  /// engine to report `connected`. Returns false on timeout / engine failure.
  ///
  /// Important: [VpnService.connect] must not gate the watchdog. On iOS,
  /// `configureVPN` → `saveToPreferences` can sit pending while NEVPN is
  /// already `.connecting`; awaiting it alone left the UI on "opening tunnel"
  /// forever even after the timer fired.
  Future<bool> _attemptCandidate(Candidate candidate) async {
    // Tear down any stuck prior dial before we listen — otherwise a
    // disconnect event from cleanup would finish(false) immediately.
    try {
      await _vpnService.disconnect();
    } catch (_) {}
    await _waitUntilNotConnecting();

    final dial = await _withDohResolved(candidate);

    final completer = Completer<bool>();
    late final StreamSubscription<engine.ConnectionStatus> sub;
    late final Timer watchdog;
    // Ignore disconnect until connect has been requested (NE may replay idle).
    var armed = false;

    void finish(bool result) {
      if (!completer.isCompleted) {
        watchdog.cancel();
        sub.cancel();
        completer.complete(result);
      }
    }

    sub = _vpnService.statusStream().listen(
      (engine.ConnectionStatus status) {
        switch (status) {
          case engine.ConnectionStatus.connected:
            _log.addLog('[VpnController] Engine reported CONNECTED');
            finish(true);
            break;
          case engine.ConnectionStatus.disconnected:
            if (!armed) return;
            _log.addLog(
              '[VpnController] Engine reported DISCONNECTED during attempt',
            );
            finish(false);
            break;
          case engine.ConnectionStatus.connecting:
            armed = true;
            break;
          default:
            break;
        }
      },
      onError: (Object e) {
        _log.addLog('[VpnController] statusStream error: $e');
        finish(false);
      },
    );

    watchdog = Timer(_attemptWatchdog, () {
      _log.addLog(
        '[VpnController] Watchdog fired for ${dial.ip}:${dial.port} '
        '(no tunnel in ${_attemptWatchdog.inSeconds}s)',
      );
      finish(false);
    });

    // Race connect against the status/watchdog completer. A hung
    // saveToPreferences must not freeze candidate rotation.
    unawaited(() async {
      try {
        if (completer.isCompleted) return;
        armed = true;
        await _vpnService.connect(config: dial.config, name: 'BULBVPN');
        _log.addLog(
          '[VpnController] connect() returned for ${dial.ip}:${dial.port}',
        );
      } catch (e, stackTrace) {
        _log.addLog('[VpnController] connect() threw: $e');
        try {
          await FirebaseCrashlytics.instance.recordError(
            e,
            stackTrace,
            reason: 'VpnService.connect ${dial.ip}',
            fatal: false,
          );
        } catch (_) {}
        finish(false);
      }
    }());

    final result = await completer.future;
    if (!result) {
      try {
        await _vpnService.disconnect();
      } catch (_) {}
      await _waitUntilNotConnecting();
    }
    return result;
  }

  /// Prefer IP literals in the OpenVPN `remote` line via DoH when the profile
  /// still names a hostname (blocked or poisoned system DNS).
  Future<Candidate> _withDohResolved(Candidate candidate) async {
    final host = DohResolver.remoteHost(candidate.config) ?? candidate.ip;
    if (DohResolver.isIpv4(host)) return candidate;
    final ip = await DohResolver.resolve(host);
    if (ip == null) {
      _log.addLog('[VpnController] DoH miss for relay host');
      return candidate;
    }
    _log.addLog('[VpnController] DoH resolved relay → $ip');
    return Candidate(
      ip: ip,
      port: candidate.port,
      protocol: candidate.protocol,
      csvPing: candidate.csvPing,
      b64: candidate.b64,
      config: DohResolver.rewriteRemoteHost(candidate.config, ip),
    );
  }

  /// Polls until the engine leaves connecting, or a short budget expires.
  Future<void> _waitUntilNotConnecting() async {
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await _vpnService.getStatus();
        if (status != engine.ConnectionStatus.connecting &&
            status != engine.ConnectionStatus.disconnecting) {
          return;
        }
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Drops the current tunnel and opens the relay that is selected now.
  Future<void> reconnect() async {
    final container = _container;
    if (container == null) return;
    _rotationGeneration++;
    _log.addLog('[VpnController] Switching relay to ${_serverHost ?? 'auto'}');
    container.read(connectionStateProvider.notifier).holdEngineEvents(false);
    container.read(softEtherHostProvider.notifier).state = null;
    await SoftEtherVpn.disconnect();
    await _connect();
  }

  Future<void> _stopVpn() async {
    final container = _container;
    if (container == null) return;
    final connectionNotifier = container.read(connectionStateProvider.notifier);
    _log.addLog('[VpnController] Stopping VPN...');
    _rotationGeneration++;
    connectionNotifier.holdEngineEvents(false);
    connectionNotifier.setDisconnecting();
    container.read(softEtherHostProvider.notifier).state = null;
    await SoftEtherVpn.disconnect();
    await _vpnService.disconnect();
    await VpnSessionStore.clear();
    _clearData(container);
    connectionNotifier.setDisconnected();
  }

  Future<void> _disconnect() async {
    final container = _container;
    if (container == null) return;
    final connectionNotifier = container.read(connectionStateProvider.notifier);
    final vpnData = await container.read(vpnDataProvider.future);
    _log.addLog('[VpnController] Disconnecting VPN...');
    _rotationGeneration++;
    connectionNotifier.holdEngineEvents(false);
    connectionNotifier.setDisconnecting();
    container.read(softEtherHostProvider.notifier).state = null;
    await SoftEtherVpn.disconnect();
    await _vpnService.disconnect();
    await VpnSessionStore.clear();
    _clearData(container);
    vpnData.disableVPN();
    connectionNotifier.setDisconnected();
    _analyticsService.logVpnDisconnected();
  }

  void _clearData(ProviderContainer container) {
    final groupNotifier = container.read(groupStateProvider.notifier);
    groupNotifier.setGroupName('');
    container.read(flowLineStepProvider.notifier).setTotalSteps(0);
    container.read(flowLineStepProvider.notifier).setStep(0);
  }

  void dispose() {
    _log.addLog('[VpnController] Disposing...');
    _rotationGeneration++;
    _vpnService.dispose();
    _initialized = false;
  }
}
