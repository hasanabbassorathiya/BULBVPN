import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/vpn_controller.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/bulb_orb.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
import 'package:bulbvpn/shared/layout/main_screen_background.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:bulbvpn/shared/widgets/staggered_in.dart';

final log = Log();

class VpnServer {
  final String hostName;
  final String ip;
  final String countryLong;
  final String countryShort;
  final int score;
  final int ping;
  final int speed;
  final int numVpnSessions;
  final int uptime;
  final String openVpnConfigBase64;

  VpnServer({
    required this.hostName,
    required this.ip,
    required this.countryLong,
    required this.countryShort,
    required this.score,
    required this.ping,
    required this.speed,
    required this.numVpnSessions,
    required this.uptime,
    required this.openVpnConfigBase64,
  });

  factory VpnServer.fromJson(Map<String, dynamic> json) {
    return VpnServer(
      hostName: json['#HostName'] ?? '',
      ip: json['IP'] ?? '',
      countryLong: json['CountryLong'] ?? '',
      countryShort: json['CountryShort'] ?? '',
      score: int.tryParse(json['Score'] ?? '0') ?? 0,
      ping: int.tryParse(json['Ping'] ?? '0') ?? 0,
      speed: int.tryParse(json['Speed'] ?? '0') ?? 0,
      numVpnSessions: int.tryParse(json['NumVpnSessions'] ?? '0') ?? 0,
      uptime: int.tryParse(json['Uptime'] ?? '0') ?? 0,
      openVpnConfigBase64: json['OpenVPN_ConfigData_Base64'] ?? '',
    );
  }

  String get speedMbps => (speed / 1024 / 1024).toStringAsFixed(1);
}

