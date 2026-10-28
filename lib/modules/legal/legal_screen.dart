import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/legal/legal_acceptance.dart';
import 'package:bulbvpn/shared/layout/main_screen_background.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// First-run clickwrap. The user must acknowledge the terms, the acceptable
/// use policy, and the risks of routing traffic through third-party relays
/// before the tunnel controls are reachable.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  bool _agreed = false;
  bool _saving = false;

  Future<void> _accept() async {
    if (!_agreed || _saving) return;
    setState(() => _saving = true);
    try {
      await LegalAcceptance.accept();
      if (mounted) context.go('/main');
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _decline() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Agreement required',
          style: TextStyle(color: AppColors.ink),
        ),
        content: const Text(
          'BULBVPN cannot be used without accepting the Terms and the '
          'Acceptable Use Policy.',
          style: TextStyle(color: AppColors.steel, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              SystemNavigator.pop();
            },
            child: const Text('Close app'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainScreenBackground(
      connectionStatus: ConnectionStatus.disconnected,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BEFORE YOU CONNECT', style: AppTextStyles.microLabel()),
                  const SizedBox(height: 8),
                  const Text(
                    'Ground rules',
                    style: TextStyle(
                      fontSize: 30,
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.6,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'BULBVPN is a tool, not a shield from the law.',
                    style: TextStyle(color: AppColors.steel, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                children: const [
                  _Section(
                    title: '1. How the tunnel works',
                    body:
                        'BULBVPN routes your traffic through volunteer VPN '
                        'Gate relays operated by third parties. We do not '
                        'control those servers. They can go offline, throttle, '
                        'log connection metadata, or change behaviour without '
                        'notice. No VPN — including this one — can guarantee '
                        'anonymity, hide your identity from every website, or '
                        'defeat account-based tracking.',
                  ),
                  _Section(
                    title: '2. Your responsibility',
                    body:
                        'You must comply with the laws that apply to you and '
                        'to the country you connect through. Using a VPN may '
                        'be restricted or illegal in some jurisdictions. You '
                        'are solely responsible for everything you do through '
                        'the tunnel, and for any consequences that follow.',
                  ),
                  _Section(
                    title: '3. Acceptable use',
                    body:
                        'Do not use BULBVPN to commit a crime, infringe '
                        'rights, distribute malware, defraud, harass, or harm '
                        'people; do not abuse the relay infrastructure. '
                        'Accounts and devices that do so may be blocked.',
                  ),
                  _Section(
                    title: '4. Risk and liability',
                    body:
                        'The app is provided "as is", without warranty. '
                        'Connections may fail, traffic may be blocked or lost, '
                        'and third parties may observe metadata. To the extent '
                        'the law allows, the developer is not liable for '
                        'indirect or consequential loss, and you agree to '
                        'indemnify the developer against claims arising from '
                        'your misuse or breach of these rules. Nothing here '
                        'excludes liability that cannot legally be excluded.',
                  ),
                  _Section(
                    title: '5. Ads and privacy',
                    body:
                        'The free build shows ads served by Google AdMob. '
                        'Google may collect device and advertising identifiers '
                        'as described in the Privacy Policy. Where required, '
                        'Google\'s consent form asks whether personalised ads '
                        'are allowed; you can reopen it from Settings.',
                  ),
                  _Section(
                    title: '6. Age and third-party terms',
                    body:
                        'You must be at least 18 years old (or the age of '
                        'majority where you live). App Store and Google Play '
                        'terms also apply to your download and use of the app.',
                  ),
                  SizedBox(height: 4),
                  _FullDocs(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                color: AppColors.canvas,
                border: Border(top: BorderSide(color: AppColors.hairline)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => setState(() => _agreed = !_agreed),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _agreed,
                          onChanged: (value) =>
                              setState(() => _agreed = value ?? false),
                          activeColor: AppColors.amber,
                          side: const BorderSide(color: AppColors.mute),
                        ),
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'I have read and agree to the Terms and the '
                              'Acceptable Use Policy, and I accept the risks '
                              'described above.',
                              style: TextStyle(
                                color: AppColors.steel,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _decline,
                        child: const Text(
                          'Decline',
                          style: TextStyle(color: AppColors.mute),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _agreed && !_saving ? _accept : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.amber,
                            foregroundColor: AppColors.canvas,
                            disabledBackgroundColor: AppColors.graphite,
                            disabledForegroundColor: AppColors.mute,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.canvas,
                                  ),
                                )
                              : const Text(
                                  'Agree and continue',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.steel,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullDocs extends StatelessWidget {
  const _FullDocs();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => launchUrl(
              Uri.parse(AppLinks.terms),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Full Terms'),
          ),
        ),
        Expanded(
          child: TextButton(
            onPressed: () => launchUrl(
              Uri.parse(AppLinks.privacy),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Privacy Policy'),
          ),
        ),
      ],
    );
  }
}
