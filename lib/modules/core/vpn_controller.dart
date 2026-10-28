import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SecureSocket, Socket;
import 'dart:math' show Random;

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
import 'package:bulbvpn/modules/core/network_identity.dart';
import 'package:bulbvpn/modules/core/relay_memory.dart';
import 'package:bulbvpn/modules/core/home_region.dart';
import 'package:bulbvpn/modules/core/relay_reachability.dart';
import 'package:bulbvpn/modules/core/vpn_gate_candidates.dart';
import 'package:bulbvpn/modules/core/vpn_session_store.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
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
  String _serverCountryCode = '';
  String _serverCountryName = '';
  String get selectedServerLabel => _serverLabel;

  void selectServerConfig(
    String config,
    String label, {
    String? hostName,
    String? ip,
    String countryCode = '',
    String countryName = '',
  }) {
    _serverConfig = config;
    _serverLabel = label;
    _serverHost = (hostName != null && hostName.isNotEmpty) ? hostName : null;
    _serverIp = (ip != null && ip.isNotEmpty) ? ip : null;
    _serverCountryCode = countryCode.trim().toUpperCase();
    _serverCountryName = countryName.trim();
    _log.addLog(
      '[VpnController] Selected server: $label host=${_serverHost ?? '-'} ip=${_serverIp ?? '-'} country=$_serverCountryCode',
    );
  }

  void clearServerConfig() {
    _serverConfig = null;
    _serverLabel = '';
    _serverHost = null;
    _serverIp = null;
    _serverCountryCode = '';
    _serverCountryName = '';
    _log.addLog('[VpnController] Server selection cleared (auto)');
  }

  bool get _strictSelection =>
      _serverIp != null || _serverHost != null || _serverConfig != null;

  VpnService get vpnService => _vpnService;

  // ---------------------------------------------------------------------------
  // Rotation tuning
  // ---------------------------------------------------------------------------
  /// Time we allow one candidate to reach `connected` before moving on.
  static const _androidAttemptWatchdog = Duration(seconds: 18);
  static const _appleAttemptWatchdog = Duration(seconds: 50);

  /// SoftEther is dialled before OpenVPN on Apple. The native connect timeout
  /// is 20s; this is the outer backstop, not the normal failure path. A dead
  /// relay now returns after the native timeout instead of retrying the
  /// password handshake and waiting twice as long.
  static const _appleSoftEtherWatchdog = Duration(seconds: 35);

  /// Hard ceiling for one user-visible connect press. Without this, a picked
  /// country with dead relays could rotate through SoftEther and then eight
  /// OpenVPN candidates, leaving the orb on "Connecting" for minutes.
  static const _androidConnectBudget = Duration(seconds: 100);
  static const _appleConnectBudget = Duration(seconds: 55);

  /// OpenVPN on iOS does not report connected until the extension applies
  /// tunnel settings. 10s expired while that handshake was still running.
  Duration get _attemptWatchdog => Platform.isIOS || Platform.isMacOS
      ? _appleAttemptWatchdog
      : _androidAttemptWatchdog;

  Duration get _connectBudget => Platform.isIOS || Platform.isMacOS
      ? _appleConnectBudget
      : _androidConnectBudget;

  /// Per-candidate TCP reachability probe budget.
  static const _probeTimeout = Duration(milliseconds: 800);

  /// Relays swept in one TLS-probe wave once a shortlist proves censored.
  static const _sweepBatch = 20;

  /// SoftEther's TLS 443 preflight. A TCP connect is not evidence on
  /// carriers that complete the handshake and then drop the payload, so the
  /// probe performs a full TLS handshake with a mobile-tolerant ceiling.
  static const _softEtherProbeTimeout = Duration(seconds: 3);

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
  static const _provenFirstIp = '219.100.37.105';
  static const _lastGoodKey = 'bulbvpn_last_good_server_v1';
  static const _lastSslKey = 'bulbvpn_last_ssl_v1';

  /// Bumped by stop/disconnect to cancel an in-flight rotation loop.
  int _rotationGeneration = 0;

  /// Guards against two connect loops (manual + auto-recovery) overlapping.
  bool _connectInFlight = false;

  /// A manual relay switch arrived while a dial was still unwinding. Run it
  /// as soon as the in-flight attempt returns instead of silently dropping the
  /// user's pick.
  bool _connectQueued = false;

  /// User pressed disconnect / stop. Recovery must never fight that.
  bool _manualDisconnect = false;

  /// True once a press got past the network/permission gates and actually
  /// dialled. A permission denial is not retryable; a failed dial is.
  bool _attemptedDial = false;

  /// Bounded automatic recovery after an unexpected tunnel drop. The first
  /// three attempts are fast; the rest slow down to five-minute probes so a
  /// carrier outage that lasts minutes does not leave the user unprotected
  /// for the rest of the day.
  static const _maxAutoReconnects = 10;
  int _autoReconnects = 0;
  Timer? _recoveryTimer;
  Timer? _connectBudgetTimer;
  int _recoveryGeneration = 0;
  bool _dropListenerAttached = false;
  final Random _recoveryJitter = Random();

  /// Watches the physical network beneath the tunnel. A handover invalidates
  /// every relay socket, so it must reset the recovery budget and force a
  /// redial instead of waiting for the old session to time out.
  Timer? _networkWatchTimer;
  Timer? _networkReconnectTimer;
  String? _networkFingerprint;
  int _networkRedialAttempts = 0;

  /// Reachability measured moments ago on the current network. Turning a
  /// three-second tap into a cached decision is the main Lantern fast-connect
  /// lesson: probe before the user asks, not after.
  final RelayReachability _reachability = RelayReachability();
  Timer? _warmTimer;
  bool _warming = false;
  Future<List<RelayTarget>>? _sweepInFlight;

  DateTime? _connectDeadline;
  List<Candidate>? _freshCache;
  DateTime? _freshCandidatesAt;

  Future<void> initialize(ProviderContainer container) async {
    if (_initialized) return;
    _container = container;
    _attachDropListener(container);
    _vibrationService.init();
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    _log.addLog(
      '[VpnController] Device region: locale=${HomeRegion.locale} '
      'tz=${HomeRegion.timezone} home=${HomeRegion.countryCode ?? 'unknown'}',
    );
    _log.addLog(
      '[VpnController] Timezone offset: ${offset.inMinutes / 60.0} hours',
    );
    try {
      await _vpnService.initialize();
      _initialized = true;
      await _primeNetworkWatcher();
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

  /// Watches real state transitions. The notifier is the single source of
  /// truth; a `connected → disconnected` edge means the tunnel died without
  /// the user asking for it, so it is safe to recover.
  void _attachDropListener(ProviderContainer container) {
    if (_dropListenerAttached) return;
    _dropListenerAttached = true;
    container.listen<ConnectionState>(connectionStateProvider, (
      previous,
      next,
    ) {
      if (next.status == ConnectionStatus.connected) {
        _autoReconnects = 0;
        _recoveryGeneration++;
        _recoveryTimer?.cancel();
        _recoveryTimer = null;
        return;
      }
      if (previous?.status == ConnectionStatus.connected &&
          next.status == ConnectionStatus.disconnected &&
          !_manualDisconnect) {
        _log.addLog(
          '[VpnController] Tunnel dropped unexpectedly; scheduling recovery',
        );
        _scheduleRecovery();
      }
    }, fireImmediately: false);
  }

  /// Reads native tunnel state without letting a transient platform-channel
  /// failure escape the recovery timer.
  Future<SoftEtherStatus> _softEtherStatusSafe() async {
    try {
      return await SoftEtherVpn.status();
    } catch (_) {
      return SoftEtherStatus.down;
    }
  }

  /// Bounded recovery. The first three attempts are quick (2s, 8s, 20s); the
  /// rest stretch out to five minutes with ±20% jitter. A multi-minute carrier
  /// outage must not end recovery for the day, and jitter keeps a fleet of
  /// phones from redialling the same relay in lockstep.
  void _scheduleRecovery() {
    if (_manualDisconnect || _connectInFlight) return;
    if (_autoReconnects >= _maxAutoReconnects) {
      _log.addLog('[VpnController] Recovery budget exhausted; staying down');
      return;
    }
    if (_recoveryTimer != null) return;
    final attempt = ++_autoReconnects;
    final base = switch (attempt) {
      1 => 2,
      2 => 8,
      3 => 20,
      4 => 45,
      5 => 90,
      6 => 180,
      _ => 300,
    };
    final seconds = (base * (0.8 + _recoveryJitter.nextDouble() * 0.4))
        .round()
        .clamp(1, 420);
    final generation = ++_recoveryGeneration;
    _recoveryTimer = Timer(Duration(seconds: seconds), () async {
      _recoveryTimer = null;
      if (generation != _recoveryGeneration || _manualDisconnect) return;
      final container = _container;
      if (container == null) return;
      final status = container.read(connectionStateProvider).status;
      if (status == ConnectionStatus.connected ||
          status == ConnectionStatus.connecting ||
          _connectInFlight) {
        return;
      }
      final tunnel = await _softEtherStatusSafe();
      if (tunnel.reason == 'revoked') {
        _log.addLog(
          '[VpnController] VPN was revoked by the system; not retrying',
        );
        return;
      }
      var online = true;
      try {
        online = await NetworkStatus.checkConnectivity();
      } catch (_) {
        // If the probe itself fails, attempt the reconnect rather than
        // silently burning the recovery budget.
      }
      if (!online) {
        _log.addLog('[VpnController] Recovery postponed: no network');
        // Being offline is not a failed reconnect attempt. Refund the slot and
        // check again shortly; otherwise a tunnel that drops in a lift loses
        // its entire recovery budget before the phone regains signal.
        _autoReconnects = (attempt - 1).clamp(0, _maxAutoReconnects);
        _recoveryTimer = Timer(const Duration(seconds: 5), () {
          _recoveryTimer = null;
          if (generation != _recoveryGeneration || _manualDisconnect) return;
          _scheduleRecovery();
        });
        return;
      }
      _log.addLog(
        '[VpnController] Auto-reconnect $attempt/$_maxAutoReconnects',
      );
      await _connect(auto: true);
    });
  }

  Future<void> _primeNetworkWatcher() async {
    _networkFingerprint = await NetworkIdentity.current(fresh: true);
    _adoptNetwork(_networkFingerprint!);
    _networkWatchTimer?.cancel();
    _networkWatchTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_pollNetworkIdentity()),
    );
  }

  /// Reachability is a property of the physical network. Every handover throws
  /// the table away, and a freshly discovered network is warmed before the
  /// user presses the orb.
  void _adoptNetwork(String network) {
    if (network == 'offline' || network == 'unknown') return;
    final changed = _reachability.network != network;
    _reachability.useNetwork(network);
    if (!changed) return;
    _scheduleWarmProbes(delay: const Duration(seconds: 1));
  }

  static const _warmProbeLimit = 10;

  /// Tops the reachability cache up while the user is still deciding. The home
  /// screen also calls this on resume, since a phone that slept for hours has
  /// a cache from before the carrier changed.
  void warmProbes({Duration delay = Duration.zero}) {
    _scheduleWarmProbes(delay: delay);
  }

  void _scheduleWarmProbes({Duration delay = Duration.zero}) {
    if (_manualDisconnect || _warmTimer != null) return;
    final network = _networkFingerprint;
    if (network == null || network == 'offline' || network == 'unknown') return;
    _warmTimer = Timer(delay, () {
      _warmTimer = null;
      unawaited(_warmRelayProbes());
    });
  }

  Future<void> _warmRelayProbes() async {
    final container = _container;
    final network = _networkFingerprint;
    if (container == null || _warming || _manualDisconnect) return;
    if (network == null || network == 'offline' || network == 'unknown') return;
    // A real dial always wins: probing in parallel competes for the same
    // carrier sockets and could delay the handshake that matters.
    final status = container.read(connectionStateProvider).status;
    if (_connectInFlight ||
        status == ConnectionStatus.connected ||
        status == ConnectionStatus.connecting ||
        status == ConnectionStatus.loading) {
      return;
    }
    _warming = true;
    try {
      final targets = await _softEtherTargets(container);
      if (network != _networkFingerprint) return;
      final cold = <RelayTarget>[];
      for (final target in targets) {
        if (cold.length >= _warmProbeLimit) break;
        if (_reachability.lookup(target.dial) != null) continue;
        cold.add(target);
      }
      if (cold.isEmpty) return;
      final probes = await _probeSoftEther(cold, network: network);
      final alive = probes.where((probe) => probe.$1).length;
      _log.addLog(
        '[VpnController] Warm probe on ${network.split('|').first}: '
        '$alive/${cold.length} relays reachable',
      );
      // A censored carrier usually leaves the shortlist with nothing alive.
      // Sweeping here, while the user has not pressed connect, turns the first
      // tap into a cached dial instead of a 20 s scan.
      if (alive < 2) {
        if (network != _networkFingerprint) return;
        final rtt = <String, int>{};
        for (var i = 0; i < cold.length; i++) {
          if (probes[i].$1) rtt[cold[i].dial] = probes[i].$2;
        }
        await _sweepSoftEther(
          container,
          {for (final target in targets) target.dial},
          _rotationGeneration,
          rtt,
        );
      }
    } finally {
      _warming = false;
    }
  }

  Future<String> _networkForMemory() async {
    final cached = _networkFingerprint;
    if (cached != null && cached != 'offline' && cached != 'unknown') {
      return cached;
    }
    final fresh = await NetworkIdentity.current(fresh: true);
    _networkFingerprint = fresh;
    return fresh;
  }

  static String? _wifiPart(String fingerprint) {
    for (final part in fingerprint.split('|')) {
      if (part.startsWith('wifi:')) return part;
    }
    return null;
  }

  /// A physical handover invalidates the relay socket even when the native
  /// session still claims to be connected. Reset the recovery budget for the
  /// new network and redial instead of waiting for a 30s read timeout.
  Future<void> _pollNetworkIdentity() async {
    final container = _container;
    if (container == null) return;
    final next = await NetworkIdentity.current(fresh: true);
    final previous = _networkFingerprint;
    if (next == 'unknown') return;
    if (previous == null || previous == next) {
      _networkFingerprint = next;
      _adoptNetwork(next);
      return;
    }
    _networkFingerprint = next;
    _adoptNetwork(next);
    // Losing every interface is a gap, not a handover. Keep it as the last
    // known value and act when a real network appears again.
    if (next == 'offline') return;
    // Mobile data appearing or disappearing while the same Wi-Fi carries the
    // traffic is not a handover; redialling would drop a healthy tunnel.
    final oldWifi = _wifiPart(previous);
    final newWifi = _wifiPart(next);
    if (oldWifi != null && newWifi != null && oldWifi == newWifi) {
      return;
    }
    // The user stopped the tunnel. A handover must not resurrect it.
    if (_manualDisconnect) return;
    final status = container.read(connectionStateProvider).status;
    _log.addLog(
      '[VpnController] Network changed: $previous -> $next '
      '(status=${status.name})',
    );
    final recovering = _autoReconnects > 0;
    _autoReconnects = 0;
    _recoveryGeneration++;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _networkReconnectTimer?.cancel();
    _networkRedialAttempts = 0;

    if (status == ConnectionStatus.connected) {
      _scheduleNetworkRedial();
      return;
    }
    if (status == ConnectionStatus.connecting ||
        status == ConnectionStatus.loading) {
      if (_connectInFlight) {
        _log.addLog('[VpnController] Aborting dial bound to the old network');
        _rotationGeneration++;
        _connectQueued = true;
        unawaited(SoftEtherVpn.disconnect());
        unawaited(_vpnService.disconnect());
      }
      return;
    }
    // The handover can arrive while a recovery timer is already pending (or
    // just after the tunnel dropped). That timer was cancelled above, so a
    // disconnected tunnel must be rescheduled on the new network.
    if (recovering && !_manualDisconnect && !_connectInFlight) {
      _scheduleRecovery();
    }
  }

  void _scheduleNetworkRedial({Duration delay = const Duration(seconds: 2)}) {
    if (_manualDisconnect) return;
    _networkReconnectTimer?.cancel();
    _networkReconnectTimer = Timer(delay, () async {
      _networkReconnectTimer = null;
      if (_manualDisconnect) return;
      final container = _container;
      if (container == null) return;
      if (container.read(connectionStateProvider).status !=
              ConnectionStatus.connected ||
          _connectInFlight) {
        return;
      }
      final online = await NetworkStatus.checkConnectivity();
      if (!online) {
        _log.addLog('[VpnController] New network has no internet yet; waiting');
        if (!_manualDisconnect &&
            container.read(connectionStateProvider).status ==
                ConnectionStatus.connected) {
          _scheduleNetworkRedial(delay: const Duration(seconds: 5));
        }
        return;
      }
      if (_networkRedialAttempts >= 3) {
        _log.addLog('[VpnController] Network redial budget exhausted');
        return;
      }
      final attempt = ++_networkRedialAttempts;
      _log.addLog(
        '[VpnController] Forcing a clean redial after network change '
        '(attempt $attempt)',
      );
      _rotationGeneration++;
      try {
        await SoftEtherVpn.disconnect();
      } catch (_) {}
      try {
        await _vpnService.disconnect();
      } catch (_) {}
      if (_manualDisconnect) return;
      container.read(connectionStateProvider.notifier).holdEngineEvents(false);
      container.read(connectedRelayProvider.notifier).state = null;
      container.read(softEtherHostProvider.notifier).state = null;
      container.read(connectionStateProvider.notifier).setDisconnected();
      _scheduleRecovery();
    });
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
  Candidate? _candidateFromB64(
    String b64, {
    String? fallbackIp,
    int? csvPing,
    String sni = '',
    String countryCode = '',
    String countryName = '',
  }) {
    final decoded = decodeOvpn(b64);
    if (decoded == null || !decoded.contains('<ca>')) return null;
    final withAuth = configForCurrentEngine(decoded);
    return Candidate.fromConfig(
      withAuth,
      fallbackIp: fallbackIp,
      csvPing: csvPing,
      sni: sni,
      countryCode: countryCode,
      countryName: countryName,
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

  Future<RelayTarget?> _readLastSsl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastSslKey);
      if (raw != null && raw.isNotEmpty) {
        if (raw.startsWith('{')) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final dial = map['dial']?.toString() ?? '';
          final sni = map['sni']?.toString() ?? '';
          if (dial.isNotEmpty && sni.isNotEmpty) {
            return RelayTarget(
              dial: dial,
              sni: sni,
              countryCode: map['code']?.toString().toUpperCase() ?? '',
              countryName: map['name']?.toString() ?? '',
              source: 'last-good',
            );
          }
        } else if (raw.contains('|')) {
          // v1 format: dial|sni
          final parts = raw.split('|');
          if (parts[0].isNotEmpty && parts[1].isNotEmpty) {
            return RelayTarget(
              dial: parts[0],
              sni: parts[1],
              source: 'last-good',
            );
          }
        }
      }
    } catch (_) {}
    final session = await VpnSessionStore.read();
    final host = session?.host ?? '';
    if (host.isEmpty) return null;
    return RelayTarget(
      dial: host,
      // The label is "<COUNTRY> · <ip>"; it is not a hostname. Using it as SNI
      // sent a literal country name in the TLS handshake. Fall back to the IP
      // and let the catalog repair the real name when it is available.
      sni: host,
      countryCode: session?.countryCode.toUpperCase() ?? '',
      countryName: session?.countryName ?? '',
      source: 'last-good',
    );
  }

  Future<void> _saveLastSsl(RelayTarget target) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastSslKey,
        jsonEncode({
          'dial': target.dial,
          'sni': target.sni,
          'code': target.countryCode.toUpperCase(),
          'name': target.countryName,
        }),
      );
    } catch (_) {}
  }

  /// Relays that completed a real SoftEther session on Iranian carriers.
  /// Only a fallback: measured relays always come first.
  static const List<RelayTarget> _provenRelays = [
    RelayTarget(
      dial: '219.100.37.105',
      sni: 'public-vpn-139.opengw.net',
      countryCode: 'JP',
      countryName: 'Japan',
      source: 'proven',
    ),
    RelayTarget(
      dial: '219.100.37.179',
      sni: 'public-vpn-187.opengw.net',
      countryCode: 'JP',
      countryName: 'Japan',
      source: 'proven',
    ),
  ];

  VpnServer? _findByHost(List<VpnServer> servers, String? host) {
    final wanted = (host ?? '').trim();
    if (wanted.isEmpty) return null;
    for (final server in servers) {
      if (server.hostName == wanted ||
          SoftEtherVpn.fqdn(server.hostName) == wanted ||
          server.ip == wanted) {
        return server;
      }
    }
    return null;
  }

  String? _remoteHostFromSelectedConfig() {
    final config = _serverConfig;
    if (config == null) return null;
    for (final line in const LineSplitter().convert(config)) {
      final match = RegExp(r'^\s*remote\s+(\S+)').firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }

  RelayTarget? _targetFromServer(
    VpnServer server, {
    required String source,
    int? pingMs,
  }) {
    if (server.ip.isEmpty) return null;
    final sni = SoftEtherVpn.fqdn(server.hostName);
    return RelayTarget(
      dial: server.ip,
      sni: sni.isEmpty ? server.ip : sni,
      countryCode: server.countryShort.toUpperCase(),
      countryName: server.displayCountry,
      pingMs: pingMs ?? server.ping,
      source: source,
    );
  }

  /// Targets are ordered by what this device actually needs:
  ///
  /// * a picked server is tried first, then other relays in that country;
  /// * if every same-country SoftEther host is unreachable, proven / measured
  ///   SoftEther from other countries are appended as an escape hatch so the
  ///   orb does not hang on Connecting;
  /// * auto mode uses last-good, then the relays this phone measured fastest;
  /// * the hard-coded VPN Gate relays proven on Iranian carriers are only a
  ///   last resort in auto mode, never ahead of the measured list.
  Future<List<RelayTarget>> _softEtherTargets(
    ProviderContainer container,
  ) async {
    try {
      final servers = await container.read(serversProvider.future);
      final measured = container.read(serverPingProvider).byIp;
      final byIp = <String, VpnServer>{for (final s in servers) s.ip: s};
      final ordered = sortByMeasuredPing(servers, measured);
      final picked = <RelayTarget>[];
      final seen = <String>{};
      final perSubnet = <String, int>{};

      bool add(
        RelayTarget? target, {
        bool dedupeSubnet = true,
        int maxPerSubnet = 2,
      }) {
        if (target == null || target.dial.isEmpty) return false;
        if (!seen.add(target.dial)) return false;
        if (dedupeSubnet) {
          final subnet = _subnet(target.dial);
          final count = perSubnet[subnet] ?? 0;
          if (count >= maxPerSubnet) return false;
          perSubnet[subnet] = count + 1;
        }
        picked.add(target);
        return true;
      }

      if (_strictSelection) {
        final selected = byIp[_serverIp] ?? _findByHost(servers, _serverHost);
        final dial =
            _serverIp ?? selected?.ip ?? _remoteHostFromSelectedConfig();
        final sni = SoftEtherVpn.fqdn(
          selected?.hostName ?? _serverHost ?? dial ?? '',
        );
        final code = (selected?.countryShort ?? _serverCountryCode)
            .toUpperCase();
        final name = selected?.displayCountry ?? _serverCountryName;
        if (dial != null && dial.isNotEmpty) {
          add(
            RelayTarget(
              dial: dial,
              sni: sni.isEmpty ? dial : sni,
              countryCode: code,
              countryName: name,
              pingMs: selected?.ping ?? 0,
              source: 'selected',
            ),
            dedupeSubnet: false,
          );
        }
        if (code.length == 2) {
          for (final server in ordered) {
            if (server.countryShort.toUpperCase() != code) continue;
            final ping = measured[server.ip];
            add(
              _targetFromServer(
                server,
                source: 'same-country',
                pingMs: ping != null && ping.status == PingStatus.ok
                    ? ping.ms
                    : server.ping,
              ),
            );
            if (picked.length >= 5) break;
          }
        }
        // Country SoftEther can be entirely unreachable (Mac log 20 Oct:
        // SoftEther probe 0/5 for RU, then OpenVPN burned the 55s budget on
        // the same dead hosts). Keep proven / measured SoftEther after the
        // country list so the TCP probe can still land a live tunnel. The
        // home screen shows the relay that actually connected.
        final beforeEscape = picked.length;
        for (final target in _provenRelays) {
          add(target, dedupeSubnet: false);
        }
        final measuredOk = ordered
            .where((s) => measured[s.ip]?.status == PingStatus.ok)
            .toList();
        for (final server in measuredOk) {
          if (code.length == 2 && server.countryShort.toUpperCase() == code) {
            continue;
          }
          final ping = measured[server.ip];
          add(
            _targetFromServer(
              server,
              source: 'escape',
              pingMs: ping != null && ping.status == PingStatus.ok
                  ? ping.ms
                  : server.ping,
            ),
          );
          if (picked.length >= 8) break;
        }
        _log.addLog(
          '[VpnController] SoftEther plan (picked $code): '
          '${picked.map((t) => '${t.countryCode}:${t.dial}/${t.source}').join(', ')}'
          '${picked.length > beforeEscape ? ' (includes escape)' : ''}',
        );
        return picked;
      }

      final network = await _networkForMemory();
      final networkRelay = await RelayMemory.recall(network: network);
      if (networkRelay != null) {
        final live = byIp[networkRelay.dial];
        final liveSni = live == null ? '' : SoftEtherVpn.fqdn(live.hostName);
        final added = add(
          networkRelay.copyWith(
            sni: liveSni.isEmpty ? networkRelay.sni : liveSni,
            countryCode: (live?.countryShort ?? networkRelay.countryCode)
                .toUpperCase(),
            countryName: live?.displayCountry ?? networkRelay.countryName,
          ),
          dedupeSubnet: false,
        );
        if (added) {
          _log.addLog(
            '[VpnController] Network-memory relay ${networkRelay.dial}',
          );
        }
      }

      final remembered = await _readLastSsl();
      if (remembered != null) {
        final live = byIp[remembered.dial];
        // A legacy record can contain an IP with no country metadata. It is
        // unverifiable: it may be a stale relay from another build, or an IP
        // that DNS pollution poisoned. Let the measured/proven list lead
        // instead of burning the first 30 s of every connection on it.
        final verifiable =
            live != null || remembered.countryCode.trim().isNotEmpty;
        if (!verifiable) {
          _log.addLog(
            '[VpnController] Ignoring unverified last-good relay '
            '${remembered.dial}; no catalog match and no country metadata',
          );
        } else {
          final liveSni = live == null ? '' : SoftEtherVpn.fqdn(live.hostName);
          add(
            remembered.copyWith(
              sni: liveSni.isEmpty ? remembered.sni : liveSni,
              countryCode: (live?.countryShort ?? remembered.countryCode)
                  .toUpperCase(),
              countryName: live?.displayCountry ?? remembered.countryName,
            ),
            dedupeSubnet: false,
          );
        }
      }

      final measuredOk = ordered
          .where((s) => measured[s.ip]?.status == PingStatus.ok)
          .toList();
      // On Irancell/Hamrah Aval, ICMP is often filtered, so there are no
      // measured winners. In that case the relays proven on those carriers go
      // right after last-good, before the unmeasured catalog order.
      if (measuredOk.isEmpty) {
        for (final target in _provenRelays) {
          add(target, dedupeSubnet: false);
        }
      }
      final pool = measuredOk.isNotEmpty ? measuredOk : ordered;
      for (final server in pool) {
        final ping = measured[server.ip];
        add(
          _targetFromServer(
            server,
            source: 'fastest',
            pingMs: ping != null && ping.status == PingStatus.ok
                ? ping.ms
                : server.ping,
          ),
        );
        if (picked.length >= 8) break;
      }

      // Last resort for filtered carriers. Never placed ahead of a measured
      // relay, so global users keep their lowest-latency choice.
      if (picked.isEmpty) {
        for (final target in _provenRelays) {
          add(target, dedupeSubnet: false);
        }
      }
      if (picked.isNotEmpty) {
        // Network memory and the global last-good stay at the head: they are
        // this network's strongest evidence. Everything else is ordered by
        // probe/dial history so a relay that just failed sinks instead of
        // being redialled first on every reconnect.
        final anchored = <RelayTarget>[];
        final scored = <RelayTarget>[];
        for (final target in picked) {
          if (target.source == 'network-memory' ||
              target.source == 'last-good') {
            anchored.add(target);
          } else {
            scored.add(target);
          }
        }
        final byHistory = await RelayMemory.orderByHistory(
          scored,
          network: network,
        );
        final plan = _foreignFirst([...anchored, ...byHistory]);
        _log.addLog(
          '[VpnController] SoftEther plan (auto): '
          '${plan.map((t) => '${t.countryCode}:${t.dial}').join(', ')}',
        );
        return plan;
      }
    } catch (e) {
      _log.addLog('[VpnController] SoftEther target list failed: $e');
    }
    final hosts = await SoftEtherVpn.hosts();
    return [
      for (final host in hosts)
        RelayTarget(dial: host, sni: host, source: 'fallback'),
    ];
  }

  /// Region-locked services read the exit IP's country, so a plan that starts
  /// with a relay inside the device's own country gives them the same answer
  /// as no VPN. Foreign exits go first, but local ones stay in the list: when
  /// a carrier blocks every foreign relay, the local exit is still a tunnel.
  List<RelayTarget> _foreignFirst(List<RelayTarget> targets) {
    if (HomeRegion.countryCode == null) return targets;
    final away = <RelayTarget>[];
    final home = <RelayTarget>[];
    for (final target in targets) {
      (HomeRegion.isHome(target.countryCode) ? home : away).add(target);
    }
    if (home.isEmpty || away.isEmpty) return targets;
    _log.addLog(
      '[VpnController] ${home.length} same-country exits moved behind '
      '${away.length} foreign exits',
    );
    return [...away, ...home];
  }

  /// Fetches the official/mirror VPN Gate list on demand. The published
  /// catalog can be hours stale and GitHub is blocked on some IR networks, so
  /// an all-dead probe result must be able to ask for a newer list.
  Future<List<Candidate>> _freshCandidates() async {
    final cached = _freshCache;
    final at = _freshCandidatesAt;
    if (cached != null && at != null) {
      final age = DateTime.now().difference(at);
      final ttl = cached.isEmpty
          ? const Duration(seconds: 30)
          : const Duration(seconds: 90);
      if (age < ttl) return cached;
    }
    final remaining = _budgetRemaining;
    if (remaining < const Duration(seconds: 12)) {
      final cached = await VpnGateCatalogCache.load();
      _freshCache = cached;
      _freshCandidatesAt = DateTime.now();
      _log.addLog(
        '[VpnController] Skipping catalog refresh; '
        '${remaining.inSeconds}s of connect budget left'
        '${cached.isEmpty ? '' : '; using ${cached.length} cached endpoints'}',
      );
      return cached;
    }
    _log.addLog('[VpnController] Refreshing VPN Gate catalog on-device');
    List<Candidate> fetched;
    try {
      fetched = await VpnGateCandidates.fetchAll(onLog: _log.addLog).timeout(
        const Duration(seconds: 12),
        onTimeout: () => const <Candidate>[],
      );
    } catch (_) {
      fetched = const [];
    }
    _freshCache = fetched;
    _freshCandidatesAt = DateTime.now();
    _log.addLog('[VpnController] Fresh catalog: ${fetched.length} endpoints');
    return fetched;
  }

  Duration get _budgetRemaining {
    final deadline = _connectDeadline;
    if (deadline == null) return _connectBudget;
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
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

    // 1) Last known-good server: fastest path on stable networks. In strict
    //    selection mode the picked server is already first; a remembered
    //    server from another country must never leak into the rotation.
    final lastGoodRaw = _strictSelection ? null : await _readLastGood();
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
        if (_strictSelection) {
          final sameCountry =
              _serverCountryCode.isNotEmpty &&
              s.countryShort.toUpperCase() == _serverCountryCode;
          final sameServer = _serverIp != null && s.ip == _serverIp;
          if (!sameCountry && !sameServer) continue;
        }
        if (s.openVpnConfigBase64.isEmpty) continue;
        final live = measured[s.ip];
        final ping = live != null && live.status == PingStatus.ok
            ? live.ms
            : s.ping;
        final c = _candidateFromB64(
          s.openVpnConfigBase64,
          fallbackIp: s.ip,
          csvPing: ping,
          sni: SoftEtherVpn.fqdn(s.hostName),
          countryCode: s.countryShort.toUpperCase(),
          countryName: s.displayCountry,
        );
        if (c != null) fromCache.add(c);
      }
      addAll(fromCache);
    } catch (e) {
      _log.addLog('[VpnController] Cached server list unavailable: $e');
    }

    if (candidates.isEmpty) {
      addAll(await _freshCandidates());
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
    // An exit in the device's own country keeps the region-locked answer the
    // user is trying to leave, so it ranks behind an equally reachable
    // foreign exit. It is never removed: a local relay can still be the only
    // tunnel a carrier allows.
    final homeBias = HomeRegion.isHome(c.countryCode) ? 200000 : 0;
    final portBias = c.port == 443 ? 0 : 800;
    return tcp + provenBias + homeBias + portBias + ping;
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
    if (!_strictSelection &&
        donor != null &&
        !byIp.containsKey(_provenFirstIp)) {
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
      sni: donor.sni,
      countryCode: donor.countryCode,
      countryName: donor.countryName,
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

    var orderedReachable = provenFirst(results);
    var orderedDead = provenFirst(dead);
    _log.addLog(
      '[VpnController] Probe results: ${orderedReachable.length} reachable, ${orderedDead.length} dead',
    );
    for (final c in orderedReachable.take(5)) {
      _log.addLog(
        '[VpnController]   reachable: ${c.ip}:${c.port} (ping ${c.csvPing})',
      );
    }

    if (orderedReachable.isEmpty) {
      final fresh = await _freshCandidates();
      final freshSorted = [...fresh]
        ..sort((a, b) => _endpointRank(a).compareTo(_endpointRank(b)));
      final seen = input.map((c) => '${c.ip}:${c.port}').toSet();
      final extra = <Candidate>[];
      for (final candidate in freshSorted) {
        if (extra.length >= _maxProbe) break;
        final on443 = candidate.protocol == 'tcp' && candidate.port == 443
            ? candidate
            : Candidate.withPort(candidate, 443);
        if (on443 == null) continue;
        if (!seen.add('${on443.ip}:${on443.port}')) continue;
        if (_strictSelection && _serverCountryCode.isNotEmpty) {
          final sameServer = _serverIp != null && on443.ip == _serverIp;
          final sameCountry =
              on443.countryCode.toUpperCase() == _serverCountryCode;
          if (!sameServer && !sameCountry) continue;
        }
        extra.add(on443);
      }
      if (extra.isNotEmpty) {
        _log.addLog('[VpnController] Probing ${extra.length} fresh endpoints');
        final freshReachable = <Candidate>[];
        final freshDead = <Candidate>[];
        for (var i = 0; i < extra.length; i += 10) {
          final batch = extra.sublist(i, (i + 10).clamp(0, extra.length));
          final probes = await Future.wait([
            for (final c in batch) _probe(c.ip, c.port),
          ]);
          for (var j = 0; j < batch.length; j++) {
            (probes[j] ? freshReachable : freshDead).add(batch[j]);
          }
        }
        _log.addLog(
          '[VpnController] Fresh probe: ${freshReachable.length} reachable, '
          '${freshDead.length} dead',
        );
        orderedReachable = provenFirst(freshReachable);
        // The fresh list is newer than the bundled catalog, but a blocked TCP
        // probe still does not prove the dial is dead. Keep both as fallback.
        orderedDead = [...provenFirst(freshDead), ...orderedDead];
      }
    }

    if (orderedReachable.isEmpty) {
      // A picked country whose every SoftEther and OpenVPN listener is dead
      // used to keep dialling "unprobed" hosts until the connect budget
      // expired (RU on Mac: Connecting for ~55s). Fail the OpenVPN path
      // immediately; SoftEther escape already ran above.
      if (_strictSelection) {
        _log.addLog(
          '[VpnController] No reachable OpenVPN listener for '
          '$_serverLabel; skipping dead-host rotation',
        );
        return const <Candidate>[];
      }
      for (final c in orderedDead.take(5)) {
        _log.addLog(
          '[VpnController]   will try (unprobed): ${c.ip}:${c.port} '
          '(ping ${c.csvPing})',
        );
      }
    }
    return [...orderedReachable, ...orderedDead];
  }

  // ---------------------------------------------------------------------------
  // Connect flow
  // ---------------------------------------------------------------------------

  /// Single entry point. A manual press resets recovery; an automatic retry
  /// keeps the bounded budget and reschedules if this attempt also fails.
  Future<void> _connect({bool auto = false}) async {
    final container = _container;
    if (container == null) return;
    if (_connectInFlight) {
      if (!auto) {
        _connectQueued = true;
        _manualDisconnect = false;
        _log.addLog(
          '[VpnController] Relay change queued behind the active dial',
        );
      } else {
        _log.addLog('[VpnController] Connect already in flight; ignoring');
      }
      return;
    }
    _connectQueued = false;
    _connectInFlight = true;
    if (!auto) {
      _manualDisconnect = false;
      _autoReconnects = 0;
      _recoveryGeneration++;
      _recoveryTimer?.cancel();
      _recoveryTimer = null;
      // A manual press asks for the freshest list; a retry within one press
      // reuses the fetch so rotation does not spend the budget twice.
      _freshCache = null;
      _freshCandidatesAt = null;
    }
    // Never let the previous session's country survive a new dial.
    container.read(connectedRelayProvider.notifier).state = null;
    try {
      await _connectImpl();
    } catch (error, stack) {
      _log.addLog('[VpnController] Connect crashed: $error');
      try {
        container.read(connectionStateProvider.notifier).setError();
      } catch (_) {}
      try {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          reason: 'VpnController connect',
          fatal: false,
        );
      } catch (_) {}
    } finally {
      _cancelConnectBudget();
      _connectInFlight = false;
    }
    if (_connectQueued) {
      _connectQueued = false;
      if (_manualDisconnect) {
        _log.addLog('[VpnController] Queued relay change dropped (stopped)');
        return;
      }
      _log.addLog('[VpnController] Running queued relay change');
      await _connect();
      return;
    }
    final status = container.read(connectionStateProvider).status;
    if (status == ConnectionStatus.connected) {
      _autoReconnects = 0;
      _recoveryGeneration++;
      _recoveryTimer?.cancel();
      _recoveryTimer = null;
      return;
    }
    // A failed manual press must keep trying too: the user asked for a tunnel.
    // A permission denial or a missing network returns before any dial and is
    // deliberately excluded, since retrying it would loop a system prompt.
    if (!_manualDisconnect && (_attemptedDial || auto)) {
      _scheduleRecovery();
    }
  }

  /// Starts the hard ceiling for this connect press. The candidate loops and
  /// native dials still have their own shorter watchdogs; this only exists so
  /// a chain of dead relays can never leave the UI on "Connecting".
  void _startConnectBudget() {
    _connectBudgetTimer?.cancel();
    _connectDeadline = DateTime.now().add(_connectBudget);
    _connectBudgetTimer = Timer(_connectBudget, () {
      unawaited(_abortConnectBudget());
    });
  }

  void _cancelConnectBudget() {
    _connectBudgetTimer?.cancel();
    _connectBudgetTimer = null;
    _connectDeadline = null;
  }

  Future<void> _abortConnectBudget() async {
    final container = _container;
    _log.addLog(
      '[VpnController] Connect budget exhausted after '
      '${_connectBudget.inSeconds}s; aborting this attempt',
    );
    // Invalidate every in-flight loop before tearing the engine down so a
    // late native success cannot resurrect a session the user never got.
    _rotationGeneration++;
    _manualDisconnect = true;
    try {
      await _vpnService.disconnect();
    } catch (_) {}
    try {
      await SoftEtherVpn.disconnect();
    } catch (_) {}
    if (container == null) return;
    container.read(connectedRelayProvider.notifier).state = null;
    container.read(softEtherHostProvider.notifier).state = null;
    container.read(connectionStateProvider.notifier).setError();
  }

  Future<void> _connectImpl() async {
    final container = _container;
    if (container == null) return;
    final connectionNotifier = container.read(connectionStateProvider.notifier);
    final loggerNotifier = container.read(loggerStateProvider.notifier);
    _attemptedDial = false;
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
    _attemptedDial = true;
    _startConnectBudget();
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

    // The user may have pressed disconnect (or picked another relay, which is
    // queued) while a SoftEther handshake was unwinding. Never fall through to
    // the OpenVPN path after that: it would open a tunnel the user closed.
    if (_manualDisconnect) {
      _log.addLog('[VpnController] Connect cancelled by user');
      return;
    }
    if (_connectQueued) {
      _log.addLog('[VpnController] Connect superseded by a queued relay');
      return;
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
    final pinned = _strictSelection
        ? const <Candidate>[]
        : ranked.where((c) => c.ip == _provenFirstIp).toList();
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
      if (_manualDisconnect) {
        _log.addLog('[VpnController] Connect cancelled by user');
        try {
          await _vpnService.disconnect();
        } catch (_) {}
        return;
      }
      if (_connectQueued) {
        _log.addLog('[VpnController] Connect superseded by a queued relay');
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
      if (_manualDisconnect) {
        _log.addLog('[VpnController] Connect cancelled by user');
        try {
          await _vpnService.disconnect();
        } catch (_) {}
        return;
      }
      if (_connectQueued) {
        _log.addLog('[VpnController] Connect superseded by a queued relay');
        return;
      }

      if (ok) {
        _log.addLog(
          '[VpnController] CONNECTED via ${candidate.ip}:${candidate.port}',
        );
        final relay = await _relayForCandidate(candidate, container);
        container.read(connectedRelayProvider.notifier).state = relay;
        container.read(softEtherHostProvider.notifier).state =
            '${relay.displayName} · ${relay.dial}';
        connectionNotifier.holdEngineEvents(false);
        connectionNotifier.setConnected();
        await _saveLastGood(candidate);
        await RelayMemory.remember(relay, network: await _networkForMemory());
        if (HomeRegion.isHome(relay.countryCode)) {
          _log.addLog(
            '[VpnController] Exit ${relay.dial} is in the device home country '
            '(${HomeRegion.countryCode}); region-locked services will still '
            'see it',
          );
        }
        await VpnSessionStore.save(
          label: relay.label,
          host: candidate.ip,
          countryCode: relay.countryCode,
          countryName: relay.countryName,
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

  /// Returns the relay that the native session reports. VPN Gate can terminate
  /// the dialled IP on a different relay inside the same operation; showing the
  /// dialled address as the exit would be a lie.
  Future<RelayTarget> _relayForEffective(
    RelayTarget target,
    ProviderContainer container,
  ) async {
    final status = await _softEtherStatusSafe();
    final effective = status.effectiveIp.trim();
    if (effective.isEmpty ||
        effective == '0.0.0.0' ||
        effective == target.dial) {
      return target.copyWith(source: 'softether');
    }
    // The session is on a different address than the one we dialled. Start
    // from the dialled target but drop its country: until the catalog proves
    // where this address lives, "Private relay" is the only honest label.
    var relay = target.copyWith(
      dial: effective,
      countryCode: '',
      countryName: '',
      source: 'softether',
    );
    try {
      final servers = await container.read(serversProvider.future);
      for (final server in servers) {
        if (server.ip != effective) continue;
        final sni = SoftEtherVpn.fqdn(server.hostName);
        relay = relay.copyWith(
          sni: sni.isEmpty ? relay.sni : sni,
          countryCode: server.countryShort.toUpperCase(),
          countryName: server.displayCountry,
        );
        break;
      }
    } catch (_) {}
    _log.addLog(
      '[VpnController] Effective relay $effective (dialed ${target.dial})',
    );
    return relay;
  }

  /// Publishes the relay that actually carries the session. The UI reads this
  /// object only; it must never infer the country from the picker.
  Future<void> _markRelayConnected(
    ProviderContainer container,
    ConnectionStateNotifier connectionNotifier,
    RelayTarget target, {
    required bool holdEngine,
  }) async {
    container.read(connectedRelayProvider.notifier).state = target;
    container.read(softEtherHostProvider.notifier).state =
        '${target.displayName} · ${target.dial}';
    await VpnSessionStore.save(
      label: target.label,
      host: target.dial,
      countryCode: target.countryCode,
      countryName: target.countryName,
    );
    await _saveLastSsl(target);
    _reachability.markAlive(target.dial);
    await RelayMemory.remember(target, network: await _networkForMemory());
    if (HomeRegion.isHome(target.countryCode)) {
      _log.addLog(
        '[VpnController] Exit ${target.dial} is in the device home country '
        '(${HomeRegion.countryCode}); region-locked services will still see it',
      );
    }
    connectionNotifier.holdEngineEvents(holdEngine);
    connectionNotifier.setConnected();
  }

  /// Resolves the country for an OpenVPN candidate from the catalog or the
  /// current pick, so the connected pill stays truthful on that path too.
  Future<RelayTarget> _relayForCandidate(
    Candidate candidate,
    ProviderContainer container,
  ) async {
    var code = candidate.countryCode.toUpperCase();
    var name = candidate.countryName;
    var sni = candidate.sni;
    var ping = candidate.csvPing;
    try {
      final servers = await container.read(serversProvider.future);
      for (final server in servers) {
        if (server.ip != candidate.ip) continue;
        code = server.countryShort.toUpperCase();
        name = server.displayCountry;
        sni = SoftEtherVpn.fqdn(server.hostName);
        if (ping <= 0) ping = server.ping;
        break;
      }
    } catch (_) {}
    // Only an explicitly picked country may fill a gap. In auto mode an
    // unknown exit stays unknown instead of inheriting the picker's label.
    if (code.isEmpty && _strictSelection) {
      code = _serverCountryCode;
      name = _serverCountryName;
    }
    return RelayTarget(
      dial: candidate.ip,
      sni: sni,
      countryCode: code,
      countryName: name,
      pingMs: ping,
      source: 'openvpn',
    );
  }

  /// Probe SoftEther TLS 443 before a native connect. Dead country relays
  /// used to burn the full SoftEther watchdog while the orb stayed on
  /// Connecting.
  ///
  /// On carriers that drop the TLS payload after completing TCP, the shortlist
  /// can come back empty or with a single false friend while a handful of
  /// relays in the wider catalog still work. [container] lets the caller hand
  /// in the catalog so this step can sweep it instead of giving up.
  Future<List<RelayTarget>> _reachableSoftEther(
    List<RelayTarget> targets,
    int generation, {
    ProviderContainer? container,
  }) async {
    final reachable = <RelayTarget>[];
    final dead = <RelayTarget>[];
    final warm = <RelayTarget>[];
    final untested = <RelayTarget>[];
    final previouslyDead = <RelayTarget>[];
    final rtt = <String, int>{};
    for (final target in targets) {
      final probe = _reachability.lookup(target.dial);
      if (probe == null) {
        untested.add(target);
      } else if (probe.ok) {
        warm.add(target);
        rtt[target.dial] = probe.elapsed.inMilliseconds;
      } else {
        previouslyDead.add(target);
      }
    }
    if (warm.isNotEmpty) {
      // The whole fast-connect win: a relay measured moments ago goes straight
      // to the native dial instead of waiting in the probe queue.
      _log.addLog(
        '[VpnController] Warm relays, skipping the probe: '
        '${warm.map((t) => t.dial).join(', ')}',
      );
      reachable.addAll(warm);
    }
    if (untested.isNotEmpty) {
      final probes = await _probeSoftEther(untested);
      if (generation != _rotationGeneration) return const <RelayTarget>[];
      for (var i = 0; i < untested.length; i++) {
        final probe = probes[i];
        (probe.$1 ? reachable : dead).add(untested[i]);
        if (probe.$1) rtt[untested[i].dial] = probe.$2;
      }
      _log.addLog(
        '[VpnController] SoftEther probe: ${reachable.length}/${targets.length} '
        'reachable'
        '${dead.isEmpty ? '' : '; unreachable: ${dead.map((t) => t.dial).join(', ')}'}',
      );
    }

    if (reachable.isEmpty) {
      // Every bundled relay is dead: ask the source for a newer list before
      // giving up on SoftEther and spending the rest of the budget on OpenVPN.
      final fresh = await _freshCandidates();
      if (generation != _rotationGeneration) return const <RelayTarget>[];
      final seen = targets.map((t) => t.dial).toSet();
      final freshTargets = <RelayTarget>[];
      for (final candidate in fresh) {
        if (freshTargets.length >= 8) break;
        if (candidate.ip.isEmpty || !seen.add(candidate.ip)) continue;
        if (_strictSelection && _serverCountryCode.isNotEmpty) {
          final sameServer = _serverIp != null && candidate.ip == _serverIp;
          final sameCountry =
              candidate.countryCode.toUpperCase() == _serverCountryCode;
          if (!sameServer && !sameCountry) continue;
        }
        freshTargets.add(
          RelayTarget(
            dial: candidate.ip,
            sni: candidate.sni.isEmpty ? candidate.ip : candidate.sni,
            countryCode: candidate.countryCode,
            countryName: candidate.countryName,
            pingMs: candidate.csvPing,
            source: 'fresh',
          ),
        );
      }
      if (freshTargets.isNotEmpty) {
        final probes = await _probeSoftEther(freshTargets);
        if (generation != _rotationGeneration) return const <RelayTarget>[];
        for (var i = 0; i < freshTargets.length; i++) {
          final probe = probes[i];
          (probe.$1 ? reachable : dead).add(freshTargets[i]);
          if (probe.$1) rtt[freshTargets[i].dial] = probe.$2;
        }
        _log.addLog(
          '[VpnController] Fresh SoftEther probe: '
          '${reachable.length}/${freshTargets.length} reachable',
        );
      }
    }

    // A cached failure is not a verdict. When the fresh list is dead too, the
    // relays that failed earlier on this network get one more real probe.
    if (reachable.isEmpty && previouslyDead.isNotEmpty) {
      final probes = await _probeSoftEther(previouslyDead);
      if (generation != _rotationGeneration) return const <RelayTarget>[];
      for (var i = 0; i < previouslyDead.length; i++) {
        final probe = probes[i];
        if (probe.$1) {
          reachable.add(previouslyDead[i]);
          rtt[previouslyDead[i].dial] = probe.$2;
        }
      }
      _log.addLog(
        '[VpnController] Re-probed ${previouslyDead.length} previously dead '
        'SoftEther relays: ${reachable.length} reachable',
      );
    }

    // Two independent survivors are enough to dial; anything less means the
    // shortlist is lying about this network and the rest of the catalog has
    // to be asked. This is the difference between "VPN Gate is blocked" and
    // "the eight relays we happened to list are blocked".
    if (reachable.length < 2 && container != null) {
      final swept = await _sweepSoftEther(
        container,
        {for (final target in targets) target.dial, ...dead.map((t) => t.dial)},
        generation,
        rtt,
      );
      if (generation != _rotationGeneration) return const <RelayTarget>[];
      for (final target in swept) {
        if (reachable.any((t) => t.dial == target.dial)) continue;
        reachable.add(target);
      }
    }

    // Order by measured TLS RTT: the handshake already pays the carrier's
    // round trip, so the tunnel that comes up first is the one closest to us.
    reachable.sort(
      (a, b) => (rtt[a.dial] ?? 1 << 20).compareTo(rtt[b.dial] ?? 1 << 20),
    );
    final ordered = _foreignFirst(reachable);

    if (ordered.isEmpty) {
      _log.addLog(
        '[VpnController] No reachable SoftEther relay for '
        '${_strictSelection ? _serverLabel : 'auto'}; skipping SoftEther',
      );
    } else if (_strictSelection) {
      final escape = ordered
          .where(
            (t) =>
                t.source == 'escape' ||
                t.source == 'proven' ||
                t.source == 'fresh' ||
                t.source == 'sweep',
          )
          .toList();
      final native = ordered
          .where((t) => t.source == 'selected' || t.source == 'same-country')
          .toList();
      if (native.isEmpty && escape.isNotEmpty) {
        _log.addLog(
          '[VpnController] Selected country SoftEther unreachable; '
          'escaping via ${escape.map((t) => '${t.countryCode}:${t.dial}').join(', ')}',
        );
      }
    }
    return ordered;
  }

  /// TLS-probes the whole catalog in waves and returns the survivors.
  ///
  /// Runs only when the shortlist produced fewer than two real TLS handshakes.
  /// Waves stop as soon as two survivors exist, so the common censored-carrier
  /// case costs one or two waves instead of a full scan.
  Future<List<RelayTarget>> _sweepSoftEther(
    ProviderContainer container,
    Set<String> alreadyProbed,
    int generation,
    Map<String, int> rtt,
  ) {
    // A background warm sweep and a connect legitimately want the same scan.
    // Share the in-flight future instead of probing every relay twice and
    // competing for the carrier's radio.
    final running = _sweepInFlight;
    if (running != null) return running;
    final future = _runSweep(container, alreadyProbed, generation, rtt);
    _sweepInFlight = future;
    return future.whenComplete(() {
      if (identical(_sweepInFlight, future)) _sweepInFlight = null;
    });
  }

  Future<List<RelayTarget>> _runSweep(
    ProviderContainer container,
    Set<String> alreadyProbed,
    int generation,
    Map<String, int> rtt,
  ) async {
    final List<VpnServer> servers;
    try {
      servers = await container.read(serversProvider.future);
    } catch (_) {
      return const [];
    }
    if (generation != _rotationGeneration) return const [];
    final seen = {...alreadyProbed};
    final pool = <RelayTarget>[];
    for (final server in servers) {
      if (server.ip.isEmpty || !seen.add(server.ip)) continue;
      pool.add(
        RelayTarget(
          dial: server.ip,
          sni: SoftEtherVpn.fqdn(server.hostName),
          countryCode: server.countryShort.toUpperCase(),
          countryName: server.displayCountry,
          pingMs: server.ping,
          source: 'sweep',
        ),
      );
    }
    if (pool.isEmpty) return const [];
    // The merge of bundled + published lists can exceed one useful sweep.
    // CSV ping is measured against the relay itself, so it is the best
    // ordering hint available before the first TLS handshake.
    pool.sort((a, b) {
      if (a.pingMs <= 0 && b.pingMs > 0) return 1;
      if (b.pingMs <= 0 && a.pingMs > 0) return -1;
      return a.pingMs.compareTo(b.pingMs);
    });
    final capped = pool.length > 160 ? pool.sublist(0, 160) : pool;
    _log.addLog(
      '[VpnController] Censored shortlist; TLS-sweeping ${capped.length} '
      'catalog relays in waves of $_sweepBatch',
    );
    final survivors = <RelayTarget>[];
    for (var i = 0; i < capped.length; i += _sweepBatch) {
      if (generation != _rotationGeneration) return const [];
      final slice = capped.sublist(
        i,
        (i + _sweepBatch).clamp(0, capped.length),
      );
      final probes = await _probeSoftEther(slice);
      if (generation != _rotationGeneration) return const [];
      for (var j = 0; j < slice.length; j++) {
        final probe = probes[j];
        if (!probe.$1) continue;
        survivors.add(slice[j]);
        rtt[slice[j].dial] = probe.$2;
      }
      if (survivors.length >= 2) break;
    }
    _log.addLog(
      '[VpnController] TLS sweep: ${survivors.length} relay(s) alive on this '
      'network${survivors.isEmpty ? '' : ': '
                '${survivors.map((t) => '${t.countryCode}:${t.dial}').join(', ')}'}',
    );
    return survivors;
  }

  /// Probes run in parallel; the result is both a boolean per target and an
  /// RTT for the scoring table. Recorded under the network the probe started
  /// on, and never written into the in-memory cache if the network moved
  /// mid-probe (the cache was cleared for a reason).
  Future<List<(bool, int)>> _probeSoftEther(
    List<RelayTarget> targets, {
    String? network,
  }) async {
    if (targets.isEmpty) return const [];
    final cacheNetwork = _reachability.network;
    final fingerprint = network ?? _networkFingerprint;
    final results = await Future.wait([
      for (final target in targets) _probeOneSoftEther(target),
    ]);
    if (cacheNetwork == _reachability.network) {
      for (var i = 0; i < targets.length; i++) {
        final result = results[i];
        _reachability.record(
          targets[i].dial,
          ok: result.$1,
          elapsed: Duration(milliseconds: result.$2),
        );
      }
    }
    if (fingerprint != null &&
        fingerprint != 'offline' &&
        fingerprint != 'unknown') {
      unawaited(
        RelayMemory.recordProbes(
          {
            for (var i = 0; i < targets.length; i++)
              targets[i].dial: results[i].$1,
          },
          network: fingerprint,
          rttMs: {
            for (var i = 0; i < targets.length; i++)
              if (results[i].$2 > 0) targets[i].dial: results[i].$2,
          },
        ),
      );
    }
    return results;
  }

  Future<(bool, int)> _probeOneSoftEther(RelayTarget target) async {
    final watch = Stopwatch()..start();
    try {
      // Irancell/Hamrah Aval-style middleboxes accept the TCP handshake and
      // then black-hole everything after it, so a bare connect() reports
      // blocked relays as healthy. Only a completed TLS handshake proves the
      // relay can carry the SoftEther session. VPN Gate hubs use self-signed
      // certificates; the native dial disables verification too.
      final attempt = SecureSocket.connect(
        target.dial,
        443,
        timeout: _softEtherProbeTimeout,
        onBadCertificate: (_) => true,
      );
      // RawSecureSocket.connect applies `timeout` to the TCP connect only.
      // A relay that accepts the handshake and then stalls TLS would leave
      // this future pending for minutes, freezing warm probes and the sweep.
      // Bound the whole handshake, and destroy a socket that arrives late.
      unawaited(
        attempt
            .then((socket) {
              try {
                socket.destroy();
              } catch (_) {}
            })
            .catchError((_) {}),
      );
      final socket = await attempt.timeout(_softEtherProbeTimeout);
      socket.destroy();
      watch.stop();
      return (true, watch.elapsedMilliseconds);
    } catch (_) {
      watch.stop();
      return (false, 0);
    }
  }

  /// A TCP probe can pass and the real dial still fail (TLS, hub, auth).
  /// Record it as a relay-level failure and stop trusting network memory for
  /// this relay on this network.
  Future<void> _recordSoftEtherFailure(RelayTarget target) async {
    final network = await _networkForMemory();
    _reachability.markDead(target.dial);
    await RelayMemory.recordDialFailure(target.dial, network: network);
    if (target.source == 'network-memory') {
      await RelayMemory.forget(target.dial, network: network);
    }
  }

  /// SoftEther inside the Apple packet tunnel. The profile is a marker the
  /// extension reads; OpenVPN never sees it when this path connects.
  Future<bool> _tryAppleSoftEther(
    ProviderContainer container,
    ConnectionStateNotifier connectionNotifier,
  ) async {
    final generation = _rotationGeneration;
    final targets = await _softEtherTargets(container);
    if (targets.isEmpty || generation != _rotationGeneration) return false;

    final reachable = await _reachableSoftEther(
      targets,
      generation,
      container: container,
    );
    if (reachable.isEmpty || generation != _rotationGeneration) return false;

    for (final target in reachable.take(3)) {
      if (generation != _rotationGeneration) return false;
      if (_manualDisconnect) {
        try {
          await _vpnService.disconnect();
        } catch (_) {}
        return false;
      }
      if (_connectQueued) return false;
      connectionNotifier.setConnecting();
      _log.addLog(
        '[VpnController] Apple SoftEther ${target.dial} (${target.countryCode})',
      );
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
        csvPing: target.pingMs,
        b64: '',
        config: config,
      );
      final ok = await _attemptCandidate(
        candidate,
        watchdogDuration: _appleSoftEtherWatchdog,
      );
      if (generation != _rotationGeneration) return false;
      if (_manualDisconnect) {
        try {
          await _vpnService.disconnect();
        } catch (_) {}
        return false;
      }
      if (_connectQueued) return false;
      if (ok) {
        _log.addLog('[VpnController] CONNECTED via SoftEther ${target.dial}');
        await _markRelayConnected(
          container,
          connectionNotifier,
          target.copyWith(source: 'softether'),
          holdEngine: false,
        );
        return true;
      }
      _log.addLog('[VpnController] Apple SoftEther failed ${target.dial}');
      await _recordSoftEtherFailure(target);
    }
    return false;
  }

  /// SoftEther dials tried before OpenVPN. Returns true when one comes up.
  Future<bool> _tryOneSoftEther(
    ProviderContainer container,
    ConnectionStateNotifier connectionNotifier,
  ) async {
    final sslGen = _rotationGeneration;
    final targets = await _softEtherTargets(container);
    if (targets.isEmpty || sslGen != _rotationGeneration) return false;
    final reachable = await _reachableSoftEther(
      targets,
      sslGen,
      container: container,
    );
    if (reachable.isEmpty || sslGen != _rotationGeneration) return false;
    for (final target in reachable.take(3)) {
      if (sslGen != _rotationGeneration) return false;
      if (_manualDisconnect || _connectQueued) return false;
      connectionNotifier.setConnecting();
      _log.addLog(
        '[VpnController] SoftEther dial ${target.dial} (${target.countryCode})',
      );
      container.read(softEtherHostProvider.notifier).state =
          '${target.displayName} · ${target.dial}';
      var result = await SoftEtherVpn.connect(
        dial: target.dial,
        sni: target.sni,
      );
      // A canceled handshake can keep the native service gate closed for a
      // moment. Give it time to unwind instead of burning the next relay.
      if (!result.ok &&
          (result.detail == 'busy' || result.detail == 'relay_changed')) {
        await SoftEtherVpn.disconnect();
        for (var attempt = 0; attempt < 16 && !result.ok; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (sslGen != _rotationGeneration) return false;
          if (_manualDisconnect || _connectQueued) return false;
          result = await SoftEtherVpn.connect(
            dial: target.dial,
            sni: target.sni,
          );
        }
      }
      if (_manualDisconnect) {
        // The user pressed disconnect while the handshake was in flight. Do
        // not let a late success resurrect a tunnel they already closed.
        try {
          await SoftEtherVpn.disconnect();
        } catch (_) {}
        return false;
      }
      if (sslGen != _rotationGeneration || _connectQueued) return false;
      if (result.ok || result.detail == 'already running') {
        final relay = await _relayForEffective(target, container);
        _log.addLog(
          '[VpnController] CONNECTED via SoftEther ${relay.dial} '
          '(${relay.countryCode})',
        );
        await _markRelayConnected(
          container,
          connectionNotifier,
          relay,
          holdEngine: true,
        );
        return true;
      }
      _log.addLog('[VpnController] SoftEther dial failed: ${result.detail}');
      await _recordSoftEtherFailure(target);
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
  Future<bool> _attemptCandidate(
    Candidate candidate, {
    Duration? watchdogDuration,
  }) async {
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

    final attemptWatchdog = watchdogDuration ?? _attemptWatchdog;
    watchdog = Timer(attemptWatchdog, () {
      _log.addLog(
        '[VpnController] Watchdog fired for ${dial.ip}:${dial.port} '
        '(no tunnel in ${attemptWatchdog.inSeconds}s)',
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
      sni: candidate.sni,
      countryCode: candidate.countryCode,
      countryName: candidate.countryName,
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
    _manualDisconnect = false;
    _recoveryGeneration++;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _log.addLog('[VpnController] Switching relay to ${_serverHost ?? 'auto'}');
    container.read(connectionStateProvider.notifier).holdEngineEvents(false);
    container.read(softEtherHostProvider.notifier).state = null;
    container.read(connectedRelayProvider.notifier).state = null;
    await SoftEtherVpn.disconnect();
    await _connect();
  }

  void _cancelRecovery() {
    _manualDisconnect = true;
    _connectQueued = false;
    _recoveryGeneration++;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
  }

  Future<void> _stopVpn() async {
    final container = _container;
    if (container == null) return;
    final connectionNotifier = container.read(connectionStateProvider.notifier);
    _log.addLog('[VpnController] Stopping VPN...');
    _rotationGeneration++;
    _cancelRecovery();
    _cancelConnectBudget();
    connectionNotifier.holdEngineEvents(false);
    connectionNotifier.setDisconnecting();
    container.read(softEtherHostProvider.notifier).state = null;
    container.read(connectedRelayProvider.notifier).state = null;
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
    _cancelRecovery();
    _cancelConnectBudget();
    connectionNotifier.holdEngineEvents(false);
    connectionNotifier.setDisconnecting();
    container.read(softEtherHostProvider.notifier).state = null;
    container.read(connectedRelayProvider.notifier).state = null;
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
    _recoveryTimer?.cancel();
    _networkWatchTimer?.cancel();
    _networkReconnectTimer?.cancel();
    _vpnService.dispose();
    _initialized = false;
  }
}
