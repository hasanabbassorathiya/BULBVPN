import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../models/imported_server.dart';
import '../services/v2ray_config_parser.dart';
import 'components/app_badge.dart';

class ServerCard extends StatelessWidget {
  final ImportedServer server;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;

  const ServerCard({
    super.key,
    required this.server,
    this.isSelected = false,
    this.isFavorite = false,
    this.onTap,
    this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : colors.card,
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.4)
                : colors.cardBorder.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            _buildProtocolBadge(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${server.address}:${server.port}',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onFavorite,
              child: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFavorite ? AppColors.warning : colors.textMuted,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProtocolBadge() {
    final info = _protocolInfo(server.protocol);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(info.icon, color: info.color, size: 20),
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
}

class _ProtocolInfo {
  final String label;
  final IconData icon;
  final Color color;
  const _ProtocolInfo(this.label, this.icon, this.color);
}
