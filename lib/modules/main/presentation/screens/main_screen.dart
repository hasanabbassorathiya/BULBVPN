import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvpn_dart/vpn_status.dart' as vpn_status;
import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/network_watch.dart';
import 'package:bulbvpn/modules/core/reality/reality_engine.dart';
import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/relay_memory.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:bulbvpn/modules/core/server_catalog.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/modules/core/split_tunnel.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:bulbvpn/modules/core/tunnel_liveness.dart';
import 'package:bulbvpn/modules/core/vpn_controller.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/core/vpn_service.dart';
import 'package:bulbvpn/modules/core/vpn_session_store.dart';
import 'package:bulbvpn/modules/main/application/relay_evidence_provider.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/home_composition.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/metered_card.dart';
import 'package:bulbvpn/shared/metered/tariff_table.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
import 'package:bulbvpn/modules/monetization/ad_banner.dart';
import 'package:bulbvpn/modules/monetization/ad_config.dart';
import 'package:bulbvpn/modules/monetization/ads_remote_config.dart';
import 'package:bulbvpn/modules/monetization/premium.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/air/air_phase_map.dart';
import 'package:bulbvpn/shared/air/connect_trace.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:bulbvpn/shared/providers/connect_trace_provider.dart';
import 'package:bulbvpn/shared/providers/data_proof_provider.dart';
import 'package:bulbvpn/shared/providers/ip_info_provider.dart';
import 'package:bulbvpn/shared/providers/exit_ip_provider.dart';
import 'package:bulbvpn/shared/widgets/staggered_in.dart';

export 'package:bulbvpn/modules/core/server_catalog.dart' show serversProvider;
export 'package:bulbvpn/modules/core/vpn_server.dart' show VpnServer;

