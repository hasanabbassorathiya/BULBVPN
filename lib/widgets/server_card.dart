import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../providers/vpn_provider.dart';
import '../utils/app_utils.dart';
import 'components/app_badge.dart';

class ServerCard extends StatelessWidget {
  final VpnServer server;
  final bool isSelected;
  final bool isFavorite;
  final bool isRecommended;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;
  final VoidCallback? onLongPress;

  const ServerCard({
    super.key,
    required this.server,
    this.isSelected = false,
    this.isFavorite = false,
    this.isRecommended = false,
    this.onTap,
    this.onFavorite,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final loadPct = (server.load * 100).round();
    final loadColor = _loadBarColor(loadPct);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopRow(colors),
            const SizedBox(height: 10),
            _buildLoadBar(colors, loadPct, loadColor),
            if (_hasBadges) ...[
              const SizedBox(height: 10),
              _buildBadges(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopRow(AppSemanticColors colors) {
    return Row(
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
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                server.country,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ),
        ),
        _buildPingBadge(),
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
    );
  }

  Widget _buildPingBadge() {
    final color = pingColor(server.ping);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        '${server.ping}ms',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildLoadBar(AppSemanticColors colors, int loadPct, Color loadColor) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: server.load),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: colors.cardBorder.withValues(alpha: 0.5),
                  valueColor: AlwaysStoppedAnimation<Color>(loadColor),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$loadPct%',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildBadges() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (server.ping < 50)
          const AppBadge(
            label: 'Gaming',
            color: AppColors.secondary,
            size: AppBadgeSize.small,
          ),
        if (isRecommended)
          const AppBadge(
            label: 'Recommended',
            color: AppColors.connected,
            icon: Icons.thumb_up_alt_outlined,
            size: AppBadgeSize.small,
          ),
        if (server.isPremium)
          const AppBadge(
            label: 'Streaming',
            color: AppColors.info,
            icon: Icons.play_circle_outline,
            size: AppBadgeSize.small,
          ),
      ],
    );
  }

  bool get _hasBadges => server.ping < 50 || isRecommended || server.isPremium;

  Color _loadBarColor(int loadPct) {
    if (loadPct < 50) return AppColors.connected;
    if (loadPct < 80) return AppColors.warning;
    return AppColors.disconnected;
  }
}
