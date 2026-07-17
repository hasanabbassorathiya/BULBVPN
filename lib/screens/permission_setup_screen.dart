import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/v2ray_service.dart';
import '../services/storage_service.dart';
import '../widgets/components/app_button.dart';
import '../main.dart';

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _grantPermission() async {
    setState(() => _isRequesting = true);

    try {
      final vpnService = V2RayService();
      await vpnService.initialize();

      if (!mounted) return;

      await StorageService().setString('vpn_permission_granted', 'true');
      _navigateToMain();
    } catch (e) {
      if (mounted) _showDeniedDialog();
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  void _showDeniedDialog() {
    final colors = AppSemanticColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.info, size: 24),
            const SizedBox(width: 10),
            Text('Permission Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary)),
          ],
        ),
        content: Text(
          'To use BULB VPN, you need to grant VPN permission in your device settings. You can enable this later from Settings > VPN Tools.',
          style: TextStyle(fontSize: 14, color: colors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToMain();
            },
            child: Text('OK', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _navigateToMain() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainNavigation()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth > 600 ? 60.0 : 32.0;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomRight,
            colors: [AppColors.bgDark, colors.surface],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPad),
            child: Column(
              children: [
                const Spacer(flex: 2),
                _buildShieldIcon(),
                const SizedBox(height: 40),
                _buildTitle(colors),
                const SizedBox(height: 16),
                _buildExplanation(colors),
                const SizedBox(height: 32),
                _buildFeatureBullets(colors),
                const Spacer(flex: 2),
                _buildGrantButton(),
                const SizedBox(height: 16),
                _buildMaybeLaterLink(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShieldIcon() {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.heroGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3 * _glowAnimation.value),
                blurRadius: 40 * _glowAnimation.value,
                spreadRadius: 10 * _glowAnimation.value,
              ),
            ],
          ),
          child: const Icon(
            Icons.shield_rounded,
            size: 48,
            color: Colors.white,
          ),
        );
      },
    );
  }

  Widget _buildTitle(AppSemanticColors colors) {
    return Text(
      'VPN Permission Required',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: colors.textPrimary,
        height: 1.2,
      ),
    );
  }

  Widget _buildExplanation(AppSemanticColors colors) {
    return Text(
      'BULB VPN needs permission to create a VPN connection. This allows us to route your internet traffic through our secure servers.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: colors.textSecondary,
      ),
    );
  }

  Widget _buildFeatureBullets(AppSemanticColors colors) {
    final features = [
      _FeatureItem(icon: Icons.lock_rounded, text: 'Encrypts all your internet traffic', color: AppColors.primary),
      _FeatureItem(icon: Icons.public_rounded, text: 'Hides your real IP address', color: AppColors.accent),
      _FeatureItem(icon: Icons.speed_rounded, text: 'Maintains full internet speed', color: AppColors.connected),
    ];

    return Column(
      children: features.map((f) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: f.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(f.icon, color: f.color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  f.text,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGrantButton() {
    return AppButton(
      label: 'Grant Permission',
      icon: Icons.shield_rounded,
      isFullWidth: true,
      isLoading: _isRequesting,
      onPressed: _isRequesting ? null : _grantPermission,
    );
  }

  Widget _buildMaybeLaterLink() {
    return GestureDetector(
      onTap: _navigateToMain,
      child: Text(
        'Maybe Later',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String text;
  final Color color;

  const _FeatureItem({
    required this.icon,
    required this.text,
    required this.color,
  });
}
