import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_theme.dart';
import '../models/in_app_message.dart';
import '../providers/auth_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/analytics_service.dart';
import '../services/in_app_message_service.dart';
import '../widgets/components/app_badge.dart';
import '../widgets/promo_banner.dart';
import 'about_screen.dart';
import 'auth_screen.dart';
import 'contact_screen.dart';
import 'paywall_screen.dart';
import 'profile_screen.dart';
import 'permission_setup_screen.dart';
import 'speed_test_screen.dart';
import 'split_tunnel_screen.dart';
import 'threat_protection_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  InAppMessage? _upgradeMessage;
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadUpgradeMessage();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  Future<void> _loadUpgradeMessage() async {
    final service = InAppMessageService();
    await service.loadMessages();
    final msg = service.getUpgradeMessage();
    if (msg != null && mounted) {
      await service.recordView(msg.id);
      setState(() => _upgradeMessage = msg);
    }
  }

  void _dismissUpgradeMessage() {
    if (_upgradeMessage != null) {
      InAppMessageService().dismissMessage(_upgradeMessage!.id);
      setState(() => _upgradeMessage = null);
    }
  }

  void _handleUpgradeAction() {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PaywallScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VPNProvider>();
    final auth = context.watch<AuthProvider>();
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth > 600 ? 40.0 : 20.0;
    final user = auth.currentUser;

    return Container(
      decoration: BoxDecoration(gradient: colors.bgGradient),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(horizontalPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: colors.textPrimary)),
              const SizedBox(height: 24),
              _buildUpgradeSection(context, vpn, colors),
              if (_upgradeMessage != null) ...[
                const SizedBox(height: 16),
                PromoBanner(
                  message: _upgradeMessage!,
                  onAction: _handleUpgradeAction,
                  onDismiss: _dismissUpgradeMessage,
                ),
              ],
              const SizedBox(height: 16),
              _buildProfileSection(context, auth, user, colors),
              const SizedBox(height: 16),
              _buildSection('Protocol', colors, [
                _buildInfoTile(Icons.cable, 'Protocol', '${vpn.protocol} (active)', colors),
              ]),
              const SizedBox(height: 16),
              _buildSection('Connection', colors, [
                _buildSwitchTile(Icons.sync, 'Auto-Connect', 'Connect on app start', vpn.autoConnect, (v) {
                  vpn.setAutoConnect(v);
                  AnalyticsService().logSettingsChanged(setting: 'auto_connect', value: v);
                }, colors),
                _buildSwitchTile(Icons.replay, 'Auto-Reconnect', 'Automatically reconnect if VPN drops', vpn.autoReconnect, (v) => vpn.setAutoReconnect(v), colors),
                _buildSwitchTile(Icons.shield, 'Kill Switch', 'Block if VPN drops', vpn.killSwitch, (v) {
                  vpn.setKillSwitch(v);
                  AnalyticsService().logSettingsChanged(setting: 'kill_switch', value: v);
                }, colors, isWarning: true),
              ]),
              const SizedBox(height: 16),
              _buildSection('VPN Tools', colors, [
                _buildNavTile(Icons.shield_rounded, 'VPN Permission', 'Manage VPN access', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PermissionSetupScreen())), colors),
                _buildNavTile(Icons.select_all, 'Split Tunneling', 'Choose apps for VPN', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SplitTunnelScreen())), colors),
                _buildNavTile(Icons.security, 'Threat Protection', 'Block ads & trackers', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThreatProtectionScreen())), colors),
              ]),
              const SizedBox(height: 16),
              _buildSection('Appearance', colors, [
                _buildSwitchTile(Icons.dark_mode, 'Dark Mode', vpn.darkMode ? 'Dark theme active' : 'Light theme active', vpn.darkMode, (v) {
                vpn.setDarkMode(v);
                AnalyticsService().logThemeChanged(theme: v ? 'dark' : 'light');
              }, colors),
              ]),
              const SizedBox(height: 16),
              _buildSection('About', colors, [
                _buildNavTile(Icons.speed, 'Speed Test', 'Measure connection speed', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SpeedTestScreen())), colors),
                _buildInfoTile(Icons.info_outline, 'Version', _appVersion, colors),
                _buildInfoTile(Icons.code, 'Protocol', 'OpenVPN (axevpn_flutter)', colors),
                _buildInfoTile(Icons.dns, 'Servers', '99 VPN Gate servers', colors),
              ]),
              const SizedBox(height: 16),
              _buildSection('Support', colors, [
                _buildNavTile(Icons.info_outline, 'About BULB VPN', 'App information & licenses', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())), colors),
                _buildNavTile(Icons.mail_outline, 'Contact Us', 'Send feedback or report issues', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactScreen())), colors),
                _buildNavTile(Icons.star_outline, 'Rate Us', 'Rate BULB VPN on Play Store', () async {
                  final url = Uri.parse('https://play.google.com/store/apps/details?id=com.bulbvpn.app');
                  if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                }, colors),
                _buildNavTile(Icons.privacy_tip_outlined, 'Privacy Policy', 'View privacy policy', () async {
                  final url = Uri.parse('https://bulbvpn.com/privacy');
                  if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                }, colors),
                _buildNavTile(Icons.description_outlined, 'Terms of Service', 'View terms of service', () async {
                  final url = Uri.parse('https://bulbvpn.com/terms');
                  if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                }, colors),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpgradeSection(BuildContext context, VPNProvider vpn, AppSemanticColors colors) {
    final isSubscriber = vpn.isSubscriber;

    return GestureDetector(
      onTap: isSubscriber
          ? null
          : () async {
              final purchased = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => const PaywallScreen(),
                ),
              );
              if (purchased == true) {
                vpn.setSubscriber(true);
              }
            },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isSubscriber
              ? colors.cardGradient
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A2332), Color(0xFF162030)],
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSubscriber ? colors.cardBorder : AppColors.primary.withValues(alpha: 0.4),
            width: isSubscriber ? 1 : 1.5,
          ),
          boxShadow: isSubscriber
              ? null
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: isSubscriber ? null : AppColors.heroGradient,
                color: isSubscriber ? AppColors.primary.withValues(alpha: 0.15) : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSubscriber ? Icons.workspace_premium : Icons.diamond_outlined,
                color: isSubscriber ? AppColors.primary : Colors.black,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isSubscriber ? 'Premium Active' : 'Upgrade to Pro',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AppBadge(
                        label: isSubscriber ? 'Active' : 'Free',
                        color: isSubscriber ? AppColors.success : AppColors.warning,
                        size: AppBadgeSize.small,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSubscriber
                        ? 'Manage your subscription'
                        : 'Unlock all servers, streaming & more',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              isSubscriber ? Icons.chevron_right : Icons.arrow_forward_ios,
              color: colors.textSecondary,
              size: isSubscriber ? 20 : 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context, AuthProvider auth, dynamic user, AppSemanticColors colors) {
    if (user != null) {
      final displayName = user.displayName ?? 'User';
      final email = user.email ?? '';
      final initials = displayName.split(' ').where((p) => p.isNotEmpty).map((p) => p[0]).take(2).join().toUpperCase();

      return GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: colors.cardGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.heroGradient,
                ),
                child: Center(
                  child: Text(initials, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                    Text(email, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textSecondary, size: 20),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_outline, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sign In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  Text('Create an account to sync your data', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, AppSemanticColors colors, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.textMuted, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.cardBorder)),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged, AppSemanticColors colors, {bool isWarning = false}) {
    return Semantics(
      label: '$title: ${value ? 'on' : 'off'}',
      toggled: value,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: (isWarning ? AppColors.warning : AppColors.primary).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: isWarning ? AppColors.warning : AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
            ])),
            Switch(value: value, onChanged: onChanged, activeThumbColor: isWarning ? AppColors.warning : AppColors.primary, activeTrackColor: (isWarning ? AppColors.warning : AppColors.primary).withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile(IconData icon, String title, String subtitle, VoidCallback onTap, AppSemanticColors colors) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.primary, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
            ])),
            Icon(Icons.chevron_right, color: colors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String subtitle, AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.primary, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
          ])),
        ],
      ),
    );
  }
}
