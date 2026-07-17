import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/vpn_provider.dart';

class ProtocolScreen extends StatelessWidget {
  const ProtocolScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VPNProvider>();
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth > 600 ? 40.0 : 20.0;
    final currentProtocol = vpn.protocol;

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
                'Choose the VPN protocol that best suits your needs',
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
              const SizedBox(height: 28),

              _buildProtocolCard(
                context: context,
                colors: colors,
                icon: Icons.vpn_lock,
                title: 'OpenVPN',
                subtitle: 'Industry standard, widely supported',
                tags: ['Highly Compatible', 'Battle-tested', 'UDP & TCP'],
                pros: [
                  'Works on all networks',
                  'Mature and reliable',
                ],
                cons: ['Slightly slower than WireGuard'],
                isSelected: currentProtocol == 'OpenVPN',
                onTap: () => vpn.setProtocol('OpenVPN'),
              ),

              const SizedBox(height: 16),

              _buildProtocolCard(
                context: context,
                colors: colors,
                icon: Icons.speed,
                title: 'WireGuard',
                subtitle: 'Modern, fast, and lightweight',
                tags: ['Fastest', 'Modern', 'Low overhead'],
                pros: [
                  '2-4x faster than OpenVPN',
                  'Smaller codebase, easier to audit',
                ],
                cons: ['Newer, less widespread support'],
                isSelected: currentProtocol == 'WireGuard',
                onTap: () => vpn.setProtocol('WireGuard'),
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
                        'Recommended: WireGuard for best performance',
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

  Widget _buildProtocolCard({
    required BuildContext context,
    required AppSemanticColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<String> tags,
    required List<String> pros,
    required List<String> cons,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: colors.cardGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : colors.cardBorder,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 4))]
              : [],
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
                AnimatedScale(
                  scale: isSelected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                    child: const Icon(Icons.check, color: Colors.white, size: 16),
                  ),
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
            ...cons.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text('⚠️ ', style: TextStyle(fontSize: 13)),
                  Expanded(child: Text(c, style: TextStyle(fontSize: 13, color: AppColors.warning))),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}
