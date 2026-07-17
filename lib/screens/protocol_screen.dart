import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class ProtocolScreen extends StatelessWidget {
  const ProtocolScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth > 600 ? 40.0 : 20.0;

    return Container(
      decoration: BoxDecoration(gradient: colors.bgGradient),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(horizontalPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios, color: colors.textPrimary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Text('Protocol', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: colors.textPrimary)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'V2Ray is the active VPN protocol',
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
              const SizedBox(height: 28),

              _buildProtocolInfoCard(
                colors: colors,
                icon: Icons.vpn_lock,
                title: 'V2Ray',
                subtitle: 'Flexible, modern proxy protocol',
                tags: ['Versatile', 'Encrypted', 'Multiple transports'],
                pros: [
                  'Supports VMess, VLESS, Trojan, and Shadowsocks',
                  'Multiple transport protocols (WebSocket, gRPC, HTTP/2)',
                  'Strong encryption and obfuscation',
                ],
              ),

              const SizedBox(height: 24),

              Text(
                'Supported Sub-Protocols',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textPrimary),
              ),
              const SizedBox(height: 12),

              _buildSubProtocolTile(
                colors: colors,
                name: 'VLESS',
                description: 'Lightweight, TLS-based. Fast and efficient with less overhead.',
                icon: Icons.flash_on,
                color: AppColors.connected,
              ),
              const SizedBox(height: 8),
              _buildSubProtocolTile(
                colors: colors,
                name: 'VMess',
                description: 'Encryption with authentication. Widely supported and battle-tested.',
                icon: Icons.lock_outline,
                color: AppColors.primary,
              ),
              const SizedBox(height: 8),
              _buildSubProtocolTile(
                colors: colors,
                name: 'Trojan',
                description: 'Disguises VPN traffic as regular HTTPS. Great for restrictive networks.',
                icon: Icons.shield_outlined,
                color: AppColors.info,
              ),
              const SizedBox(height: 8),
              _buildSubProtocolTile(
                colors: colors,
                name: 'Shadowsocks',
                description: 'Lightweight encrypted proxy. Simple and fast.',
                icon: Icons.speed,
                color: AppColors.secondary,
              ),

              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Import V2Ray configs using vmess://, vless://, trojan://, or ss:// links',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProtocolInfoCard({
    required AppSemanticColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<String> tags,
    required List<String> pros,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                  ],
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: tags.map((tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
            )).toList(),
          ),
          const SizedBox(height: 16),
          ...pros.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Text('✅ ', style: TextStyle(fontSize: 13)),
                Expanded(child: Text(p, style: TextStyle(fontSize: 13, color: colors.textSecondary))),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildSubProtocolTile({
    required AppSemanticColors colors,
    required String name,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
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
                Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textPrimary)),
                const SizedBox(height: 2),
                Text(description, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
