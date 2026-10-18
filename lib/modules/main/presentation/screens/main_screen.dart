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
import 'package:bulbvpn/modules/core/server_catalog.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/modules/core/vpn_controller.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/core/vpn_service.dart';
import 'package:bulbvpn/modules/core/vpn_session_store.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/bulb_orb.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
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

class _MainScreenState extends ConsumerState<MainScreen> with WidgetsBindingObserver {
  VpnController? _vpnController;
  bool _vpnInitialized = false;
  Timer? _ticker;

  DateTime? _connectedAt;
  int? _prevByteIn;
  String _sessionLabel = '00:00:00';
  String _rateLabel = '—';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    log.addLog('[MainScreen] initState');
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    Future.microtask(_warmServers);
  }

  Future<void> _warmServers() async {
    final servers = await ref.read(serversProvider.future).catchError((_) => <VpnServer>[]);
    if (!mounted || servers.isEmpty) return;
    await ref.read(serverPingProvider.notifier).pingAll(servers);
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
    final tunnel = await SoftEtherVpn.status();
    final engine = await VpnService().getStatus();
    final live = tunnel.running || engine == vpn_status.ConnectionStatus.connected;
    if (!live) return;
    final session = await VpnSessionStore.read();
    if (!mounted) return;
    final notifier = ref.read(connectionStateProvider.notifier);
    notifier.adoptLiveTunnel(holdEngine: tunnel.running);
    final label = session?.label.isNotEmpty == true
        ? session!.label
        : (tunnel.host.isNotEmpty ? tunnel.host : null);
    if (label != null) {
      ref.read(softEtherHostProvider.notifier).state = label;
    }
    if (session != null) {
      _connectedAt = DateTime.fromMillisecondsSinceEpoch(session.startedMs);
      _updateSession();
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
    final parts = [info.city, info.region, info.country].where((s) => s.trim().isNotEmpty);
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
          ],
        ),
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
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
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
                        Text('${lines.length}', style: AppTextStyles.microLabel()),
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
                          icon: const Icon(Icons.close, color: AppColors.steel, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: lines.isEmpty
                        ? const Center(
                            child: Text(
                              'No logs yet — tap the bulb to connect.',
                              style: TextStyle(color: AppColors.mute, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                            itemCount: lines.length,
                            itemBuilder: (_, i) {
                              final line = redactRelayDetail(lines[i]);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  line,
                                  style: AppTextStyles.logLine(color: _logColor(line)),
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

  String _stageLabel(vpn_status.ConnectionStatus? engine, ConnectionStatus status) {
    if (status == ConnectionStatus.connected) return 'secure tunnel';
    if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error ||
        status == ConnectionStatus.noInternet) {
      return status == ConnectionStatus.disconnected ? 'idle' : 'tunnel closed';
    }
    switch (engine) {
      case vpn_status.ConnectionStatus.connected:
        return 'secure tunnel';
      case vpn_status.ConnectionStatus.connecting:
        return 'opening tunnel';
      case vpn_status.ConnectionStatus.disconnecting:
        return 'closing tunnel';
      case vpn_status.ConnectionStatus.disconnected:
      case vpn_status.ConnectionStatus.unknown:
      case null:
        // Fall through to app-level states while the engine settles.
        return switch (status) {
          ConnectionStatus.connecting => 'opening tunnel',
          ConnectionStatus.analyzing => 'testing tunnel',
          ConnectionStatus.disconnecting => 'closing tunnel',
          _ => 'connecting',
        };
    }
  }

  String _orbLabel(ConnectionStatus status, vpn_status.ConnectionStatus? engine) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Tap to disconnect';
      case ConnectionStatus.loading:
      case ConnectionStatus.connecting:
      case ConnectionStatus.analyzing:
        return _stageLabel(engine, status);
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
    final catalog = ref.watch(serversProvider).valueOrNull ?? const <VpnServer>[];
    final fastest = _fastestServer(catalog, pingState.byIp);
    final exitIp = ref.watch(exitIpProvider);
    final beforeIp = ref.watch(ipWhoProvider.select((state) => state.before?.ip));
    final visibleExit =
        exitIp != null && exitIp.ip.isNotEmpty && exitIp.ip != beforeIp
            ? exitIp
            : null;
    final ipWho = ref.watch(ipWhoProvider);
    final sslHost = ref.watch(softEtherHostProvider);
    final status = cs.status;
    final afterInfo = ipWho.after;
    final afterMatches =
        visibleExit != null && afterInfo != null && afterInfo.ip == visibleExit.ip;
    final endpointLabel = sslHost != null
        ? publicRelayLabel(sslHost, catalog)
        : (selected?.publicLabel ??
            fastest?.publicLabel ??
            'finding fastest');

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
                  final bounded = constraints.hasBoundedHeight &&
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
                          '${_stageLabel(cs.vpnStatus, status)} · $endpointLabel',
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
                        label: _orbLabel(status, cs.vpnStatus),
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
                          label: _orbLabel(status, cs.vpnStatus),
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
                                        style: AppTextStyles.metric(size: 20),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(width: 1, color: AppColors.hairline),
                                Expanded(
                                  flex: 10,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 16),
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
                                                overflow: TextOverflow.ellipsis,
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
                            label: visibleExit == null ? 'EXIT IP' : 'AFTER',
                            ip: visibleExit?.ip,
                            location: afterMatches
                                ? _ipLocationLabel(afterInfo)
                                : (visibleExit?.loc ?? ''),
                            copyable: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---- Server pill ------------------------------------
                  StaggeredIn(
                    delayMs: 200,
                    child: _serverPill(
                      selected,
                      catalog: catalog,
                      sslHost: sslHost,
                      fastest: fastest,
                      ping: fastest == null ? null : pingState.byIp[fastest.ip],
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
        Builder(builder: (context) {
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
        }),
        const SizedBox(height: 20),
        StaggeredIn(
          delayMs: 100,
          offset: 8,
          child: Text(
            label,
            style: AppTextStyles.microLabel(
              color: phase == BulbPhase.idle
                  ? AppColors.steel
                  : AppColors.ink,
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

  VpnServer? _fastestServer(List<VpnServer> servers, Map<String, ServerPing> byIp) {
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
    String? sslHost,
    VpnServer? fastest,
    ServerPing? ping,
    bool probing = false,
  }) {
    final shown = selected ?? fastest;
    final flagCode = shown == null
        ? null
        : (shown.countryShort.toLowerCase().length == 2
              ? shown.countryShort.toLowerCase()
              : 'xx');
    final title = sslHost != null
        ? publicRelayLabel(sslHost, catalog)
        : (selected?.publicLabel ?? shown?.publicLabel ?? 'Finding a server');
    final subtitle = sslHost != null
        ? 'Private tunnel'
        : (selected != null
            ? 'Selected'
            : (probing && ping == null
                ? 'Measuring from this device'
                : 'Fastest'));
    final liveMs = sslHost == null && selected == null ? ping : null;
    return GestureDetector(
      onTap: () => showServerSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
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
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.amberTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  selected == null ? 'FASTEST' : 'PICKED',
                  style: AppTextStyles.microLabel(color: AppColors.amber),
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
