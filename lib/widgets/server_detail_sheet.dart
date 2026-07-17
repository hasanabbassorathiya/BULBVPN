import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../models/imported_server.dart';
import '../providers/vpn_provider.dart';
import '../services/v2ray_config_parser.dart';
import 'components/app_bottom_sheet.dart';

class ServerDetailSheet extends StatefulWidget {
  final ImportedServer server;

  const ServerDetailSheet({super.key, required this.server});

  static void show(BuildContext context, ImportedServer server) {
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
    _isFavorite = vpn.isFavoriteServer(widget.server.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final server = widget.server;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildHeader(colors, server),
        const SizedBox(height: 16),
        _buildProtocolCards(colors, server),
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

  Widget _buildHeader(AppSemanticColors colors, ImportedServer server) {
    final info = _protocolInfo(server.protocol);
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: info.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(info.icon, color: info.color, size: 24),
        ),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${server.address}:${server.port}',
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

  Widget _buildProtocolCards(AppSemanticColors colors, ImportedServer server) {
    final info = _protocolInfo(server.protocol);
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            value: info.label,
            label: 'Protocol',
            icon: info.icon,
            color: info.color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            value: '${server.port}',
            label: 'Port',
            icon: Icons.numbers,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            value: server.configJson.length > 8 ? 'Yes' : 'No',
            label: 'Configured',
            icon: Icons.check_circle_outline,
            color: AppColors.connected,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(AppSemanticColors colors, ImportedServer server) {
    final items = [
      _InfoItem(label: 'Protocol', value: _protocolInfo(server.protocol).label),
      _InfoItem(label: 'Address', value: server.address),
      _InfoItem(label: 'Port', value: '${server.port}'),
      _InfoItem(label: 'Imported', value: _formatDate(server.importedAt)),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
        final isCurrentServer = vpn.selectedImportedServer?.id == server.id;
        final isConnected = vpn.isConnected && isCurrentServer;

        return SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () async {
              vpn.selectImportedServer(server);
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
                vpn.selectImportedServer(best);
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
              final fav = vpn.isFavoriteServer(widget.server.id);
              return _ActionButton(
                label: fav ? 'Remove Favorite' : 'Add to Favorites',
                icon: fav ? Icons.star_rounded : Icons.star_outline_rounded,
                isHighlighted: fav,
                onTap: () {
                  setState(() => _isFavorite = !_isFavorite);
                  vpn.toggleFavoriteServer(widget.server.id);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  _ProtocolInfo _protocolInfo(V2RayProtocol protocol) {
    switch (protocol) {
      case V2RayProtocol.vmess:
        return _ProtocolInfo('VMess', Icons.lock_outline, AppColors.primary);
      case V2RayProtocol.vless:
        return _ProtocolInfo('VLESS', Icons.flash_on, AppColors.connected);
      case V2RayProtocol.trojan:
        return _ProtocolInfo('Trojan', Icons.shield_outlined, AppColors.info);
      case V2RayProtocol.shadowsocks:
        return _ProtocolInfo('SS', Icons.speed, AppColors.secondary);
      case V2RayProtocol.unknown:
        return _ProtocolInfo('Unknown', Icons.help_outline, AppColors.textMuted);
      default:
        return _ProtocolInfo('Unknown', Icons.help_outline, AppColors.textMuted);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _ProtocolInfo {
  final String label;
  final IconData icon;
  final Color color;
  const _ProtocolInfo(this.label, this.icon, this.color);
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
