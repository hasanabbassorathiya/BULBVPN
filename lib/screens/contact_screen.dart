import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_theme.dart';
import '../providers/vpn_provider.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  Future<void> _openEmail() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final deviceInfo = DeviceInfoPlugin();
    String model = 'Unknown';
    String os = 'Unknown';
    String vpnStatus = 'Unknown';
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;

    try {
      if (isAndroid) {
        final info = await deviceInfo.androidInfo;
        model = '${info.manufacturer} ${info.model}';
        os = 'Android ${info.version.release}';
      } else {
        final info = await deviceInfo.iosInfo;
        model = '${info.name} ${info.modelName}';
        os = '${info.systemName} ${info.systemVersion}';
      }
    } catch (_) {}

    if (!mounted) return;
    try {
      final vpn = context.read<VPNProvider>();
      vpnStatus = vpn.isConnected ? 'Connected' : 'Disconnected';
    } catch (_) {}

    final body = '''
Device Information:
- App Version: ${packageInfo.version} (${packageInfo.buildNumber})
- Device: $model
- OS: $os
- VPN Status: $vpnStatus

Please describe your suggestion, feedback, or complaint:


''';

    final uri = Uri(
      scheme: 'mailto',
      path: 'hasanabbasssorathiya12@gmail.com',
      queryParameters: {
        'subject': 'BULB VPN - Suggestion/Feedback/Complaint',
        'body': body,
      },
    );

    if (!mounted) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

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
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_ios_new,
                        color: colors.textPrimary, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Contact Us',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'We\'d love to hear from you',
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
              const SizedBox(height: 32),
              _buildContactCard(colors),
              const SizedBox(height: 24),
              _buildInfoCard(colors),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard(AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Icon(Icons.mail_outline, size: 32, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Get in Touch',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Have a suggestion, feedback, or complaint? '
            'Send us an email and we\'ll get back to you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _openEmail,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.email_outlined, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Email Us',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT TO INCLUDE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          _buildTipItem(Icons.check_circle_outline, 'Description of your issue or suggestion', colors),
          _buildTipItem(Icons.check_circle_outline, 'Steps to reproduce (if reporting a bug)', colors),
          _buildTipItem(Icons.check_circle_outline, 'Your device model and Android/iOS version', colors),
          _buildTipItem(Icons.check_circle_outline, 'Screenshots if applicable', colors),
        ],
      ),
    );
  }

  Widget _buildTipItem(IconData icon, String text, AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