final serversProvider = FutureProvider<List<VpnServer>>((ref) async {
  const url = 'https://raw.githubusercontent.com/alihusains/apigate/main/response.json';
  log.addLog('[MainScreen] Fetching servers from: $url');
  final response = await http.get(Uri.parse(url));
  log.addLog('[MainScreen] Response status: ${response.statusCode}, bytes: ${response.bodyBytes.length}');
  if (response.statusCode == 200) {
    final List<dynamic> data = json.decode(response.body);
    final servers = data.map((json) => VpnServer.fromJson(json)).toList();
    log.addLog('[MainScreen] Parsed ${servers.length} servers');
    return servers;
  }
  log.addLog('[MainScreen] ERROR: Failed to load servers - status ${response.statusCode}');
  throw Exception('Failed to load servers: ${response.statusCode}');
});

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
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
    log.addLog('[MainScreen] initState');
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Warm the server list so the sheet opens instantly.
    Future.microtask(() => ref.read(serversProvider.future).catchError((_) => <VpnServer>[]));
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
  void dispose() {
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
      // Apply a server picked before the controller was ready.
      final picked = ref.read(selectedServerProvider);
      if (picked != null) _applyServerConfig(picked);
    } catch (e, stackTrace) {
      log.addLog('[MainScreen] VPN Controller init error: $e');
      log.addLog('[MainScreen] Stack trace: $stackTrace');
    }
  }

  void _applyServerConfig(VpnServer server) {
    final ctrl = _vpnController;
    if (ctrl == null) return;
    try {
      final config = utf8.decode(base64.decode(server.openVpnConfigBase64));
      ctrl.selectServerConfig(config, '${server.countryLong} · ${server.ip}');
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
      final session =
          formatDuration(DateTime.now().difference(_connectedAt!));
      final byteIn = int.tryParse(cs.vpnStatus?.byteIn ?? '') ?? 0;
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
      await _vpnController!.handleConnectionButton(ref);
    } catch (e, stackTrace) {
      log.addLog('[MainScreen] ERROR in handleConnectionButton: $e');
      log.addLog('[MainScreen] Stack trace: $stackTrace');
    }
  }

  void _showLogs() {
    final lines = Log().recent(200);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
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
                    onPressed: () {
                      Log().clearLogs();
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                itemCount: lines.length,
                itemBuilder: (_, i) {
                  final line = lines[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(line, style: AppTextStyles.logLine(color: _logColor(line))),
                  );
                },
              ),
            ),
          ],
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

  String _stageLabel(VPNStage? stage, ConnectionStatus status) {
    if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error ||
        status == ConnectionStatus.noInternet) {
      return status == ConnectionStatus.disconnected ? 'idle' : 'tunnel closed';
    }
    switch (stage) {
      case VPNStage.connected:
        return 'secure tunnel';
      case VPNStage.tcp_connect:
      case VPNStage.udp_connect:
        return 'opening tunnel';
      case VPNStage.wait_connection:
        return 'waiting for tunnel';
      case VPNStage.authenticating:
      case VPNStage.authentication:
        return 'authenticating';
      case VPNStage.vpn_generate_config:
        return 'generating config';
      case VPNStage.get_config:
        return 'loading config';
      case VPNStage.assign_ip:
        return 'assigning ip';
      case VPNStage.resolve:
        return 'resolving host';
      case VPNStage.prepare:
        return 'preparing';
      case VPNStage.connecting:
        return 'connecting';
      case VPNStage.disconnecting:
      case VPNStage.exiting:
        return 'closing tunnel';
      case VPNStage.denied:
      case VPNStage.error:
        return 'rejected';
      case VPNStage.disconnected:
      case VPNStage.unknown:
      case null:
        return 'idle';
    }
  }

  String _orbLabel(ConnectionStatus status, VPNStage? stage) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Tap to disconnect';
      case ConnectionStatus.loading:
      case ConnectionStatus.connecting:
      case ConnectionStatus.analyzing:
        return _stageLabel(stage, status);
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
    final status = cs.status;

    // Push server picks into the controller.
    ref.listen(selectedServerProvider, (prev, next) {
      if (next == null) {
        _vpnController?.clearServerConfig();
      } else {
        _applyServerConfig(next);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- Top bar: brand + logs -------------------------
                  StaggeredIn(
                    child: Row(
                      children: [
                        _brandWordmark(),
                        const Spacer(),
                        IconButton(
                          onPressed: _showLogs,
                          tooltip: 'Logs',
                          icon: const Icon(Icons.terminal,
                              color: AppColors.steel, size: 22),
                          constraints: const BoxConstraints(
                              minWidth: 44, minHeight: 44),
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
                          '${_stageLabel(cs.vpnStage, status)} · ${selected?.ip ?? 'auto'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.monoValue(
                              size: 11, color: AppColors.steel),
                        ),
                      ],
                    ),
                  ),

                  // ---- Orb zone (optical center) ---------------------
                  Expanded(
                    child: Align(
                      alignment: const Alignment(0, -0.18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BulbOrb(
                            phase: phase,
                            onTap: _onConnectPressed,
                            size: 210,
                          ),
                          const SizedBox(height: 20),
                          StaggeredIn(
                            delayMs: 100,
                            offset: 8,
                            child: Text(
                              _orbLabel(status, cs.vpnStage),
                              style: AppTextStyles.microLabel(
                                color: phase == BulbPhase.idle
                                    ? AppColors.steel
                                    : AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ---- Metric rail: SESSION + DOWN (1.6fr / 1fr) ------
                  StaggeredIn(
                    delayMs: 140,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 16,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('SESSION',
                                      style: AppTextStyles.microLabel()),
                                  const SizedBox(height: 6),
                                  Text(_sessionLabel,
                                      style: AppTextStyles.metric(size: 20)),
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
                                padding: const EdgeInsets.only(left: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('DOWN',
                                        style: AppTextStyles.microLabel()),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.arrow_downward,
                                            size: 14,
                                            color: AppColors.emerald),
                                        const SizedBox(width: 5),
                                        Text(
                                          _rateLabel,
                                          style: AppTextStyles.metric(
                                              size: 20,
                                              color: AppColors.emerald),
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
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---- Server pill ------------------------------------
                  StaggeredIn(
                    delayMs: 200,
                    child: _serverPill(selected),
                  ),

                  // ---- Nav clearance ----------------------------------
                  const SizedBox(height: 96),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandWordmark() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
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
        Transform.translate(
          offset: const Offset(0, -1),
          child: Text('SECURE TUNNEL', style: AppTextStyles.microLabel()),
        ),
      ],
    );
  }

  Widget _serverPill(VpnServer? selected) {
    final flagCode = selected == null
        ? null
        : (selected.countryShort.toLowerCase().length == 2
            ? selected.countryShort.toLowerCase()
            : 'xx');
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
                  errorBuilder: (_, __, ___) => const Icon(Icons.public,
                      size: 20, color: AppColors.steel),
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
                    selected?.countryLong ?? 'Auto select',
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
                    selected?.ip ?? 'fastest available',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.monoValue(
                        size: 11, color: AppColors.mute),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (selected != null && selected.ping > 0)
              Text(
                '${selected.ping} ms',
                style: AppTextStyles.monoValue(
                    size: 12, color: AppColors.steel),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.amberTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('AUTO',
                    style: AppTextStyles.microLabel(color: AppColors.amber)),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.mute),
          ],
        ),
      ),
    );
  }
}
