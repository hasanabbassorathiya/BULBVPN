import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../models/in_app_message.dart';
import '../providers/vpn_provider.dart';
import '../services/in_app_message_service.dart';
import '../services/ip_info_service.dart';
import '../utils/app_utils.dart';
import '../widgets/components/server_score_badge.dart';
import '../widgets/promo_banner.dart';
import '../widgets/vpn_toggle.dart';
import 'paywall_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  IPInfo? _ipInfo;
  IPInfo? _vpnIpInfo;
  bool _loadingIp = false;
  VPNStatus? _lastVpnStatus;
  InAppMessage? _activeBannerMessage;

  @override
  void initState() {
    super.initState();
    _fetchCurrentIp();
    _loadBannerMessage();
  }

  Future<void> _loadBannerMessage() async {
    final service = InAppMessageService();
    await service.loadMessages();
    final msg = service.getTopBannerMessage();
    if (msg != null && mounted) {
      await service.recordView(msg.id);
      setState(() => _activeBannerMessage = msg);
    }
  }

  void _dismissBannerMessage() {
    if (_activeBannerMessage != null) {
      InAppMessageService().dismissMessage(_activeBannerMessage!.id);
      setState(() => _activeBannerMessage = null);
    }
  }

  void _handleBannerAction() {
    if (_activeBannerMessage?.actionRoute != null && mounted) {
      final route = _activeBannerMessage!.actionRoute!;
      if (route == 'paywall') {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
      } else {
        Navigator.pushNamed(context, route);
      }
    }
  }

  Future<void> _fetchCurrentIp() async {
    setState(() => _loadingIp = true);
    final info = await IPInfoService.fetchIPInfo();
    if (mounted) {
      setState(() {
        _ipInfo = info;
        _loadingIp = false;
      });
    }
  }

  Future<void> _fetchVpnIp() async {
    setState(() => _loadingIp = true);
    final info = await IPInfoService.fetchIPInfo();
    if (mounted) {
      setState(() {
        _vpnIpInfo = info;
        _loadingIp = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VPNProvider>(
      builder: (context, vpn, _) {
        if (_lastVpnStatus != vpn.status) {
          final prev = _lastVpnStatus;
          _lastVpnStatus = vpn.status;
          if (vpn.isConnected && prev != VPNStatus.connected) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _fetchVpnIp());
          } else if (vpn.isDisconnected && prev == VPNStatus.connected) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fetchCurrentIp();
              _vpnIpInfo = null;
            });
          } else if (vpn.isDisconnected && prev == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCurrentIp());
          }
        }

        final colors = AppSemanticColors.of(context);
        final screenWidth = MediaQuery.of(context).size.width;
        final isDesktop = screenWidth > 900;
        final isTablet = screenWidth >= 600 && screenWidth <= 900;
        final horizontalPad = screenWidth > 600 ? 40.0 : 24.0;

        return Container(
          decoration: BoxDecoration(gradient: colors.bgGradient),
          child: SafeArea(
            child: isDesktop
                ? _buildDesktopLayout(vpn, colors, horizontalPad)
                : isTablet
                    ? _buildTabletLayout(vpn, colors, horizontalPad)
                    : _buildPhoneLayout(vpn, colors, horizontalPad),
          ),
        );
      },
    );
  }

  // ─── Phone Layout (< 600px) ──────────────────────────────────────────────
  Widget _buildPhoneLayout(VPNProvider vpn, AppSemanticColors colors, double horizontalPad) {
    return Column(
      children: [
        _buildHeader(vpn, colors, horizontalPad),
        if (vpn.isKillSwitchActive) _buildKillSwitchBanner(vpn, colors, horizontalPad),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  if (_activeBannerMessage != null)
                    PromoBanner(
                      message: _activeBannerMessage!,
                      onAction: _handleBannerAction,
                      onDismiss: _dismissBannerMessage,
                    ),
                  _buildProtectedBadge(vpn, colors),
                  const SizedBox(height: 20),
                  _buildIpInfoCard(vpn, colors, horizontalPad),
                  const SizedBox(height: 30),
                  _buildServerSelector(context, vpn, colors, horizontalPad),
                  if (vpn.isDisconnected) ...[
                    const SizedBox(height: 20),
                    _buildRecommendedSection(context, vpn, colors),
                  ],
                  if (vpn.isConnected) ...[
                    const SizedBox(height: 20),
                    _buildConnectedInfo(vpn, colors),
                  ],
                  const SizedBox(height: 30),
                  const VPNToggle(),
                  const SizedBox(height: 12),
                  _buildConnectionStage(vpn),
                  const SizedBox(height: 16),
                  _buildQuickConnectButton(vpn, colors),
                  const SizedBox(height: 24),
                  _buildStatusText(vpn),
                  const SizedBox(height: 30),
                  _buildQuickStats(vpn, horizontalPad),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Tablet Layout (600-900px) ───────────────────────────────────────────
  Widget _buildTabletLayout(VPNProvider vpn, AppSemanticColors colors, double horizontalPad) {
    return Column(
      children: [
        _buildHeader(vpn, colors, horizontalPad),
        if (vpn.isKillSwitchActive) _buildKillSwitchBanner(vpn, colors, horizontalPad),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column — VPN controls (40%)
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        if (_activeBannerMessage != null)
                          PromoBanner(
                            message: _activeBannerMessage!,
                            onAction: _handleBannerAction,
                            onDismiss: _dismissBannerMessage,
                          ),
                        _buildProtectedBadge(vpn, colors),
                        const SizedBox(height: 30),
                        _buildServerSelector(context, vpn, colors, 0),
                        if (vpn.isDisconnected) ...[
                          const SizedBox(height: 20),
                          _buildRecommendedSection(context, vpn, colors),
                        ],
                        if (vpn.isConnected) ...[
                          const SizedBox(height: 20),
                          _buildConnectedInfo(vpn, colors),
                        ],
                        const SizedBox(height: 30),
                        const VPNToggle(),
                        const SizedBox(height: 12),
                        _buildConnectionStage(vpn),
                        const SizedBox(height: 16),
                        _buildQuickConnectButton(vpn, colors),
                        const SizedBox(height: 24),
                        _buildStatusText(vpn),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Right column — IP info + stats (60%)
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        _buildIpInfoCard(vpn, colors, 0),
                        const SizedBox(height: 20),
                        _buildQuickStats(vpn, 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Desktop Layout (> 900px) ────────────────────────────────────────────
  Widget _buildDesktopLayout(VPNProvider vpn, AppSemanticColors colors, double horizontalPad) {
    return Column(
      children: [
        _buildHeader(vpn, colors, horizontalPad),
        if (vpn.isKillSwitchActive) _buildKillSwitchBanner(vpn, colors, horizontalPad),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left panel — Server list (25%)
                Expanded(
                  flex: 25,
                  child: _buildServerListSidebar(vpn, colors),
                ),
                const SizedBox(width: 20),
                // Center — Main VPN area (50%)
                Expanded(
                  flex: 50,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        if (_activeBannerMessage != null)
                          PromoBanner(
                            message: _activeBannerMessage!,
                            onAction: _handleBannerAction,
                            onDismiss: _dismissBannerMessage,
                          ),
                        _buildProtectedBadge(vpn, colors),
                        const SizedBox(height: 30),
                        _buildServerSelector(context, vpn, colors, 0),
                        if (vpn.isDisconnected) ...[
                          const SizedBox(height: 20),
                          _buildRecommendedSection(context, vpn, colors),
                        ],
                        if (vpn.isConnected) ...[
                          const SizedBox(height: 20),
                          _buildConnectedInfo(vpn, colors),
                        ],
                        const SizedBox(height: 30),
                        const VPNToggle(),
                        const SizedBox(height: 12),
                        _buildConnectionStage(vpn),
                        const SizedBox(height: 16),
                        _buildQuickConnectButton(vpn, colors),
                        const SizedBox(height: 24),
                        _buildStatusText(vpn),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Right panel — Stats (25%)
                Expanded(
                  flex: 25,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        _buildIpInfoCard(vpn, colors, 0),
                        const SizedBox(height: 20),
                        _buildQuickStats(vpn, 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Desktop Server List Sidebar ─────────────────────────────────────────
  Widget _buildServerListSidebar(VPNProvider vpn, AppSemanticColors colors) {
    final servers = vpn.filteredServers;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Servers',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (servers.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No servers loaded',
                  style: TextStyle(fontSize: 13, color: colors.textMuted),
                ),
              ),
            )
          else
            ...List.generate(servers.length, (index) {
              final server = servers[index];
              final isSelected = vpn.selectedServer?.id == server.id;
              return GestureDetector(
                onTap: vpn.isDisconnected
                    ? () {
                        vpn.selectServer(server);
                        vpn.connect();
                      }
                    : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected
                        ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Text(server.flag, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              server.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              server.country,
                              style: TextStyle(fontSize: 10, color: colors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${server.ping}ms',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: pingColor(server.ping),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ─── Shared Widgets ──────────────────────────────────────────────────────

  Widget _buildConnectionStage(VPNProvider vpn) {
    if (!vpn.isConnecting) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              vpn.vpnStageLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKillSwitchBanner(VPNProvider vpn, AppSemanticColors colors, double horizontalPad) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: horizontalPad > 0 ? horizontalPad : 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.disconnected.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.disconnected.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield, color: AppColors.disconnected, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kill Switch Active',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.disconnected),
                ),
                Text(
                  'Your internet is blocked for protection',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => vpn.disableKillSwitch(),
            child: const Text('Disable', style: TextStyle(color: AppColors.disconnected)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(VPNProvider vpn, AppSemanticColors colors, double horizontalPad) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                'BULB VPN',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: vpn.isConnected
                  ? AppColors.connected.withValues(alpha: 0.15)
                  : colors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: vpn.isConnected
                    ? AppColors.connected.withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: vpn.isConnected ? AppColors.connected : colors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  vpn.protocol,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: vpn.isConnected ? AppColors.connected : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtectedBadge(VPNProvider vpn, AppSemanticColors colors) {
    final isActive = vpn.isConnected;
    final isConnecting = vpn.isConnecting;
    return Semantics(
      label: isActive
          ? 'Protected'
          : isConnecting
              ? 'Connecting'
              : 'Unprotected',
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.connected.withValues(alpha: 0.1)
            : isConnecting
                ? AppColors.warning.withValues(alpha: 0.1)
                : colors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isActive
              ? AppColors.connected.withValues(alpha: 0.3)
              : isConnecting
                  ? AppColors.warning.withValues(alpha: 0.3)
                  : colors.cardBorder.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isConnecting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning),
            )
          else
            Icon(
              isActive ? Icons.lock : Icons.lock_open,
              color: isActive ? AppColors.connected : colors.textMuted,
              size: 16,
            ),
          const SizedBox(width: 8),
          Text(
            isActive ? 'Protected' : isConnecting ? 'Connecting...' : 'Unprotected',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive
                  ? AppColors.connected
                  : isConnecting
                      ? AppColors.warning
                      : colors.textSecondary,
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildIpInfoCard(VPNProvider vpn, AppSemanticColors colors, double horizontalPad) {
    final isVpn = vpn.isConnected;
    final info = isVpn ? _vpnIpInfo : _ipInfo;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: horizontalPad > 0 ? 0 : 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isVpn ? Icons.shield : Icons.language,
                size: 16,
                color: isVpn ? AppColors.connected : colors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                isVpn ? 'VPN IP Address' : 'Your IP Address',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isVpn ? AppColors.connected : colors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (_loadingIp)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (info != null) ...[
            Row(
              children: [
                Text(info.flag, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.ip,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${info.city}, ${info.country}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else if (!_loadingIp) ...[
            GestureDetector(
              onTap: _fetchCurrentIp,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Unable to fetch IP info',
                    style: TextStyle(fontSize: 13, color: colors.textMuted),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.refresh, color: colors.textMuted, size: 16),
                ],
              ),
            ),
          ],
          if (isVpn && _vpnIpInfo != null && _ipInfo != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.connected.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(_ipInfo!.flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Real IP: ${_ipInfo!.ip} (${_ipInfo!.city}, ${_ipInfo!.country})',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServerSelector(BuildContext context, VPNProvider vpn, AppSemanticColors colors, double horizontalPad) {
    final server = vpn.selectedServer;

    return Semantics(
      label: server != null
          ? 'Selected server: ${server.name}, ${server.country}'
          : 'Tap to select a server',
      button: true,
      child: GestureDetector(
      onTap: vpn.isDisconnected ? () => _showServerPicker(context, vpn) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: colors.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
        ),
        child: server != null
            ? Row(
                children: [
                  Text(server.flag, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          server.country,
                          style: TextStyle(fontSize: 12, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${server.ping}ms',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    vpn.isDisconnected ? Icons.chevron_right : Icons.lock,
                    color: colors.textMuted,
                    size: 22,
                  ),
                ],
              )
            : Row(
                children: [
                  Icon(Icons.language, color: colors.textMuted, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tap to select a server',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.textMuted, size: 22),
                ],
              ),
            ),
      ),
    );
  }

  void _showServerPicker(BuildContext context, VPNProvider vpn) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ServerPickerSheet(vpn: vpn),
    );
  }

  Widget _buildStatusText(VPNProvider vpn) {
    String text;
    Color color;
    bool showLoader = false;

    if (vpn.isConnected) {
      text = 'Connected • ${vpn.selectedServer?.name ?? "Unknown"}';
      color = AppColors.connected;
    } else if (vpn.isConnecting) {
      text = 'Connecting...';
      color = AppColors.warning;
      showLoader = true;
    } else if (vpn.status == VPNStatus.disconnecting) {
      text = 'Disconnecting...';
      color = AppColors.warning;
    } else {
      text = 'Disconnected';
      color = AppColors.textMuted;
    }

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (showLoader) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickStats(VPNProvider vpn, double horizontalPad) {
    return Row(
      children: [
        _buildMiniStat(Icons.arrow_upward_rounded, '${vpn.downloadSpeed.toStringAsFixed(1)} Mbps', AppColors.secondary),
        const SizedBox(width: 12),
        _buildMiniStat(Icons.access_time, vpn.formattedDuration, AppColors.accent),
        const SizedBox(width: 12),
        _buildMiniStat(Icons.data_usage, vpn.dataUsed, AppColors.primary),
      ],
    );
  }

  Widget _buildRecommendedSection(BuildContext context, VPNProvider vpn, AppSemanticColors colors) {
    final top = vpn.topRecommended;
    if (top.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'Recommended for you',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: top.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final server = top[index];
              final score = vpn.scoreFor(server);
              return GestureDetector(
                onTap: () {
                  vpn.selectServer(server);
                  vpn.connect();
                },
                child: Container(
                  width: 160,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: colors.cardGradient,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(server.flag, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              server.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Text(
                            '${server.ping}ms',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: pingColor(server.ping),
                            ),
                          ),
                          const Spacer(),
                          ServerScoreBadge(score: score, compact: true),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedInfo(VPNProvider vpn, AppSemanticColors colors) {
    final server = vpn.selectedServer;
    if (server == null) return const SizedBox.shrink();
    final score = vpn.scoreFor(server);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.connected.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.connected.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Text(server.flag, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  '${server.country} • ${server.ping}ms',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          ServerScoreBadge(score: score),
        ],
      ),
    );
  }

  Widget _buildQuickConnectButton(VPNProvider vpn, AppSemanticColors colors) {
    if (vpn.isConnected || vpn.isConnecting) {
      return Semantics(
        label: vpn.isConnecting ? 'Connecting' : 'Disconnect from VPN',
        button: true,
        child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: vpn.isConnecting ? null : () => vpn.disconnect(),
          icon: Icon(vpn.isConnecting ? Icons.hourglass_empty : Icons.stop_rounded, size: 22),
          label: Text(
            vpn.isConnecting ? 'Connecting...' : 'Disconnect',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.disconnected,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
        ),
      ),
      );
    }

    return Semantics(
      label: 'Quick connect to fastest server',
      button: true,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () {
            final server = vpn.selectedServer ?? vpn.bestServer;
            if (server != null) {
              vpn.selectServer(server);
              vpn.connect();
            }
          },
          icon: const Icon(Icons.bolt_rounded, size: 22),
          label: const Text(
            'Quick Connect',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerPickerSheet extends StatelessWidget {
  final VPNProvider vpn;
  const _ServerPickerSheet({required this.vpn});

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textMuted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Select Server',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: colors.textPrimary),
            ),
          ),
          _buildFilterChips(vpn, colors),
          const SizedBox(height: 8),
          Expanded(
            child: Consumer<VPNProvider>(
              builder: (context, vpn, _) {
                final servers = vpn.filteredServers;
                if (servers.isEmpty) {
                  if (vpn.serverFilter == ServerFilter.favorites) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_border, color: colors.textMuted, size: 40),
                            const SizedBox(height: 12),
                            Text(
                              'No favorite servers yet.',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap the star on any server to add it.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: servers.length,
                  itemBuilder: (context, index) {
                    final server = servers[index];
                    final isSelected = vpn.selectedServer?.id == server.id;
                    return _buildServerItem(context, vpn, server, isSelected, colors);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(VPNProvider vpn, AppSemanticColors colors) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: ServerFilter.values.map((filter) {
          final isSelected = vpn.serverFilter == filter;
          final label = filter == ServerFilter.all ? 'All'
              : filter == ServerFilter.favorites ? '★'
              : filter == ServerFilter.asia ? 'Asia'
              : filter == ServerFilter.europe ? 'Europe'
              : filter == ServerFilter.americas ? 'Americas'
              : 'Low Ping';
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => vpn.setServerFilter(filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : colors.card,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? colors.surface : colors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildServerItem(BuildContext context, VPNProvider vpn, VpnServer server, bool isSelected, AppSemanticColors colors) {
    final loadPct = (server.load * 100).round();
    final loadColor = loadPct < 50
        ? AppColors.connected
        : loadPct < 80
            ? AppColors.warning
            : AppColors.disconnected;

    return GestureDetector(
      onTap: () {
        vpn.selectServer(server);
        Navigator.pop(context);
        vpn.connect();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.3) : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(server.flag, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        server.country,
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: pingColor(server.ping).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${server.ping}ms',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: pingColor(server.ping),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => vpn.toggleFavorite(server.id),
                  child: Icon(
                    vpn.isFavorite(server.id) ? Icons.star : Icons.star_border,
                    color: vpn.isFavorite(server.id) ? AppColors.warning : colors.textMuted,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: server.load,
                      minHeight: 3,
                      backgroundColor: colors.cardBorder.withValues(alpha: 0.5),
                      valueColor: AlwaysStoppedAnimation<Color>(loadColor),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$loadPct% load',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
