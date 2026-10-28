import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openvpn_dart/vpn_status.dart' as vpn_status;
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/network_watch.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:bulbvpn/modules/core/server_catalog.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/modules/core/vpn_controller.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/core/vpn_service.dart';
import 'package:bulbvpn/modules/core/vpn_session_store.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/bulb_orb.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
import 'package:bulbvpn/modules/monetization/ad_banner.dart';
import 'package:bulbvpn/modules/monetization/ad_config.dart';
import 'package:bulbvpn/modules/monetization/ads_remote_config.dart';
import 'package:bulbvpn/shared/layout/main_screen_background.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
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
  String _sessionLabel = '00:00:00';
  String _rateLabel = '—';
  bool _refreshingIps = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    log.addLog('[MainScreen] initState');
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    Future.microtask(_warmServers);
  }

  Future<void> _warmServers() async {
    final servers = await ref
        .read(serversProvider.future)
        .catchError((_) => <VpnServer>[]);
    if (!mounted || servers.isEmpty) return;
    // Tabs are rebuilt on every visit; only re-probe when the last sweep is
    // stale so the latency column stops blinking back to "…" each time.
    await ref.read(serverPingProvider.notifier).ensureFresh(servers);
  }

  /// Carrier switched Wi-Fi ⇄ cellular while the app was open. Old latency
  /// numbers describe the previous path, so measure again on this one.
  Future<void> _onNetworkChanged() async {
    log.addLog('[MainScreen] Network changed; re-measuring latency');
    final servers =
        ref.read(serversProvider).valueOrNull ?? const <VpnServer>[];
    if (servers.isEmpty) return;
    await ref.read(serverPingProvider.notifier).pingAll(servers);
  }

  void _refreshPingsIfStale() {
    final servers =
        ref.read(serversProvider).valueOrNull ?? const <VpnServer>[];
    if (servers.isEmpty) return;
    unawaited(ref.read(serverPingProvider.notifier).ensureFresh(servers));
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
      // The network usually changed while the phone slept. Refresh relay
      // reachability in the background so the next tap does not pay for it.
      _vpnController?.warmProbes(delay: const Duration(seconds: 2));
      _refreshPingsIfStale();
      if (ref.read(connectionStateProvider).status !=
          ConnectionStatus.connected) {
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

  Future<void> _restoreLiveTunnel() async {
    final current = ref.read(connectionStateProvider).status;
    if (current == ConnectionStatus.disconnecting) return;
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
      // The tunnel died while the app was backgrounded / the OS revoked it.
      // Returning silently here left the orb on "Connected" while all traffic
      // was already leaving in the clear.
      final latest = ref.read(connectionStateProvider).status;
      if (latest == ConnectionStatus.connected) {
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
        await VpnSessionStore.clear();
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
    if (cs.status == ConnectionStatus.connected) {
      _connectedAt ??= DateTime.now();
      final session = formatDuration(DateTime.now().difference(_connectedAt!));
      final byteIn = cs.totalDownload;
      String rate = _rateLabel;
      if (_prevByteIn != null && byteIn >= _prevByteIn!) {
        rate = formatRate(byteIn - _prevByteIn!);
      }
      _prevByteIn = byteIn;
      setState(() {
        _sessionLabel = session;
        _rateLabel = rate;
      });
    } else if (_connectedAt != null ||
        _sessionLabel != '00:00:00' ||
        _rateLabel != '—') {
      _connectedAt = null;
      _prevByteIn = null;
      setState(() {
        _sessionLabel = '00:00:00';
        _rateLabel = '—';
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

  Widget _buildIpRow({
    required String label,
    required String? ip,
    required String location,
    bool copyable = false,
    Widget? trailing,
  }) {
    return Semantics(
      button: copyable && ip != null,
      label: copyable && ip != null ? 'Exit IP $ip, double tap to copy' : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: (copyable && ip != null) ? _copyIp(ip) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.microLabel(
                color: ip == null ? AppColors.mute : AppColors.steel,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    ip ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.monoValue(
                      size: 15,
                      color: ip == null ? AppColors.mute : AppColors.ink,
                    ),
                  ),
                  if (location.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.mute,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (copyable && ip != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 12, color: AppColors.mute),
            ],
            if (trailing != null) ...[const SizedBox(width: 2), trailing],
          ],
        ),
      ),
    );
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

  Widget _refreshIpsButton({required bool live}) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        tooltip: live ? 'Refresh exit IP' : 'Refresh IP',
        onPressed: _refreshingIps ? null : () => _refreshIps(live: live),
        icon: _refreshingIps
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            : const Icon(Icons.refresh, size: 16, color: AppColors.steel),
      ),
    );
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
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 13,
                fontFamily: 'GeistMono',
              ),
            ),
            backgroundColor: AppColors.raised,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
    };
  }

  void _showLogs() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) => ValueListenableBuilder<int>(
            valueListenable: Log().version,
            builder: (_, __, ___) {
              final lines = Log().recent(200);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.mute,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
                    child: Row(
                      children: [
                        const Text(
                          'Logs',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${lines.length}',
                          style: AppTextStyles.microLabel(),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Log().clearLogs(),
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color: AppColors.amber,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.steel,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: lines.isEmpty
                        ? const Center(
                            child: Text(
                              'No logs yet — tap the bulb to connect.',
                              style: TextStyle(
                                color: AppColors.mute,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                            itemCount: lines.length,
                            itemBuilder: (_, i) {
                              final line = redactRelayDetail(lines[i]);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  line,
                                  style: AppTextStyles.logLine(
                                    color: _logColor(line),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  const SafeArea(child: SizedBox(height: 8)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Color _logColor(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('error') || lower.contains('exception')) {
      return AppColors.red;
    }
    if (lower.contains('connected') || lower.contains('success')) {
      return AppColors.emerald;
    }
    return AppColors.steel;
  }

  BulbPhase _bulbPhase(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return BulbPhase.connected;
      case ConnectionStatus.loading:
      case ConnectionStatus.connecting:
      case ConnectionStatus.analyzing:
      case ConnectionStatus.disconnecting:
        return BulbPhase.connecting;
      case ConnectionStatus.error:
      case ConnectionStatus.noInternet:
        return BulbPhase.failed;
      case ConnectionStatus.disconnected:
        return BulbPhase.idle;
    }
  }

  (String, Color) _statusPresentation(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return ('Connected', AppColors.emerald);
      case ConnectionStatus.loading:
      case ConnectionStatus.connecting:
      case ConnectionStatus.analyzing:
        return ('Connecting', AppColors.amber);
      case ConnectionStatus.disconnecting:
        return ('Disconnecting', AppColors.amber);
      case ConnectionStatus.error:
        return ('Connection failed', AppColors.red);
      case ConnectionStatus.noInternet:
        return ('No internet', AppColors.red);
      case ConnectionStatus.disconnected:
        return ('Standby', AppColors.ink);
    }
  }

  String _stageLabel(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'secure tunnel';
      case ConnectionStatus.connecting:
        return 'opening tunnel';
      case ConnectionStatus.analyzing:
        return 'testing tunnel';
      case ConnectionStatus.loading:
        return 'preparing';
      case ConnectionStatus.disconnecting:
        return 'closing tunnel';
      case ConnectionStatus.error:
      case ConnectionStatus.noInternet:
        return 'tunnel closed';
      case ConnectionStatus.disconnected:
        return 'idle';
    }
  }

  String _orbLabel(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Tap to disconnect';
      case ConnectionStatus.loading:
      case ConnectionStatus.connecting:
      case ConnectionStatus.analyzing:
        return _stageLabel(status);
      case ConnectionStatus.disconnecting:
        return 'closing tunnel';
      case ConnectionStatus.error:
      case ConnectionStatus.noInternet:
        return 'Tap to retry';
      case ConnectionStatus.disconnected:
        return 'Tap to connect';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ref.watch(connectionStateProvider);
    final selected = ref.watch(selectedServerProvider);
    final pingState = ref.watch(serverPingProvider);
    // Watching also boots the Remote Config fetch; ads stay off by default.
    final adsEnabled = ref.watch(adsEnabledProvider);
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
    // While live, only the relay that the native session reports may be shown.
    // The picker and the "fastest" hint are not evidence of where traffic exits.
    // If the relay is momentarily unknown, say so instead of substituting the
    // picker's country (the original US/India label with a Japanese exit bug).
    final endpointLabel = status == ConnectionStatus.connected
        ? (connectedRelay?.displayName ?? 'Connected relay')
        : (selected?.publicLabel ??
              (fastest != null
                  ? 'Auto · ${fastest.publicLabel}'
                  : 'Auto · finding fastest'));

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
      if (next == ConnectionStatus.connected &&
          prev != ConnectionStatus.connected) {
        _connectedAt = DateTime.now();
        _prevByteIn = null;
      } else if (prev == ConnectionStatus.connected &&
          next != ConnectionStatus.connected) {
        _connectedAt = null;
        _prevByteIn = null;
        setState(() {
          _sessionLabel = '00:00:00';
          _rateLabel = '—';
        });
      }
    });
    // Latency belongs to the carrier path, not to the app session.
    ref.listen(networkFingerprintProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final after = next.valueOrNull;
      if (before == null || after == null || before == after) return;
      unawaited(_onNetworkChanged());
    });

    final (statusTitle, statusColor) = _statusPresentation(status);
    final phase = _bulbPhase(status);

    return MainScreenBackground(
      connectionStatus: status,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bounded =
                      constraints.hasBoundedHeight &&
                      constraints.maxHeight.isFinite;
                  // iPad landscape and the iPhone-on-iPad window are shorter
                  // than the phone column. Expanded inside an unbounded
                  // height throws; scroll instead.
                  final tight = !bounded || constraints.maxHeight < 740;
                  final column = Column(
                    mainAxisSize: tight ? MainAxisSize.min : MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ---- Top bar: brand (+ debug logs only) ------------
                      StaggeredIn(
                        child: Row(
                          children: [
                            Flexible(child: _brandWordmark()),
                            const Spacer(),
                            if (kDebugMode)
                              IconButton(
                                onPressed: _showLogs,
                                tooltip: 'Logs',
                                icon: const Icon(
                                  Icons.terminal,
                                  color: AppColors.steel,
                                  size: 22,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ---- Status rail ------------------------------------
                      StaggeredIn(
                        delayMs: 60,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('STATUS', style: AppTextStyles.microLabel()),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: statusColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    statusTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${_stageLabel(status)} · '
                              '${live ? endpointLabel : (selected != null ? '${selected.displayCountry} picked' : 'auto')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.monoValue(
                                size: 11,
                                color: AppColors.steel,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ---- Orb zone (optical center) ---------------------
                      if (tight)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: _orbBlock(
                            ref,
                            phase,
                            tight: true,
                            label: _orbLabel(status),
                          ),
                        )
                      else
                        Expanded(
                          child: Align(
                            alignment: const Alignment(0, -0.18),
                            child: _orbBlock(
                              ref,
                              phase,
                              tight: false,
                              label: _orbLabel(status),
                            ),
                          ),
                        ),

                      // ---- Metric rail: SESSION + DOWN (1.6fr / 1fr) ------
                      StaggeredIn(
                        delayMs: 140,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.hairline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 16,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'SESSION',
                                            style: AppTextStyles.microLabel(),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _sessionLabel,
                                            style: AppTextStyles.metric(
                                              size: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      color: AppColors.hairline,
                                    ),
                                    Expanded(
                                      flex: 10,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 16,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'DOWN',
                                              style: AppTextStyles.microLabel(),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.arrow_downward,
                                                  size: 14,
                                                  color: AppColors.emerald,
                                                ),
                                                const SizedBox(width: 5),
                                                Flexible(
                                                  child: Text(
                                                    _rateLabel,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: AppTextStyles.metric(
                                                      size: 20,
                                                      color: AppColors.emerald,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(height: 1, color: AppColors.hairline),
                              const SizedBox(height: 12),
                              // BEFORE / AFTER IP with ipwho.is enrichment.
                              _buildIpRow(
                                label: 'BEFORE',
                                ip: ipWho.before?.ip,
                                location: ipWho.before == null
                                    ? ''
                                    : _ipLocationLabel(ipWho.before!),
                              ),
                              const SizedBox(height: 10),
                              Container(height: 1, color: AppColors.hairline),
                              const SizedBox(height: 10),
                              _buildIpRow(
                                label: visibleExit == null
                                    ? 'EXIT IP'
                                    : 'AFTER',
                                ip: visibleExit?.ip,
                                location: visibleExit == null
                                    ? (live ? 'measuring through tunnel…' : '')
                                    : (afterMatches
                                          ? _ipLocationLabel(afterInfo)
                                          : visibleExit.loc),
                                copyable: true,
                                trailing: _refreshIpsButton(live: live),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ---- Sponsored slot (kept clear of the connect
                      // control so an orb tap cannot become an ad click).
                      // Iranian ISPs blackhole Google's ad hosts, so the
                      // request is retried whenever the tunnel goes live. ----
                      if (adsEnabled && AdConfig.canRequestAds) ...[
                        AdBanner(
                          key: ValueKey('ad-$live'),
                          horizontalInset: 40,
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ---- Server pill ------------------------------------
                      StaggeredIn(
                        delayMs: 200,
                        child: _serverPill(
                          selected,
                          catalog: catalog,
                          connectedRelay: connectedRelay,
                          live: live,
                          fastest: fastest,
                          ping: fastest == null
                              ? null
                              : pingState.byIp[fastest.ip],
                          probing: pingState.probing && selected == null,
                        ),
                      ),

                      // ---- Nav clearance ----------------------------------
                      SizedBox(height: tight ? 72 : 96),
                    ],
                  );
                  if (tight) {
                    return SingleChildScrollView(child: column);
                  }
                  return column;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _orbBlock(
    WidgetRef ref,
    BulbPhase phase, {
    required bool tight,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Builder(
          builder: (context) {
            final total = ref.watch(
              connectionStateProvider.select((s) => s.totalDownload),
            );
            final delta = total - (_prevByteIn ?? total);
            return BulbOrb(
              phase: phase,
              onTap: _onConnectPressed,
              size: tight ? 156 : 210,
              byteDelta: delta.clamp(0, 1 << 30),
            );
          },
        ),
        const SizedBox(height: 20),
        StaggeredIn(
          delayMs: 100,
          offset: 8,
          child: Text(
            label,
            style: AppTextStyles.microLabel(
              color: phase == BulbPhase.idle ? AppColors.steel : AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }

  Widget _brandWordmark() {
    return Row(
      children: [
        const Text(
          'BULB',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const Text(
          'VPN',
          style: TextStyle(
            color: AppColors.amber,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(width: 10),
        if (MediaQuery.sizeOf(context).width >= 390)
          Flexible(
            child: Text(
              'SECURE TUNNEL',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.microLabel(),
            ),
          ),
      ],
    );
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

  Widget _serverPill(
    VpnServer? selected, {
    required List<VpnServer> catalog,
    required RelayTarget? connectedRelay,
    required bool live,
    VpnServer? fastest,
    ServerPing? ping,
    bool probing = false,
  }) {
    // The flag, title and badge must all describe the same thing. Mixing the
    // picker's country with the connected relay's name was the visible symptom
    // of the old JP fallback overriding the selected server.
    final liveRelay = live ? connectedRelay : null;
    final flagCode = live
        ? (liveRelay == null || liveRelay.code.isEmpty ? null : liveRelay.code)
        : (selected != null
              ? (selected.countryShort.toLowerCase().length == 2
                    ? selected.countryShort.toLowerCase()
                    : null)
              : (fastest != null &&
                        fastest.countryShort.toLowerCase().length == 2
                    ? fastest.countryShort.toLowerCase()
                    : null));
    final title = live
        ? (liveRelay?.displayName ?? 'Connected relay')
        : (selected?.publicLabel ??
              (fastest != null
                  ? 'Auto · ${fastest.publicLabel}'
                  : 'Choose a server'));
    final subtitle = live
        ? (liveRelay == null
              ? 'Connected · relay details unavailable'
              : 'Connected · ${liveRelay.code.isEmpty ? 'private relay' : liveRelay.code}')
        : (selected != null
              ? 'Selected relay'
              : (probing && ping == null
                    ? 'Measuring from this device'
                    : 'Auto · fastest measured'));
    final liveMs = !live && selected == null ? ping : null;
    return GestureDetector(
      onTap: () => showServerSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: live
                ? AppColors.emerald.withValues(alpha: 0.35)
                : AppColors.hairline,
          ),
        ),
        child: Row(
          children: [
            if (flagCode != null)
              SizedBox(
                width: 30,
                height: 22,
                child: SvgPicture.asset(
                  'assets/flags/$flagCode.svg',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.public,
                    size: 20,
                    color: AppColors.steel,
                  ),
                ),
              )
            else
              const Icon(Icons.public, size: 20, color: AppColors.steel),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.monoValue(
                      size: 11,
                      color: AppColors.mute,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (liveMs != null && liveMs.status == PingStatus.ok)
              Text(
                '${liveMs.ms} ms',
                style: AppTextStyles.monoValue(
                  size: 12,
                  color: AppColors.emerald,
                ),
              )
            else if (probing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.amber,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: live
                      ? AppColors.emerald.withValues(alpha: 0.14)
                      : AppColors.amberTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  live ? 'LIVE' : (selected == null ? 'AUTO' : 'PICKED'),
                  style: AppTextStyles.microLabel(
                    color: live ? AppColors.emerald : AppColors.amber,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.mute),
          ],
        ),
      ),
    );
  }
}
