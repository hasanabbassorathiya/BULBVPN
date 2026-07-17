import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/components/app_badge.dart';
import '../widgets/components/app_button.dart';
import '../widgets/components/app_card.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth > 600 ? 40.0 : 20.0;
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    final displayName = user?.displayName ?? 'Guest User';
    final email = user?.email ?? 'Not signed in';
    final initials = _getInitials(displayName);

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
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_rounded, color: colors.textPrimary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text('Profile', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: colors.textPrimary)),
                ],
              ),
              const SizedBox(height: 24),
              _buildHeader(initials, displayName, email, colors),
              const SizedBox(height: 24),
              _buildAccountSection(user, colors),
              const SizedBox(height: 16),
              _buildSettingsSection(context, colors),
              const SizedBox(height: 16),
              _buildSignOutButton(context, auth, colors),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Widget _buildHeader(String initials, String displayName, String email, AppSemanticColors colors) {
    return AppCard(
      child: Center(
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.heroGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              displayName,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              email,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection(dynamic user, AppSemanticColors colors) {
    final tierLabel = user != null ? 'Free' : 'Free';
    final tierColor = AppColors.primary;
    final dataUsedMB = 347;
    final dataLimitMB = 500;
    final usagePercent = dataLimitMB > 0 ? (dataUsedMB / dataLimitMB).clamp(0.0, 1.0) : 0.0;
    final createdAt = user != null ? 'Jan 15, 2025' : 'Unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACCOUNT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.textMuted, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.workspace_premium, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Subscription', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                        const SizedBox(height: 4),
                        AppBadge(label: tierLabel, color: tierColor, icon: Icons.star_rounded),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: colors.cardBorder, height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.data_usage, color: AppColors.info, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Data Usage', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: usagePercent,
                            minHeight: 6,
                            backgroundColor: colors.cardBorder,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              usagePercent > 0.8 ? AppColors.warning : AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${dataUsedMB}MB / ${dataLimitMB}MB',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: colors.cardBorder, height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calendar_today, color: AppColors.success, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Member Since', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(createdAt, style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSection(BuildContext context, AppSemanticColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SETTINGS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.textMuted, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              _buildNavTile(Icons.edit_rounded, 'Edit Profile', 'Update your name and photo', () {}, colors),
              Divider(color: colors.cardBorder, height: 1),
              _buildNavTile(Icons.lock_rounded, 'Change Password', 'Update your password', () {}, colors),
              Divider(color: colors.cardBorder, height: 1),
              _buildNavTile(Icons.delete_forever_rounded, 'Delete Account', 'Permanently remove your data', () => _showDeleteDialog(context, colors), colors, isDestructive: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavTile(IconData icon, String title, String subtitle, VoidCallback onTap, AppSemanticColors colors, {bool isDestructive = false}) {
    final iconColor = isDestructive ? AppColors.error : AppColors.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDestructive ? AppColors.error : colors.textPrimary)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, AppSemanticColors colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            const SizedBox(width: 10),
            Text('Delete Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently removed.',
          style: TextStyle(fontSize: 14, color: colors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutButton(BuildContext context, AuthProvider auth, AppSemanticColors colors) {
    return AppButton(
      label: 'Sign Out',
      icon: Icons.logout_rounded,
      variant: AppButtonVariant.outlined,
      color: AppColors.error,
      isFullWidth: true,
      onPressed: () async {
        await auth.signOut();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthScreen()),
            (route) => false,
          );
        }
      },
    );
  }
}
