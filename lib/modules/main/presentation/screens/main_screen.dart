import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_dart/vpn_status.dart' as vpn_status;
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/modules/core/vpngate_source.dart';
import 'package:bulbvpn/modules/core/vpn_controller.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/bulb_orb.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
import 'package:bulbvpn/shared/layout/main_screen_background.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:bulbvpn/shared/providers/ip_info_provider.dart';
import 'package:bulbvpn/shared/providers/exit_ip_provider.dart';
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
  String _sanitizeB64(String b) {
    var s = b.trim().replaceAll('\n','').replaceAll('\r','').replaceAll(' ','');
    final mod = s.length % 4;
    if (mod != 0) s += '=' * (4-mod);
    return s;
  }
  VpnServer? _serverFromCsvLine(String line) {
    final l = line.trim();
    if (l.isEmpty || l.startsWith('*') || l.startsWith('#')) return null;
    final parts = l.split(',');
    if (parts.length < 15) return null;
    final b64 = parts.last.trim();
    if (b64.isEmpty) return null;
    // validate decodable
    try { final _ = base64.decode(_sanitizeB64(b64)); } catch (_) { return null; }
    return VpnServer(
      hostName: parts[0].trim(),
      ip: parts[1].trim(),
      countryLong: parts[5].trim(),
      countryShort: parts[6].trim(),
      score: int.tryParse(parts[2].trim()) ?? 0,
      ping: int.tryParse(parts[3].trim()) ?? 0,
      speed: int.tryParse(parts[4].trim()) ?? 0,
      numVpnSessions: int.tryParse(parts[7].trim()) ?? 0,
      uptime: int.tryParse(parts[8].trim()) ?? 0,
      openVpnConfigBase64: b64,
    );
  }
  Future<List<VpnServer>?> _fetchPublishedList() async {
    for (final url in vpnGatePublishedLists) {
      try {
        log.addLog('[MainScreen] Fetching published VPN Gate list: $url');
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200 || response.body.isEmpty) continue;
        final decoded = json.decode(response.body);
        if (decoded is! List) continue;
        final servers = decoded
            .whereType<Map>()
            .map((row) => VpnServer.fromJson(Map<String, dynamic>.from(row)))
            .where((server) => server.ip.isNotEmpty && server.hostName.isNotEmpty)
            .toList();
        if (servers.isEmpty) continue;
        log.addLog('[MainScreen] Parsed ${servers.length} servers from published list');
        return servers;
      } catch (e) {
        log.addLog('[MainScreen] Published list failed: $e');
      }
    }
    return null;
  }
  Future<List<VpnServer>?> _fetchOfficialCsv() async {
    const url = 'http://www.vpngate.net/api/iphone/';
    log.addLog('[MainScreen] Fetching servers from official CSV: $url');
    for (var attempt=1; attempt<=2; attempt++) {
      try {
        final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
        log.addLog('[MainScreen] Official CSV status: ${resp.statusCode}, bytes: ${resp.bodyBytes.length}');
        if (resp.statusCode != 200 || !resp.body.contains('OpenVPN_ConfigData_Base64')) continue;
        final lines = resp.body.split('\n');
        final servers = <VpnServer>[];
        for (final line in lines) {
          final s = _serverFromCsvLine(line);
          if (s != null) servers.add(s);
        }
        if (servers.isEmpty) { log.addLog('[MainScreen] Official CSV: no valid configs (attempt $attempt)'); continue; }
        servers.sort((a,b){ final pa=a.ping<=0?9999:a.ping; final pb=b.ping<=0?9999:b.ping; return pa.compareTo(pb); });
        log.addLog('[MainScreen] Parsed ${servers.length} servers from official CSV (sorted by ping asc)');
        return servers;
      } catch (e) { log.addLog('[MainScreen] Official CSV error attempt $attempt: $e'); }
    }
    return null;
  }
  Future<List<VpnServer>> _fetchJsonMirror() async {
    const url = 'https://raw.githubusercontent.com/alihusains/apigate/main/response.json';
    log.addLog('[MainScreen] Fallback JSON mirror: $url');
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
    log.addLog('[MainScreen] Mirror status: ${response.statusCode}, bytes: ${response.bodyBytes.length}');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      var servers = data.map((json) => VpnServer.fromJson(json)).toList();
      servers = servers.where((s) => s.openVpnConfigBase64.isNotEmpty).toList();
      servers.sort((a, b) { final pa=a.ping<=0?9999:a.ping; final pb=b.ping<=0?9999:b.ping; return pa.compareTo(pb); });
      log.addLog('[MainScreen] Parsed ${servers.length} servers from mirror (sorted by ping asc)');
      return servers;
    }
    throw Exception('Failed to load servers: ${response.statusCode}');
  }
  final published = await _fetchPublishedList();
  if (published != null) {
    return published;
  }
  List<VpnServer> servers;
  final official = await _fetchOfficialCsv();
  if (official != null) {
    servers = official;
  } else {
    log.addLog('[MainScreen] Official CSV failed, using JSON mirror');
    servers = await _fetchJsonMirror();
  }
  // Do not pin servers.first into the controller. CSV ping is measured by
  // VPN Gate, not from this device, and locking connect to that one host
  // skips candidate rotation when the endpoint is dead or DPI-stalled.
  return servers;
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
    Future.microtask(
      () => ref.read(serversProvider.future).catchError((_) => <VpnServer>[]),
    );
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
      ctrl.selectServerConfig(
        config,
        '${server.countryLong} · ${server.ip}',
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
                              final line = lines[i];
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
    final exitIp = ref.watch(exitIpProvider);
    final ipWho = ref.watch(ipWhoProvider);
    final sslHost = ref.watch(softEtherHostProvider);
    final status = cs.status;
    final afterInfo = ipWho.after;
    final afterMatches =
        exitIp != null && afterInfo != null && afterInfo.ip == exitIp.ip;
    final endpointLabel = selected != null
        ? '${selected.countryLong} · ${selected.ip}'
        : (sslHost ?? 'auto');

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
        _vpnController?.reconnect(ref);
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
                  final tight = constraints.maxHeight < 740;
                  return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- Top bar: brand + logs -------------------------
                  StaggeredIn(
                    child: Row(
                      children: [
                        Flexible(child: _brandWordmark()),
                        const Spacer(),
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
                  Expanded(
                    child: Align(
                      alignment: const Alignment(0, -0.18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Builder(builder: (context) {
                            final total = ref.watch(connectionStateProvider.select((s) => s.totalDownload));
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
                              _orbLabel(status, cs.vpnStatus),
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
                            label: exitIp == null ? 'EXIT IP' : 'AFTER',
                            ip: exitIp?.ip,
                            location: afterMatches
                                ? _ipLocationLabel(afterInfo)
                                : (exitIp?.loc ?? ''),
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
                    child: _serverPill(selected, sslHost: sslHost),
                  ),

                  // ---- Nav clearance ----------------------------------
                  SizedBox(height: tight ? 72 : 96),
                ],
              );
                },
              ),
            ),
          ),
        ),
      ),
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

  Widget _serverPill(VpnServer? selected, {String? sslHost}) {
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
                    sslHost != null
                        ? 'SoftEther SSL'
                        : (selected?.countryLong ?? 'Auto select'),
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
                    sslHost ?? selected?.ip ?? 'fastest available',
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
            if (selected != null && selected.ping > 0)
              Text(
                '${selected.ping} ms',
                style: AppTextStyles.monoValue(
                  size: 12,
                  color: AppColors.steel,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.amberTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'AUTO',
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
