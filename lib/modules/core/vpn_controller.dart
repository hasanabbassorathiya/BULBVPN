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
  String get selectedServerLabel => _serverLabel;

  void selectServerConfig(String config, String label, {String? hostName}) {
    _serverConfig = config;
    _serverLabel = label;
    _serverHost = (hostName != null && hostName.isNotEmpty) ? hostName : null;
    _log.addLog('[VpnController] Selected server: $label host=${_serverHost ?? '-'} (${config.length} chars)');
  }

  void clearServerConfig() {
    _serverConfig = null;
    _serverLabel = '';
    _serverHost = null;
    _log.addLog('[VpnController] Server selection cleared (auto)');
  }

  static const bool _useTestConfig = true;
  VpnService get vpnService => _vpnService;

  // ---------------------------------------------------------------------------
  // Rotation tuning
  // ---------------------------------------------------------------------------
  /// Time we allow one candidate to reach `connected` before moving on.
  static const _attemptWatchdog = Duration(seconds: 25);
  /// Per-candidate TCP reachability probe budget.
  static const _probeTimeout = Duration(milliseconds: 2500);
  /// How many candidates we actually try (probe-ranked) per connect press.
  static const _maxAttempts = 12;
  /// How many candidates we probe at most (ranked by CSV ping first).
  static const _maxProbe = 24;
  static const _lastGoodKey = 'bulbvpn_last_good_server_v1';

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
        _log.addLog('[VpnController] TEST MODE ENABLED - Will fetch fresh VPN Gate config');
      }
    } catch (e, stackTrace) {
      _log.addLog('[VpnController] ERROR initializing: $e');
      try { FirebaseCrashlytics.instance.recordError(e, stackTrace, reason: 'VpnController initialize', fatal: false); } catch (_) {}
      rethrow;
    }
  }

  Future<void> handleConnectionButton(WidgetRef ref) async {
    final connectionState = ref.read(connectionStateProvider);
    _log.addLog('[VpnController] handleConnectionButton called, current status: ${connectionState.status}');
    switch (connectionState.status) {
      case ConnectionStatus.connected:
        await _disconnect(ref);
        return;
      case ConnectionStatus.loading:
      case ConnectionStatus.connecting:
      case ConnectionStatus.disconnecting:
        await _stopVpn(ref);
        return;
      case ConnectionStatus.disconnected:
      case ConnectionStatus.error:
      case ConnectionStatus.noInternet:
        await _connect(ref);
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

  /// Builds the full candidate list: last-good first, then fresh VPN Gate
  /// (official CSV, then mirror), then the UI-cached server list.
  Future<List<Candidate>> _buildCandidates(WidgetRef ref) async {
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

    // 2) Fresh VPN Gate fetch (official CSV → mirrors).
    if (_useTestConfig) {
      final fresh = await VpnGateCandidates.fetchAll(
        onLog: (m) => _log.addLog('[VpnController] $m'),
      );
      addAll(fresh);
    }

    // 3) Cached UI list as final fallback.
    try {
      final cachedServers = await ref.read(serversProvider.future);
      final fromCache = <Candidate>[];
      for (final s in cachedServers) {
        if (s.openVpnConfigBase64.isEmpty) continue;
        final c = _candidateFromB64(s.openVpnConfigBase64, fallbackIp: s.ip, csvPing: s.ping);
        if (c != null) fromCache.add(c);
      }
      fromCache.sort((a, b) {
        final pa = a.csvPing <= 0 ? 9999 : a.csvPing;
        final pb = b.csvPing <= 0 ? 9999 : b.csvPing;
        return pa.compareTo(pb);
      });
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

  int _endpointRank(Candidate c) {
    final ping = c.csvPing <= 0 ? 9999 : c.csvPing;
    final tcp = c.protocol == 'tcp' ? 0 : 100000;
    // TCP 443 first inside a subnet: DPI networks treat it best.
    final portBias = c.port == 443 ? 0 : 1000;
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

  Future<void> _connect(WidgetRef ref) async {
    final connectionNotifier = ref.read(connectionStateProvider.notifier);
    final loggerNotifier = ref.read(loggerStateProvider.notifier);
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

    if (Platform.isAndroid) {
      final sslGen = ++_rotationGeneration;
      connectionNotifier.holdEngineEvents(true);
      final selectedHost = _serverHost;
      final hosts = (selectedHost != null)
          ? <String>[selectedHost]
          : await SoftEtherVpn.hosts();
      if (selectedHost != null) {
        _log.addLog('[VpnController] SoftEther will use the selected relay $selectedHost');
      }
      var sslUp = false;
      if (sslGen == _rotationGeneration) {
        for (final host in hosts) {
          if (sslGen != _rotationGeneration) break;
          connectionNotifier.setConnecting();
          _log.addLog('[VpnController] SoftEther SSL $host:443');
          final result = await SoftEtherVpn.connect(host);
          if (sslGen != _rotationGeneration) break;
          if (result.ok) {
            _log.addLog('[VpnController] CONNECTED via SoftEther SSL $host (${result.detail})');
            ref.read(softEtherHostProvider.notifier).state = host;
            connectionNotifier.setConnected();
            sslUp = true;
            break;
          }
          _log.addLog('[VpnController] SoftEther failed $host: ${result.detail}');
        }
      }
      if (sslUp) return;
      connectionNotifier.holdEngineEvents(false);
      if (sslGen != _rotationGeneration) return;
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
    final built = await _buildCandidates(ref);
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
        _log.addLog('[VpnController] Attempt ${candidate.ip}:${candidate.port} (${candidate.protocol})...');
        try { FirebaseCrashlytics.instance.log('vpn attempt ${candidate.ip}:${candidate.port}'); } catch (_) {}

        final ok = await _attemptCandidate(candidate);
        if (gen != _rotationGeneration) return;

        if (ok) {
          _log.addLog('[VpnController] CONNECTED via ${candidate.ip}:${candidate.port}');
          await _saveLastGood(candidate);
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
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    return result;
  }

  /// Drops the current tunnel and opens the relay that is selected now.
  Future<void> reconnect(WidgetRef ref) async {
    _rotationGeneration++;
    _log.addLog('[VpnController] Switching relay to ${_serverHost ?? 'auto'}');
    ref.read(connectionStateProvider.notifier).holdEngineEvents(false);
    ref.read(softEtherHostProvider.notifier).state = null;
    await SoftEtherVpn.disconnect();
    await _connect(ref);
  }

  Future<void> _stopVpn(WidgetRef ref) async {
    final connectionNotifier = ref.read(connectionStateProvider.notifier);
    _log.addLog('[VpnController] Stopping VPN...');
    _rotationGeneration++; // cancels any rotation in flight
    connectionNotifier.holdEngineEvents(false);
    connectionNotifier.setDisconnecting();
    ref.read(softEtherHostProvider.notifier).state = null;
    await SoftEtherVpn.disconnect();
    await _vpnService.disconnect();
    _clearData(ref);
    connectionNotifier.setDisconnected();
  }

  Future<void> _disconnect(WidgetRef ref) async {
    final connectionNotifier = ref.read(connectionStateProvider.notifier);
    final vpnData = await _container?.read(vpnDataProvider.future);
    _log.addLog('[VpnController] Disconnecting VPN...');
    _rotationGeneration++;
    connectionNotifier.holdEngineEvents(false);
    connectionNotifier.setDisconnecting();
    ref.read(softEtherHostProvider.notifier).state = null;
    await SoftEtherVpn.disconnect();
    await _vpnService.disconnect();
    _clearData(ref);
    vpnData?.disableVPN();
    connectionNotifier.setDisconnected();
    _analyticsService.logVpnDisconnected();
  }

  void _clearData(WidgetRef ref) {
    final groupNotifier = ref.read(groupStateProvider.notifier);
    groupNotifier.setGroupName('');
    ref.read(flowLineStepProvider.notifier).setTotalSteps(0);
    ref.read(flowLineStepProvider.notifier).setStep(0);
  }

  void dispose() {
    _log.addLog('[VpnController] Disposing...');
    _rotationGeneration++;
    _vpnService.dispose();
    _initialized = false;
  }
}
