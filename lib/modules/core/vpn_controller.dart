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

  static const bool _useTestConfig = true;
  VpnService get vpnService => _vpnService;

  // ---------------------------------------------------------------------------
  // Rotation tuning
  // ---------------------------------------------------------------------------
  /// Time we allow one candidate to reach `connected` before moving on.
  static const _attemptWatchdog = Duration(seconds: 10);
  /// Per-candidate TCP reachability probe budget.
  static const _probeTimeout = Duration(milliseconds: 800);
  /// How many candidates we actually try (probe-ranked) per connect press.
  static const _maxAttempts = 3;
  /// How many candidates we probe at most (ranked by measured ping first).
  static const _maxProbe = 6;
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
    _log.addLog('[VpnController] Timezone offset: ${offset.inMinutes / 60.0} hours');
    try {
      await _vpnService.initialize();
      _initialized = true;
      _log.addLog('[VpnController] VpnController initialized successfully');
      if (_useTestConfig) {
        _log.addLog('[VpnController] Catalog refresh is on');
      }
    } catch (e, stackTrace) {
      _log.addLog('[VpnController] ERROR initializing: $e');
      try { FirebaseCrashlytics.instance.recordError(e, stackTrace, reason: 'VpnController initialize', fatal: false); } catch (_) {}
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
    _log.addLog('[VpnController] handleConnectionButton called, current status: ${connectionState.status}');
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
        _log.addLog('[VpnController] Unknown status: ${connectionState.status}');
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
    final withAuth = ensureIcsOpenVpnCompat(ensureAuthUserPass(decoded));
    return Candidate.fromConfig(withAuth, fallbackIp: fallbackIp, csvPing: csvPing);
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
      await prefs.setString(_lastGoodKey, jsonEncode({'ip': c.ip, 'port': c.port, 'b64': c.b64}));
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
      final remembered = await _readLastSsl();
      if (remembered != null) {
        picked.add(remembered);
        seenSubnet.add(_subnet(remembered.dial));
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
        _log.addLog('[VpnController] SoftEther trying ${picked.length} measured relays');
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
          _log.addLog('[VpnController] Last-good server: ${map['ip']}:${map['port']}');
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
        final ping = live != null && live.status == PingStatus.ok ? live.ms : s.ping;
        final c = _candidateFromB64(s.openVpnConfigBase64, fallbackIp: s.ip, csvPing: ping);
        if (c != null) fromCache.add(c);
      }
      addAll(fromCache);
    } catch (e) {
      _log.addLog('[VpnController] Cached server list unavailable: $e');
    }

    // 3) Network refresh only when nothing local is connectable.
    if (_useTestConfig && candidates.isEmpty) {
      final fresh = await VpnGateCandidates.fetchAll(
        onLog: (m) => _log.addLog('[VpnController] $m'),
      ).timeout(const Duration(seconds: 6), onTimeout: () => const []);
      addAll(fresh);
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

  int _endpointRank(Candidate c) {
    final ping = c.csvPing <= 0 ? 9999 : c.csvPing;
    final tcp = c.protocol == 'tcp' ? 0 : 100000;
    // Port 443 often accepts the TCP handshake on this carrier and then
    // never finishes authentication. Prefer the relay's own port.
    final portBias = c.port == 443 ? 500 : 0;
    return tcp + portBias + ping;
  }

  /// One endpoint per /24 per pass, best endpoint first inside each subnet.
  /// A single low-ping cluster (one operator, same dead path) otherwise
  /// fills the whole probe and attempt budget.
  List<Candidate> _spreadSubnets(List<Candidate> input, int limit) {
    final sorted = [...input]..sort((a, b) => _endpointRank(a).compareTo(_endpointRank(b)));
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
    _log.addLog('[VpnController] Probing ${shortlist.length} candidate endpoints across $subnets subnets...');

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

    final orderedReachable = _spreadSubnets(results, results.length);
    final orderedDead = _spreadSubnets(dead, dead.length);
    _log.addLog('[VpnController] Probe results: ${orderedReachable.length} reachable, ${orderedDead.length} dead');
    for (final c in orderedReachable.take(5)) {
      _log.addLog('[VpnController]   reachable: ${c.ip}:${c.port} (ping ${c.csvPing})');
    }
    if (orderedReachable.isEmpty) {
      for (final c in orderedDead.take(5)) {
        _log.addLog('[VpnController]   will try (unprobed): ${c.ip}:${c.port} (ping ${c.csvPing})');
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

    if (Platform.isAndroid) {
      final ok = await _vpnService.checkAndRequestPermissions();
      _log.addLog('[VpnController] Permissions result: $ok');
      if (!ok) {
        _log.addLog('[VpnController] VPN/notification permission denied');
        try {
          await FirebaseCrashlytics.instance.recordError('VPN permission denied', StackTrace.current, fatal: false);
          await _analyticsService.logVpnFailed(ip: 'permission', ping: 0, rawStage: 'permission_denied', serverLabel: _serverLabel);
        } catch (_) {}
        connectionNotifier.setError();
        _vibrationService.vibrateError();
        return;
      }
    }

    // OpenVPN is the path that actually forwards on mobile data. SoftEther
    // is one short fallback after those attempts, not a minute of dead handshakes.
    if (Platform.isAndroid) {
      await SoftEtherVpn.disconnect();
    }

    // A picked server is tried first. It does not replace the rest of the
    // list: one stalled endpoint used to end the whole connect.
    final preferred = <Candidate>[];
    if (_serverConfig != null) {
      _log.addLog('[VpnController] Selected server tried first: $_serverLabel');
      final c = _candidateFromB64(base64Encode(utf8.encode(_serverConfig!)));
      if (c != null) {
        preferred.add(c);
        final alt = Candidate.withPort(c, 443);
        if (alt != null) preferred.add(alt);
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
      try { await _analyticsService.logVpnFailed(ip: 'no_server', ping: 0, rawStage: 'no_config', serverLabel: _serverLabel); } catch (_) {}
      connectionNotifier.setError();
      _vibrationService.vibrateError();
      return;
    }

    final ranked = await _rankByReachability(candidates);
    if (preferred.isNotEmpty) {
      final first = preferred.first;
      ranked.removeWhere((candidate) => candidate.ip == first.ip && candidate.port == first.port);
      ranked.insert(0, first);
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
        _log.addLog('[VpnController] Attempt ${candidate.ip}:${candidate.port} (${candidate.protocol})...');
        try { FirebaseCrashlytics.instance.log('vpn attempt ${candidate.ip}:${candidate.port}'); } catch (_) {}

        final ok = await _attemptCandidate(candidate);
        if (gen != _rotationGeneration) return;

        if (ok) {
          _log.addLog('[VpnController] CONNECTED via ${candidate.ip}:${candidate.port}');
          connectionNotifier.holdEngineEvents(false);
          connectionNotifier.setConnected();
          await _saveLastGood(candidate);
          await VpnSessionStore.save(
            label: '${candidate.ip}:${candidate.port}',
            host: candidate.ip,
          );
          try {
            await _analyticsService.logVpnConnected('vpn_gate', '${candidate.ip}:${candidate.port}', 0);
          } catch (_) {}
          // statusStream already flipped the notifier to connected.
          return;
        }
        _log.addLog('[VpnController] Attempt failed: ${candidate.ip}:${candidate.port}, moving to next candidate');
        try {
          await _analyticsService.logVpnFailed(ip: candidate.ip, ping: candidate.csvPing, rawStage: 'candidate_timeout', serverLabel: _serverLabel);
        } catch (_) {}
    }

    if (gen != _rotationGeneration) return;
    if (Platform.isAndroid && await _tryOneSoftEther(container, connectionNotifier)) {
      return;
    }
    if (gen == _rotationGeneration) {
      final tried = ranked.take(_maxAttempts).length;
      _log.addLog('[VpnController] All $tried attempts failed');
      connectionNotifier.setError();
      _vibrationService.vibrateError();
      try {
        await _analyticsService.logVpnFailed(ip: 'rotation', ping: 0, rawStage: 'all_candidates_failed', serverLabel: _serverLabel);
      } catch (_) {}
    }
  }

  /// One SoftEther dial, used only after OpenVPN misses. Returns true when up.
  Future<bool> _tryOneSoftEther(
    ProviderContainer container,
    ConnectionStateNotifier connectionNotifier,
  ) async {
    final sslGen = _rotationGeneration;
    final targets = await _fastestSoftEtherTargets(container);
    if (targets.isEmpty || sslGen != _rotationGeneration) return false;
    final target = targets.first;
    connectionNotifier.setConnecting();
    _log.addLog('[VpnController] SoftEther fallback ${target.dial}');
    container.read(softEtherHostProvider.notifier).state =
        '${target.sni} · ${target.dial}';
    final result = await SoftEtherVpn.connect(dial: target.dial, sni: target.sni);
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
    _log.addLog('[VpnController] SoftEther fallback failed: ${result.detail}');
    connectionNotifier.holdEngineEvents(false);
    return false;
  }

  /// Connects to one candidate and waits up to [_attemptWatchdog] for the
  /// engine to report `connected`. Returns false on timeout / engine failure.
  Future<bool> _attemptCandidate(Candidate candidate) async {
    final completer = Completer<bool>();
    late final StreamSubscription<engine.ConnectionStatus> sub;
    late final Timer watchdog;

    void finish(bool result) {
      if (!completer.isCompleted) {
        watchdog.cancel();
        sub.cancel();
        completer.complete(result);
      }
    }

    sub = _vpnService.statusStream().listen((engine.ConnectionStatus status) {
      switch (status) {
        case engine.ConnectionStatus.connected:
          _log.addLog('[VpnController] Engine reported CONNECTED');
          finish(true);
          break;
        case engine.ConnectionStatus.disconnected:
          _log.addLog('[VpnController] Engine reported DISCONNECTED during attempt');
          finish(false);
          break;
        default:
          break;
      }
    }, onError: (Object e) {
      _log.addLog('[VpnController] statusStream error: $e');
      finish(false);
    });

    watchdog = Timer(_attemptWatchdog, () {
      _log.addLog('[VpnController] Watchdog fired for ${candidate.ip}:${candidate.port} (no tunnel in ${_attemptWatchdog.inSeconds}s)');
      finish(false);
    });

    try {
      await _vpnService.connect(
        config: candidate.config,
        name: 'BULBVPN',
      );
    } catch (e, stackTrace) {
      _log.addLog('[VpnController] connect() threw: $e');
      try { FirebaseCrashlytics.instance.recordError(e, stackTrace, reason: 'VpnService.connect ${candidate.ip}', fatal: false); } catch (_) {}
      finish(false);
      return await completer.future;
    }

    final result = await completer.future;
    if (!result) {
      // Tear down this attempt before the next one starts.
      try {
        await _vpnService.disconnect();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return result;
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
