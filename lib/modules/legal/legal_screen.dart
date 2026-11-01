import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/legal/legal_acceptance.dart';
import 'package:bulbvpn/shared/air/air_buttons.dart';
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
      if (mounted) context.go('/onboarding');
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _decline() {
    final air = context.air;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: air.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: air.hairline),
        ),
        title: Text(
          'Agreement required',
          style: AppTextStyles.title(color: air.ink, size: 18),
        ),
        content: Text(
          'BULBVPN cannot be used without accepting the Terms and the '
          'Acceptable Use Policy.',
          style: AppTextStyles.body(color: air.steel, size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Back', style: TextStyle(color: air.steel)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              SystemNavigator.pop();
            },
            child: Text('Close app', style: TextStyle(color: air.alertInk)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Scaffold(
      backgroundColor: air.ground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: air.surface,
                border: Border.symmetric(
                  horizontal: BorderSide(color: air.hairline),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BEFORE YOU CONNECT',
                          style: AppTextStyles.label(
                            color: air.steel,
                            size: 10.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Ground rules',
                          style: AppTextStyles.display(
                            color: air.ink,
                            size: 30,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'BULBVPN is a tool, not a shield from the law.',
                          style: AppTextStyles.body(
                            color: air.steel,
                            size: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: air.hairline),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                      children: [
                        for (final section in _sections) ...[
                          _Section(section: section),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: air.hairline,
                            ),
                          ),
                        ],
                        _FullDocs(),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                    decoration: BoxDecoration(
                      color: air.surface,
                      border: Border(top: BorderSide(color: air.hairline)),
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
                                activeColor: air.accent,
                                side: BorderSide(color: air.hairlineStrong),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'I have read and agree to the Terms and '
                                    'the Acceptable Use Policy, and I accept '
                                    'the risks described above.',
                                    style: AppTextStyles.body(
                                      color: air.steel,
                                      size: 12.5,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton(
                              onPressed: _decline,
                              child: Text(
                                'Decline',
                                style: TextStyle(color: air.mute),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AirButton.primary(
                                label: _saving
                                    ? 'Saving…'
                                    : 'Agree and continue',
                                onPressed: _agreed && !_saving ? _accept : null,
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
          ),
        ),
      ),
    );
  }
}

class _LegalSection {
  final String title;
  final String body;
  const _LegalSection(this.title, this.body);
}

const _sections = <_LegalSection>[
  _LegalSection(
    '1. How the tunnel works',
    'BULBVPN routes your traffic through volunteer VPN Gate relays '
        'operated by third parties. We do not control those servers. They '
        'can go offline, throttle, log connection metadata, or change '
        'behaviour without notice. No VPN — including this one — can '
        'guarantee anonymity, hide your identity from every website, or '
        'defeat account-based tracking.',
  ),
  _LegalSection(
    '2. Your responsibility',
    'You must comply with the laws that apply to you and to the country you '
        'connect through. Using a VPN may be restricted or illegal in some '
        'jurisdictions. You are solely responsible for everything you do '
        'through the tunnel, and for any consequences that follow.',
  ),
  _LegalSection(
    '3. Acceptable use',
    'Do not use BULBVPN to commit a crime, infringe rights, distribute '
        'malware, defraud, harass, or harm people; do not abuse the relay '
        'infrastructure. Accounts and devices that do so may be blocked.',
  ),
  _LegalSection(
    '4. Risk and liability',
    'The app is provided "as is", without warranty. Connections may fail, '
        'traffic may be blocked or lost, and third parties may observe '
        'metadata. To the extent the law allows, the developer is not liable '
        'for indirect or consequential loss, and you agree to indemnify the '
        'developer against claims arising from your misuse or breach of '
        'these rules. Nothing here excludes liability that cannot legally be '
        'excluded.',
  ),
  _LegalSection(
    '5. Ads and privacy',
    'The free build shows ads served by Google AdMob. Google may collect '
        'device and advertising identifiers as described in the Privacy '
        'Policy. Where required, Google\'s consent form asks whether '
        'personalised ads are allowed; you can reopen it from Settings.',
  ),
  _LegalSection(
    '6. Age and third-party terms',
    'You must be at least 18 years old (or the age of majority where you '
        'live). App Store and Google Play terms also apply to your download '
        'and use of the app.',
  ),
];

class _Section extends StatelessWidget {
  const _Section({required this.section});

  final _LegalSection section;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: AppTextStyles.title(color: air.ink, size: 17),
        ),
        const SizedBox(height: 8),
        Text(
          section.body,
          style: AppTextStyles.body(color: air.ink, size: 15, height: 1.6),
        ),
      ],
    );
  }
}

class _FullDocs extends StatelessWidget {
  const _FullDocs();

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => launchUrl(
              Uri.parse(AppLinks.terms),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              'Full Terms',
              style: TextStyle(color: air.accentInk),
            ),
          ),
        ),
        Expanded(
          child: TextButton(
            onPressed: () => launchUrl(
              Uri.parse(AppLinks.privacy),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              'Privacy Policy',
              style: TextStyle(color: air.accentInk),
            ),
          ),
        ),
      ],
    );
  }
}
