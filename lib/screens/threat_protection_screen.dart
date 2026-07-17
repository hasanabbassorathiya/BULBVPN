import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class ThreatProtectionScreen extends StatefulWidget {
  const ThreatProtectionScreen({super.key});

  @override
  State<ThreatProtectionScreen> createState() => _ThreatProtectionScreenState();
}

class _ThreatProtectionScreenState extends State<ThreatProtectionScreen> {
  bool _blockAds = true;
  bool _blockTrackers = true;
  bool _blockMalware = false;

  final int _adsBlocked = 1247;
  final int _trackersBlocked = 892;

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);

    return Container(
      decoration: BoxDecoration(gradient: colors.bgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Threat Protection', style: TextStyle(color: colors.textPrimary)),
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, color: colors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.connected.withValues(alpha: 0.15), AppColors.primary.withValues(alpha: 0.05)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.connected.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Icon(
                      _blockAds || _blockTrackers || _blockMalware
                          ? Icons.shield
                          : Icons.shield_outlined,
                      color: _blockAds || _blockTrackers || _blockMalware
                          ? AppColors.connected
                          : colors.textMuted,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _blockAds || _blockTrackers || _blockMalware
                          ? 'Protection Active'
                          : 'Protection Disabled',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _blockAds || _blockTrackers || _blockMalware
                            ? AppColors.connected
                            : colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStat('Ads Blocked', _adsBlocked, colors),
                        const SizedBox(width: 24),
                        _buildStat('Trackers Blocked', _trackersBlocked, colors),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'PROTECTION SETTINGS',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: colors.textMuted, letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  gradient: colors.cardGradient,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    _buildProtectionTile(
                      icon: Icons.block,
                      title: 'Block Ads',
                      subtitle: 'Remove ads from websites and apps',
                      value: _blockAds,
                      onChanged: (val) => setState(() => _blockAds = val),
                      color: AppColors.warning,
                      isLast: false,
                      colors: colors,
                    ),
                    _buildProtectionTile(
                      icon: Icons.visibility_off,
                      title: 'Block Trackers',
                      subtitle: 'Prevent tracking of your activity',
                      value: _blockTrackers,
                      onChanged: (val) => setState(() => _blockTrackers = val),
                      color: AppColors.accent,
                      isLast: false,
                      colors: colors,
                    ),
                    _buildProtectionTile(
                      icon: Icons.bug_report,
                      title: 'Block Malware',
                      subtitle: 'Protect against malicious websites',
                      value: _blockMalware,
                      onChanged: (val) => setState(() => _blockMalware = val),
                      color: AppColors.disconnected,
                      isLast: true,
                      colors: colors,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, int count, AppSemanticColors colors) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.connected),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: colors.textSecondary)),
      ],
    );
  }

  Widget _buildProtectionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color color,
    required bool isLast,
    required AppSemanticColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: isLast ? null : BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.cardBorder, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: color,
              activeTrackColor: color.withValues(alpha: 0.3),
              inactiveTrackColor: colors.cardBorder,
            ),
          ),
        ],
      ),
    );
  }
}
