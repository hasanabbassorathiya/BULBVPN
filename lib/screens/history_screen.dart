import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../models/connection_history.dart';
import '../providers/vpn_provider.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth > 600 ? 40.0 : 20.0;

    return Container(
      decoration: BoxDecoration(gradient: colors.bgGradient),
      child: SafeArea(
        child: Consumer<VPNProvider>(
          builder: (context, vpn, _) {
            final history = vpn.connectionHistory;

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.arrow_back_ios_new, color: colors.textPrimary, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Connection History',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: colors.textPrimary),
                        ),
                      ),
                      if (history.isNotEmpty)
                        GestureDetector(
                          onTap: () => _showClearDialog(context, vpn),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.disconnected.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Clear',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.disconnected),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (history.isNotEmpty) ...[
                  _buildSummaryStats(vpn, colors, horizontalPad),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: history.isEmpty
                      ? _buildEmptyState(colors)
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                          itemCount: history.length,
                          itemBuilder: (context, index) => _buildHistoryCard(history[index], colors),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryStats(VPNProvider vpn, AppSemanticColors colors, double horizontalPad) {
    final history = vpn.connectionHistory;
    final totalConnections = history.length;
    final totalMinutes = history.fold<int>(0, (sum, r) => sum + r.durationSeconds) ~/ 60;
    final totalMB = history.fold<double>(0, (sum, r) => sum + r.dataUsedMB);

    String dataLabel;
    if (totalMB > 1024) {
      dataLabel = '${(totalMB / 1024).toStringAsFixed(1)} GB';
    } else {
      dataLabel = '${totalMB.toStringAsFixed(1)} MB';
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: Row(
        children: [
          _buildMiniStatCard(Icons.replay, '$totalConnections', 'Connections', colors),
          const SizedBox(width: 10),
          _buildMiniStatCard(Icons.access_time, '$totalMinutes', 'Minutes', colors),
          const SizedBox(width: 10),
          _buildMiniStatCard(Icons.data_usage, dataLabel, 'Data', colors),
        ],
      ),
    );
  }

  Widget _buildMiniStatCard(IconData icon, String value, String label, AppSemanticColors colors) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: colors.cardGradient,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppSemanticColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, color: colors.textMuted, size: 64),
          const SizedBox(height: 16),
          Text(
            'No connections yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Your connection history will appear here',
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(ConnectionRecord record, AppSemanticColors colors) {
    final isWireGuard = record.protocol == 'WireGuard';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: record.wasSuccessful
              ? AppColors.connected.withValues(alpha: 0.15)
              : AppColors.disconnected.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Text(record.flag, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.serverName,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isWireGuard
                            ? AppColors.connected.withValues(alpha: 0.12)
                            : AppColors.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        record.protocol,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isWireGuard ? AppColors.connected : AppColors.info,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      record.country,
                      style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      record.formattedDuration,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${record.dataUsedMB.toStringAsFixed(1)} MB',
                      style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  record.timeAgo,
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: record.wasSuccessful ? AppColors.connected : AppColors.disconnected,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, VPNProvider vpn) {
    final colors = AppSemanticColors.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear History', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
          'This will delete all connection records.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              vpn.clearHistory();
              Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: AppColors.disconnected)),
          ),
        ],
      ),
    );
  }
}
