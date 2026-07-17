import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/vpn_provider.dart';
import '../utils/app_utils.dart';
import 'components/app_bottom_sheet.dart';

class ServerDetailSheet extends StatefulWidget {
  final VpnServer server;

  const ServerDetailSheet({super.key, required this.server});

  static void show(BuildContext context, VpnServer server) {
    AppBottomSheet.show(
      context: context,
      maxHeightFraction: 0.75,
      showCloseButton: false,
      child: ServerDetailSheet(server: server),
    );
  }

  @override
  State<ServerDetailSheet> createState() => _ServerDetailSheetState();
}

class _ServerDetailSheetState extends State<ServerDetailSheet> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    final vpn = context.read<VPNProvider>();
    _isFavorite = vpn.isFavorite(widget.server.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final server = widget.server;
    final loadPct = (server.load * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildHeader(colors, server),
        const SizedBox(height: 16),
        _buildMetricCards(colors, server, loadPct),
        const SizedBox(height: 20),
        _buildInfoSection(colors, server),
        const SizedBox(height: 20),
        _buildConnectButton(),
        const SizedBox(height: 12),
        _buildActionRow(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildHeader(AppSemanticColors colors, VpnServer server) {
    return Row(
      children: [
        Text(server.flag, style: const TextStyle(fontSize: 32)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                server.name,
                style: AppTypography.titleLarge(context).copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                server.country,
                style: AppTypography.bodyMedium(context).copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCards(
    AppSemanticColors colors,
    VpnServer server,
    int loadPct,
  ) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            value: '${server.ping}ms',
            label: 'Latency',
            icon: Icons.speed,
            color: pingColor(server.ping),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            value: '$loadPct%',
            label: 'Load',
            icon: Icons.bar_chart,
            color: _loadColor(loadPct),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            value: 'OpenVPN',
            label: 'Protocol',
            icon: Icons.lock_outline,
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(AppSemanticColors colors, VpnServer server) {
    final items = [
      _InfoItem(label: 'Region', value: _regionFor(server)),
      _InfoItem(label: 'City', value: server.name),
      _InfoItem(label: 'Uptime', value: '99.9%'),
      _InfoItem(label: 'Speed', value: '1 Gbps'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Server Information',
          style: AppTypography.labelLarge(context).copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        ...items.map((item) => _buildInfoRow(colors, item)),
      ],
    );
  }

  Widget _buildInfoRow(AppSemanticColors colors, _InfoItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            item.label,
            style: AppTypography.bodyMedium(context).copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.value,
              style: AppTypography.bodyLarge(context).copyWith(
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectButton() {
    final server = widget.server;
    return Consumer<VPNProvider>(
      builder: (context, vpn, _) {
        final isCurrentServer = vpn.selectedServer?.id == server.id;
        final isConnected = vpn.isConnected && isCurrentServer;

        return SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () async {
              vpn.selectServer(server);
              if (!isConnected) {
                Navigator.of(context).pop();
                await vpn.connect();
              } else {
                Navigator.of(context).pop();
                await vpn.disconnect();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: isConnected
                    ? null
                    : const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                      ),
                color: isConnected ? AppColors.disconnected : null,
                borderRadius: AppRadius.lgAll,
              ),
              child: Center(
                child: Text(
                  isConnected ? 'Disconnect from ${server.name}' : 'Connect to ${server.name}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Quick Connect',
            icon: Icons.flash_on_outlined,
            onTap: () async {
              final vpn = context.read<VPNProvider>();
              final best = vpn.bestServer;
              if (best != null) {
                vpn.selectServer(best);
                Navigator.of(context).pop();
                await vpn.connect();
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Consumer<VPNProvider>(
            builder: (context, vpn, _) {
              final fav = vpn.isFavorite(widget.server.id);
              return _ActionButton(
                label: fav ? 'Remove Favorite' : 'Add to Favorites',
                icon: fav ? Icons.star_rounded : Icons.star_outline_rounded,
                isHighlighted: fav,
                onTap: () {
                  setState(() => _isFavorite = !_isFavorite);
                  vpn.toggleFavorite(widget.server.id);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _regionFor(VpnServer server) {
    const regions = {
      'US': 'North America',
      'CA': 'North America',
      'GB': 'Europe',
      'DE': 'Europe',
      'FR': 'Europe',
      'NL': 'Europe',
      'JP': 'Asia',
      'SG': 'Asia',
      'KR': 'Asia',
      'IN': 'Asia',
      'BR': 'South America',
      'AU': 'Oceania',
    };
    return regions[server.countryCode] ?? 'Other';
  }

  Color _loadColor(int loadPct) {
    if (loadPct < 50) return AppColors.connected;
    if (loadPct < 80) return AppColors.warning;
    return AppColors.disconnected;
  }
}

class _MetricCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.titleMedium(context).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.labelSmall(context).copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoItem {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isHighlighted;

  const _ActionButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isHighlighted
              ? AppColors.warning.withValues(alpha: 0.1)
              : colors.card,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: isHighlighted
                ? AppColors.warning.withValues(alpha: 0.3)
                : colors.cardBorder.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isHighlighted ? AppColors.warning : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppTypography.labelMedium(context).copyWith(
                  color: isHighlighted ? AppColors.warning : colors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
