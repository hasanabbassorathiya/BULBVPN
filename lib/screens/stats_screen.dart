import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/vpn_provider.dart';
import '../screens/history_screen.dart';
import '../widgets/stat_card.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

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
            return SingleChildScrollView(
              padding: EdgeInsets.all(horizontalPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    'Statistics',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: colors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Real-time connection metrics',
                    style: TextStyle(fontSize: 14, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  _buildSpeedSection(vpn, colors),
                  const SizedBox(height: 16),
                  _buildConnectionInfo(vpn, colors),
                  const SizedBox(height: 16),
                  _buildSessionStats(vpn, colors),
                  const SizedBox(height: 16),
                  _buildHistoryPreview(context, vpn, colors),
                  const SizedBox(height: 100),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSpeedSection(VPNProvider vpn, AppSemanticColors colors) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.arrow_downward_rounded,
            label: 'Download',
            value: vpn.isConnected ? vpn.downloadSpeed.toStringAsFixed(1) : '0.0',
            unit: 'Mbps',
            accentColor: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.arrow_upward_rounded,
            label: 'Upload',
            value: vpn.isConnected ? vpn.uploadSpeed.toStringAsFixed(1) : '0.0',
            unit: 'Mbps',
            accentColor: AppColors.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionInfo(VPNProvider vpn, AppSemanticColors colors) {
    final server = vpn.selectedImportedServer;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: vpn.isConnected ? AppColors.connected.withValues(alpha: 0.2) : colors.cardBorder.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: vpn.isConnected ? AppColors.connected.withValues(alpha: 0.15) : colors.cardBorder,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.wifi,
                  color: vpn.isConnected ? AppColors.connected : colors.textMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Connection Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Status', vpn.status.name.toUpperCase(),
              vpn.isConnected ? AppColors.connected : colors.textMuted, colors),
          _buildInfoRow('Server', server != null ? server.name : 'Not selected', colors.textPrimary, colors),
          _buildInfoRow('Address', server != null ? '${server.address}:${server.port}' : '—', colors.textSecondary, colors),
          _buildInfoRow('Protocol', server != null ? server.protocol.name.toUpperCase() : 'V2Ray', colors.textPrimary, colors),
          _buildInfoRow('Download', vpn.isConnected ? '${vpn.downloadSpeed.toStringAsFixed(1)} Mbps' : '—', AppColors.primary, colors),
          _buildInfoRow('Upload', vpn.isConnected ? '${vpn.uploadSpeed.toStringAsFixed(1)} Mbps' : '—', AppColors.secondary, colors),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor, AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: colors.textSecondary)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildSessionStats(VPNProvider vpn, AppSemanticColors colors) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.access_time,
            label: 'Session',
            value: vpn.formattedDuration,
            accentColor: AppColors.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            icon: Icons.data_usage,
            label: 'Data Used',
            value: vpn.dataUsed,
            accentColor: AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryPreview(BuildContext context, VPNProvider vpn, AppSemanticColors colors) {
    final history = vpn.connectionHistory;
    final lastThree = history.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Recent Connections',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.textPrimary),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
                child: Text(
                  'View History',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (lastThree.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No connection records yet',
                  style: TextStyle(fontSize: 13, color: colors.textMuted),
                ),
              ),
            )
          else
            ...lastThree.map((record) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      record.protocol.toUpperCase(),
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.serverName,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${record.formattedDuration} • ${record.timeAgo}',
                          style: TextStyle(fontSize: 11, color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: record.wasSuccessful ? AppColors.connected : AppColors.disconnected,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }
}