final log = Log();

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  VpnController? _vpnController;
  bool _vpnInitialized = false;
  Timer? _ticker;

  DateTime? _connectedAt;
  int? _prevByteIn;
  int? _prevByteUp;
  String _sessionLabel = '00:00:00';
  String _downRateLabel = '—';
  String _upRateLabel = '—';
  String _clockLabel = _localClock();
  bool _refreshingIps = false;
  String _preparedLabel = '';

  static String _localClock() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    log.addLog('[MainScreen] initState');
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    Future.microtask(_loadPrepared);
  }

  /// The relay that last carried this network. Shown while idle so the first
  /// tap starts from a known-good endpoint instead of a blank slate.
  Future<void> _loadPrepared() async {
    try {
      final relay = await RelayMemory.recall();
      final name = relay?.displayName ?? '';
      if (!mounted || name == _preparedLabel) return;
      setState(() => _preparedLabel = name);
    } catch (_) {}
  }

  /// Carrier switched Wi-Fi ⇄ cellular while the app was open. Old latency
  /// numbers describe the previous path, so they are dropped instead of
  /// re-measured: the user came back to connect, not to watch a sweep.
  Future<void> _onNetworkChanged() async {
    log.addLog('[MainScreen] Network changed; dropping stale latency');
    unawaited(_loadPrepared());
    ref.read(serverPingProvider.notifier).invalidate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_vpnInitialized) {
      _vpnInitialized = true;
      _initVpnController();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreLiveTunnel();
      if (ref.read(connectionStateProvider).status ==
          ConnectionStatus.connected) {
        _vpnController?.verifyConnectionNow();
      } else {
        unawaited(ref.read(ipWhoProvider.notifier).refresh(before: true));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _initVpnController() async {
    log.addLog('[MainScreen] Initializing VPN controller...');
    final container = ProviderScope.containerOf(context);
    _vpnController = VpnController();
    try {
      await _vpnController!.initialize(container);
      log.addLog('[MainScreen] VPN controller initialized successfully');
      final picked = ref.read(selectedServerProvider);
      if (picked != null) _applyServerConfig(picked);
      await _restoreLiveTunnel();
      await _connectIfLaunchRequested();
    } catch (e, stackTrace) {
      log.addLog('[MainScreen] VPN Controller init error: $e');
      log.addLog('[MainScreen] Stack trace: $stackTrace');
    }
  }

  bool _restoringTunnel = false;
  bool _restoreAgain = false;

  /// One restore at a time. This runs from launch initialisation and from
  /// every resume, and each pass awaits the session store and the platform
  /// channel; two overlapping passes let the older read publish the newer
  /// state, which is how the orb ends up contradicting Android's VPN key. A
  /// resume that arrives mid-pass is remembered and runs once the current one
  /// lands, so nothing is lost by serialising.
  Future<void> _restoreLiveTunnel() async {
    if (_restoringTunnel) {
      _restoreAgain = true;
      return;
    }
    _restoringTunnel = true;
    try {
      await _restoreLiveTunnelOnce();
    } finally {
      _restoringTunnel = false;
      if (_restoreAgain) {
        _restoreAgain = false;
        unawaited(_restoreLiveTunnel());
      }
    }
  }

  Future<void> _restoreLiveTunnelOnce() async {
    final current = ref.read(connectionStateProvider).status;
    if (current == ConnectionStatus.disconnecting) return;
    if (RealityEngine.instance.isSessionActive) {
      await _restoreRealityTunnel();
      return;
    }
    // This runs from a lifecycle callback, so a platform-channel exception
    // must never escape as an unhandled async error. If neither engine can be
    // asked, treat the tunnel as unverified rather than claiming it is up.
    var tunnel = SoftEtherStatus.down;
    try {
      tunnel = await SoftEtherVpn.status();
    } catch (e) {
      log.addLog('[MainScreen] SoftEther status failed on resume: $e');
    }
    var engine = vpn_status.ConnectionStatus.disconnected;
    try {
      engine = await VpnService().getStatus();
    } catch (e) {
      log.addLog('[MainScreen] Engine status failed on resume: $e');
    }
    final live =
        tunnel.isLive || engine == vpn_status.ConnectionStatus.connected;
    if (!mounted) return;
    if (!live) {
      // The UI process and the tunnel do not share a lifetime: XrayVPNService
      // runs in `:RunSoLibXrayDaemon` and keeps forwarding after Android
      // restarts the app, so "this process has no session" is not evidence
      // that the tunnel died. Ask the framework before contradicting the OS
      // status bar, and keep the relay record if the tunnel is still ours.
      final session = await VpnSessionStore.read();
      final system = await querySystemVpnState();
      if (!mounted) return;
      final orphan = TunnelLiveness.classify(
        system,
        realitySessionRecorded: session != null,
      );
      if (orphan == OrphanTunnel.reality && session != null) {
        await _adoptOrphanRealityTunnel(session);
        return;
      }
      final latest = ref.read(connectionStateProvider).status;
      if (latest == ConnectionStatus.connected) {
        if (orphan == OrphanTunnel.otherOwner) {
          log.addLog(
            '[MainScreen] Another app owns the active VPN; our tunnel is gone',
          );
        } else if (orphan == OrphanTunnel.ours) {
          // Ours, but not forwarding: the honest claim is still disconnected.
          // The interface stays installed (a deliberate kill switch must not be
          // lifted by a resume), and the session record survives so the next
          // connect retries the relay this network was already using.
          log.addLog(
            '[MainScreen] Our own TUN is still held but carrying no traffic; '
            'keeping the relay record',
          );
        }
        final notifier = ref.read(connectionStateProvider.notifier);
        notifier.holdEngineEvents(false);
        notifier.setDisconnected();
        ref.read(connectedRelayProvider.notifier).state = null;
        ref.read(softEtherHostProvider.notifier).state = null;
        _connectedAt = null;
        _prevByteIn = null;
        log.addLog('[MainScreen] Cleared stale connected state');
      } else if (latest == ConnectionStatus.disconnected ||
          latest == ConnectionStatus.error ||
          latest == ConnectionStatus.noInternet) {
        // The tunnel is really gone. Drop the persisted relay too, so a later
        // session cannot inherit the country of a dead one.
        if (TunnelLiveness.clearsSessionOnRestart(
          system,
          realitySessionRecorded: session != null,
        )) {
          await VpnSessionStore.clear();
        }
      }
      return;
    }
    if (ref.read(connectionStateProvider).status ==
        ConnectionStatus.disconnecting) {
      return;
    }
    final session = await VpnSessionStore.read();
    if (!mounted) return;
    final notifier = ref.read(connectionStateProvider.notifier);
    notifier.adoptLiveTunnel(holdEngine: tunnel.isLive);
    final label = session?.label.isNotEmpty == true
        ? session!.label
        : (tunnel.host.isNotEmpty ? tunnel.host : null);
    if (label != null) {
      ref.read(softEtherHostProvider.notifier).state = label;
    }
    if (session != null) {
      final relay = RelayTarget(
        dial: session.host,
        sni: tunnel.host,
        countryCode: session.countryCode,
        countryName: session.countryName,
        source: 'restored',
      );
      if (relay.countryCode.isNotEmpty || relay.countryName.isNotEmpty) {
        ref.read(connectedRelayProvider.notifier).state = relay;
      }
      _connectedAt = DateTime.fromMillisecondsSinceEpoch(session.startedMs);
      _updateSession();
    }
    if (ref.read(connectedRelayProvider) == null) {
      // A live tunnel with no persisted relay metadata is still live. Publish
      // an explicit unknown relay so the orb and the pill cannot disagree.
      ref.read(connectedRelayProvider.notifier).state = RelayTarget(
        dial: tunnel.host,
        sni: tunnel.host,
        source: 'restored',
      );
    }
    log.addLog('[MainScreen] Restored live tunnel ${label ?? tunnel.host}');
  }

  /// The REALITY engine still owns a native session (resume, or the app was
  /// backgrounded while connected). Its status stream is authoritative, so
  /// re-adopt it instead of asking SoftEther/OpenVPN, which are idle and
  /// would report the tunnel as dead.
  Future<void> _restoreRealityTunnel() async {
    final session = await VpnSessionStore.read();
    if (!mounted) return;
    final relays = await _realityRelaysSafe();
    final match = RealityCatalog.findByHost(relays, session?.host);
    ref.read(connectionStateProvider.notifier).adoptRealityTunnel();
    if (match != null) {
      ref.read(connectedRelayProvider.notifier).state = match.toTarget(
        source: 'restored',
      );
      ref.read(softEtherHostProvider.notifier).state =
          '${match.displayName} · ${match.host}';
    } else if (session != null) {
      ref.read(connectedRelayProvider.notifier).state = RelayTarget(
        dial: session.host,
        sni: session.host,
        countryCode: session.countryCode,
        countryName: session.countryName,
        source: 'restored',
        trustTier: TrustTier.community,
      );
      ref.read(softEtherHostProvider.notifier).state = session.label;
    }
    if (session != null) {
      _connectedAt = DateTime.fromMillisecondsSinceEpoch(session.startedMs);
      _updateSession();
    }
    log.addLog(
      '[MainScreen] Restored live REALITY tunnel '
      '${match?.endpoint ?? session?.host ?? ''}',
    );
  }

  /// Re-adopts a REALITY tunnel the daemon survived without us.
  ///
  /// Without this the app contradicts the OS: the key icon says connected, the
  /// orb says disconnected, and Disconnect cannot stop what it cannot see.
  Future<void> _adoptOrphanRealityTunnel(VpnSessionSnapshot session) async {
    final relays = await _realityRelaysSafe();
    if (!mounted) return;
    final match = RealityCatalog.findByHost(relays, session.host);
    await RealityEngine.instance.adoptDaemonSession(relay: match);
    if (!mounted) return;
    log.addLog(
      '[MainScreen] Adopted REALITY tunnel the daemon held across a restart',
    );
    await _restoreRealityTunnel();
    if (!mounted) return;
    _vpnController?.verifyConnectionNow();
  }

  Future<List<RealityRelay>> _realityRelaysSafe() async {
    final cached = ref.read(realityRelaysProvider).valueOrNull;
    if (cached != null) return cached;
    try {
      return await RealityCatalog.load();
    } catch (e) {
      log.addLog('[MainScreen] REALITY catalog unavailable: $e');
      return const <RealityRelay>[];
    }
  }

  void _applyServerConfig(VpnServer server) {
    final ctrl = _vpnController;
    if (ctrl == null) return;
    try {
      final config = utf8.decode(base64.decode(server.openVpnConfigBase64));
      ctrl.selectServerConfig(
        config,
        '${server.displayCountry} · ${server.ip}',
        hostName: server.hostName,
        ip: server.ip,
        countryCode: server.countryShort,
        countryName: server.displayCountry,
      );
    } catch (e) {
      log.addLog('[MainScreen] ERROR decoding server config: $e');
      ref.read(selectedServerProvider.notifier).state = null;
      ctrl.clearServerConfig();
    }
  }

  void _tick() {
    if (!mounted) return;
    try {
      _updateSession();
    } on FlutterError {
      // Element deactivated mid route transition; the next tick catches up.
    }
  }

  void _updateSession() {
    final cs = ref.read(connectionStateProvider);
    final clock = _localClock();
    if (cs.status == ConnectionStatus.connected) {
      _connectedAt ??= DateTime.now();
      final session = formatDuration(DateTime.now().difference(_connectedAt!));
      final byteIn = cs.totalDownload;
      var down = _downRateLabel;
      if (_prevByteIn != null && byteIn >= _prevByteIn!) {
        down = formatMbps(byteIn - _prevByteIn!);
      }
      _prevByteIn = byteIn;

      var up = _upRateLabel;
      if (cs.hasUpload) {
        if (_prevByteUp != null && cs.totalUpload >= _prevByteUp!) {
          up = formatMbps(cs.totalUpload - _prevByteUp!);
        }
        _prevByteUp = cs.totalUpload;
      } else {
        up = '—';
        _prevByteUp = null;
      }

      if (session != _sessionLabel ||
          down != _downRateLabel ||
          up != _upRateLabel ||
          clock != _clockLabel) {
        setState(() {
          _sessionLabel = session;
          _downRateLabel = down;
          _upRateLabel = up;
          _clockLabel = clock;
        });
      }
    } else if (_connectedAt != null ||
        _sessionLabel != '00:00:00' ||
        _downRateLabel != '—' ||
        _upRateLabel != '—' ||
        _clockLabel != clock) {
      _connectedAt = null;
      _prevByteIn = null;
      _prevByteUp = null;
      setState(() {
        _sessionLabel = '00:00:00';
        _downRateLabel = '—';
        _upRateLabel = '—';
        _clockLabel = clock;
      });
    }
  }

  /// Set only when the process is launched with `--bulb-connect`.
  Future<void> _connectIfLaunchRequested() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('bulb_autoconnect') != true) return;
    await prefs.setBool('bulb_autoconnect', false);
    log.addLog('[MainScreen] Launch requested connect');
    if (!mounted) return;
    await _onConnectPressed();
  }

  Future<void> _onConnectPressed() async {
    log.addLog('[MainScreen] Orb pressed');
    if (_vpnController == null) {
      await _initVpnController();
    }
    if (_vpnController == null) {
      log.addLog('[MainScreen] ERROR: VPN controller still null after init');
      return;
    }
    try {
      await _vpnController!.handleConnectionButton();
    } catch (e, stackTrace) {
      log.addLog('[MainScreen] ERROR in handleConnectionButton: $e');
      log.addLog('[MainScreen] Stack trace: $stackTrace');
    }
  }

  String _proofAge(Duration age) {
    if (age.inSeconds < 5) return 'just now';
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    return '${age.inHours}h ago';
  }

  String _ipLocationLabel(PublicIpInfo info) {
    final parts = [
      info.city,
      info.region,
      info.country,
    ].where((s) => s.trim().isNotEmpty);
    if (parts.isEmpty) return info.isp;
    return info.isp.trim().isEmpty
        ? parts.join(', ')
        : '${parts.join(', ')} · ${info.isp}';
  }

  Future<void> _refreshIps({required bool live}) async {
    if (_refreshingIps) return;
    setState(() => _refreshingIps = true);
    try {
      if (live) {
        // Re-resolve the exit through the tunnel first, then enrich it. The
        // user asked for this lookup, so skip ipwho.is' one-per-minute window.
        await ref.read(exitIpProvider.notifier).refresh();
        await ref
            .read(ipWhoProvider.notifier)
            .refresh(after: true, force: true);
      } else {
        await ref
            .read(ipWhoProvider.notifier)
            .refresh(before: true, force: true);
      }
    } finally {
      if (mounted) setState(() => _refreshingIps = false);
    }
  }

  VoidCallback? _copyIp(String ip) {
    if (ip.isEmpty) return null;
    return () async {
      await Clipboard.setData(ClipboardData(text: ip));
      if (!mounted) return;
      // Both can yield the same ip (before == after when idle); show one toast.
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'IP $ip copied',
              style: AppTextStyles.monoValue(color: context.air.ink, size: 13),
            ),
            backgroundColor: context.air.raised,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = ref.watch(connectionStateProvider);
    final selected = ref.watch(selectedServerProvider);
    final pingState = ref.watch(serverPingProvider);
    // Watching also boots the Remote Config fetch; ads stay off by default and
    // disappear for Premium accounts.
    final adsEnabled =
        ref.watch(adsEnabledProvider) && ref.watch(adsVisibleProvider);
    final catalog =
        ref.watch(serversProvider).valueOrNull ?? const <VpnServer>[];
    final fastest = _fastestServer(catalog, pingState.byIp);
    final connectedRelay = ref.watch(connectedRelayProvider);
    final exitIp = ref.watch(exitIpProvider);
    final beforeIp = ref.watch(
      ipWhoProvider.select((state) => state.before?.ip),
    );
    // Both engines keep this app inside its own TUN (the SoftEther session
    // socket is exempted through protect()), so the in-app lookup travels
    // through the tunnel and reports the real exit. The pre-tunnel address
    // must never be labelled as the exit.
    final visibleExit =
        exitIp != null && exitIp.ip.isNotEmpty && exitIp.ip != beforeIp
        ? exitIp
        : null;
    final ipWho = ref.watch(ipWhoProvider);
    final status = cs.status;
    final live = status == ConnectionStatus.connected;
    final afterInfo = ipWho.after;
    final afterMatches =
        visibleExit != null &&
        afterInfo != null &&
        afterInfo.ip == visibleExit.ip;

    // Push server picks into the controller.
    ref.listen(selectedServerProvider, (prev, next) {
      if (next == null) {
        _vpnController?.clearServerConfig();
      } else {
        _applyServerConfig(next);
      }
      final live = ref.read(connectionStateProvider).status;
      if (prev?.ip != next?.ip &&
          (live == ConnectionStatus.connected ||
              live == ConnectionStatus.connecting)) {
        _vpnController?.reconnect();
      }
    });
    // Track session start/stop precisely on transitions.
    ref.listen(connectionStateProvider.select((s) => s.status), (prev, next) {
      if (next == ConnectionStatus.analyzing &&
          prev != ConnectionStatus.analyzing) {
        HapticFeedback.selectionClick();
      }
      if (next == ConnectionStatus.connected &&
          prev != ConnectionStatus.connected) {
        HapticFeedback.mediumImpact();
        // An adopted or restored tunnel already stamped the real session start
        // from the persisted record. The status edge lands after that write,
        // so overwriting here would restart the clock on every resume and show
        // a session that never began.
        _connectedAt ??= DateTime.now();
        _prevByteIn = null;
        _prevByteUp = null;
      } else if (prev == ConnectionStatus.connected &&
          next != ConnectionStatus.connected) {
        _connectedAt = null;
        _prevByteIn = null;
        _prevByteUp = null;
        setState(() {
          _sessionLabel = '00:00:00';
          _downRateLabel = '—';
          _upRateLabel = '—';
        });
      }
      if (next == ConnectionStatus.disconnected ||
          next == ConnectionStatus.error ||
          next == ConnectionStatus.noInternet) {
        ref.read(connectTraceProvider.notifier).state = null;
        unawaited(_loadPrepared());
      }
    });
    // Latency belongs to the carrier path, not to the app session.
    ref.listen(networkFingerprintProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final after = next.valueOrNull;
      if (before == null || after == null || before == after) return;
      unawaited(_onNetworkChanged());
    });

    final phase = airPhaseFor(status);
    final stage = connectStageFor(phase);
    final trace = ref.watch(connectTraceProvider);
    final witness = stage == null ? null : trace?.witness;
    // "Connected" is an engine claim. The label may say traffic is confirmed
    // only while a probe through the TUN succeeded recently; otherwise it
    // says what is actually happening (the watchdog is checking).
    final proof = ref.watch(dataProofProvider);
    final proofAge = proof == null ? null : DateTime.now().difference(proof.at);
    final proofFresh =
        proofAge != null && !proofAge.isNegative && proofAge.inSeconds <= 45;
    // In allow mode only the selected packages enter the tunnel, so this app's
    // own probe leaves through the carrier and a byte proof can never arrive.
    // The native flags the engine reconciles every second are the authority on
    // that configuration, so the line names the route instead of promising a
    // check that cannot happen.
    final allowOnly =
        ref.watch(splitTunnelProvider).appliedMode == TunnelMode.allow;
    // While live, only the relay that the native session reports may be shown.
    // The picker and the "fastest" hint are not evidence of where traffic exits.
    final relayLabel = live
        ? (connectedRelay?.displayName ?? 'Connected relay')
        : (selected?.publicLabel ??
              (fastest != null ? 'Auto · ${fastest.publicLabel}' : 'Auto'));
    final connectedServer = live
        ? _serverForDial(connectedRelay?.dial, catalog)
        : null;
    final tierServer = live ? connectedServer : (selected ?? fastest);
    // A community REALITY host is never in the VPN Gate catalog, so the relay
    // itself is the only source that can say who operates the exit.
    final liveTier = connectedRelay?.trustTier ?? connectedServer?.trustTier;
    final pingServer = live ? connectedServer : (selected ?? fastest);
    final measured = pingServer == null ? null : pingState.byIp[pingServer.ip];
    final flagCode =
        (live ? connectedRelay?.code : null) ??
        _countryCode(selected ?? fastest) ??
        '';
    final detail = switch (status) {
      ConnectionStatus.disconnected =>
        _preparedLabel.isEmpty
            ? 'path closed · $relayLabel'
            : 'prepared · $_preparedLabel',
      ConnectionStatus.loading => 'waking the engine',
      ConnectionStatus.connecting => 'opening tunnel · $relayLabel',
      ConnectionStatus.analyzing => 'checking the first byte',
      ConnectionStatus.connected =>
        proofFresh
            ? 'traffic confirmed ${_proofAge(proofAge)} · $relayLabel'
            : allowOnly
            ? 'selected apps only · tunnel up'
            : 'checking traffic · $relayLabel',
      ConnectionStatus.disconnecting => 'closing the tunnel',
      ConnectionStatus.error => 'no working path on this network',
      ConnectionStatus.noInternet => 'this network is offline',
    };

    final state = HomeViewState(
      phase: phase,
      statusTitle: phase.word,
      statusDetail: detail,
      networkLabel: _networkLabel(
        ref.watch(networkFingerprintProvider).valueOrNull ?? '',
      ),
      clockLabel: live ? _sessionLabel : _clockLabel,
      pingLabel: measured?.status == PingStatus.ok ? '${measured!.ms}' : '—',
      downLabel: live ? _downRateLabel : '—',
      upLabel: live && cs.hasUpload ? _upRateLabel : '—',
      trafficLabel: formatVolume(live ? cs.totalDownload : 0),
      protocolLabel: live ? cs.protocol.label : 'Automatic',
      relayLabel: relayLabel,
      exitIp: visibleExit?.ip ?? '',
      exitLocation: visibleExit == null
          ? (live ? 'measuring through tunnel' : '')
          : (afterMatches ? _ipLocationLabel(afterInfo) : visibleExit.loc),
      flagCode: flagCode,
      trustTier: live ? liveTier : tierServer?.trustTier,
      live: live,
      proven: proofFresh,
      proofAge: proofAge,
      measuring: _refreshingIps,
      tight: MediaQuery.sizeOf(context).height < 740,
      connectStage: stage,
      busyWitness: witness,
    );

    // Iranian ISPs blackhole Google's ad hosts, so the request is retried
    // whenever the tunnel goes live. The strip is only asked for when it is
    // both enabled and loadable; when it is not, the tariff sheet keeps its
    // third line.
    final sponsored = adsEnabled && AdConfig.canRequestAds
        ? AdBanner(key: ValueKey('ad-$live'), horizontalInset: 0)
        : null;

    return MeteredCard(
      state: state,
      rows: _tariffRows(
        catalog: catalog,
        byIp: pingState.byIp,
        evidence:
            ref.watch(relayEvidenceProvider).valueOrNull ?? RelayEvidence.empty,
        limit: sponsored == null ? 3 : 2,
      ),
      onConnect: _onConnectPressed,
      onOpenRelays: () => showServerSheet(context),
      onScratch: () => state.exitIp.isEmpty
          ? _refreshIps(live: live)
          : _copyIp(state.exitIp)?.call(),
      banner: sponsored,
    );
  }

  /// The relay lines printed on the connect face. Ranked by the same evidence
  /// the tariff sheet ranks by, so the card and the sheet cannot tell two
  /// different stories about the same host, and each line carries the strongest
  /// reading that exists for it — your own session first, then the fleet probe,
  /// then this phone's handshake. A relay with no reading prints an em dash and
  /// is marked untried rather than quiet.
  List<TariffRow> _tariffRows({
    required List<VpnServer> catalog,
    required Map<String, ServerPing> byIp,
    required RelayEvidence evidence,
    required int limit,
  }) {
    final now = DateTime.now();
    final ranked = sortByMeasuredPing(catalog, byIp).take(limit).toList();
    return [
      for (var i = 0; i < ranked.length; i++)
        () {
          final server = ranked[i];
          final reading = evidence.reading(
            dial: server.ip,
            ping: byIp[server.ip],
            now: now,
          );
          return TariffRow(
            rank: '${i + 1}',
            destination: server.publicLabel,
            measured: reading.value,
            verdict: reading.verdict,
          );
        }(),
    ];
  }

  VpnServer? _serverForDial(String? dial, List<VpnServer> catalog) {
    if (dial == null || dial.isEmpty) return null;
    for (final server in catalog) {
      if (server.ip == dial) return server;
    }
    return null;
  }

  String? _countryCode(VpnServer? server) {
    if (server == null) return null;
    final code = server.countryShort.trim().toLowerCase();
    return code.length == 2 ? code : null;
  }

  String _networkLabel(String fingerprint) {
    if (fingerprint.startsWith('wifi:')) {
      final parts = fingerprint.split(':');
      return parts.length >= 3 && parts[2].isNotEmpty
          ? 'Wi-Fi · ${parts[2]}'
          : 'Wi-Fi';
    }
    if (fingerprint.startsWith('cell:')) return 'Mobile';
    if (fingerprint.startsWith('eth:')) return 'Ethernet';
    if (fingerprint == 'offline') return 'Offline';
    return 'Network';
  }

  VpnServer? _fastestServer(
    List<VpnServer> servers,
    Map<String, ServerPing> byIp,
  ) {
    final ranked = sortByMeasuredPing(servers, byIp);
    for (final server in ranked) {
      final ping = byIp[server.ip];
      if (ping != null && ping.status == PingStatus.ok) return server;
    }
    return ranked.isEmpty ? null : ranked.first;
  }
}
