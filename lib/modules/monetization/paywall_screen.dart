import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';
import 'package:bulbvpn/modules/monetization/premium.dart';
import 'package:bulbvpn/shared/simple/simple_key.dart';
import 'package:bulbvpn/shared/simple/simple_note.dart';
import 'package:bulbvpn/shared/simple/simple_section.dart';
import 'package:bulbvpn/shared/simple/simple_term_row.dart';
import 'package:bulbvpn/shared/services/firebase_analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Premium removes ads and ranks the least-crowded, highest-capacity relays
/// first. The VPN itself never depends on it: free users keep every country.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _busy = false;
  bool _showCode = false;
  final TextEditingController _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    FirebaseAnalyticsService().logPaywallViewed();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _buy(Package package) async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await ref.read(premiumProvider.notifier).purchase(package);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _toast(error);
    } else if (ref.read(premiumProvider).isActive) {
      _toast('Premium is active. Ads are off and priority relays are on.');
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await ref.read(premiumProvider.notifier).restore();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(error ?? 'Premium restored on this account.');
  }

  Future<void> _redeem() async {
    if (_busy) return;
    setState(() => _busy = true);
    final message = await ref
        .read(premiumProvider.notifier)
        .redeemUniversal(_code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (message == null) {
      _code.clear();
      _toast('Code redeemed. Premium is active on this device.');
    } else {
      _toast(message);
    }
  }

  Future<void> _retryOfferings() async {
    setState(() => _busy = true);
    await ref.read(premiumProvider.notifier).loadOfferings();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ref.read(premiumProvider).hasProducts) {
      _toast('Plans are still unavailable. Check your connection and retry.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    final premium = ref.watch(premiumProvider);
    final active = premium.isActive;
    final loading =
        premium.status == PremiumStatus.loading ||
        premium.status == PremiumStatus.unknown;
    final packages =
        premium.offerings?.current?.availablePackages ?? const <Package>[];
    final ordered = [
      for (final p in packages)
        if (p.packageType == PackageType.annual) p,
      for (final p in packages)
        if (p.packageType != PackageType.annual) p,
    ];

    return Scaffold(
      backgroundColor: s.background,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Premium',
                        style: AppTextStyles.title(color: s.ink, size: 19),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      120,
                    ),
                    children: [
                      Text(
                        'A quieter tunnel.',
                        style: AppTextStyles.display(color: s.ink, size: 32),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'The VPN stays free. Premium removes ads and puts the '
                        'fastest, least-crowded relays at the front of every '
                        'connection.',
                        style: AppTextStyles.body(color: s.inkSoft, size: 14),
                      ),
                      const SizedBox(height: 24),
                      SimpleSection(title: 'Free'),
                      SimpleTermRow(title: 'Community and bootstrap relays'),
                      SimpleTermRow(title: 'Speed test'),
                      SimpleTermRow(title: 'Split tunneling on Android'),
                      const SizedBox(height: 22),
                      SimpleSection(title: 'Premium'),
                      _feature('Priority relays', s),
                      _feature('No ads', s),
                      const SizedBox(height: 26),
                      if (active)
                        SimpleSection(
                          title: 'Status',
                          note: 'Ads are off and priority relays are on for '
                              'this account.',
                          disclosure: 'Active',
                          disclosureSemantics: 'Premium active',
                        )
                      else if (loading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Column(
                            children: [
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Loading store prices…',
                                style: AppTextStyles.monoValue(
                                  color: s.inkSoft,
                                  size: 11,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (ordered.isNotEmpty) ...[
                        SimpleSection(title: 'Plans'),
                        for (final package in ordered)
                          _planRow(package),
                      ]
                      else
                        _unavailable(s),
                      if (!active && !loading) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: _busy ? null : _restore,
                            child: const Text('Restore purchases'),
                          ),
                        ),
                      ],
                      if (!active && !_showCode) ...[
                        const SizedBox(height: 4),
                        Center(
                          child: TextButton(
                            onPressed: () => setState(() => _showCode = true),
                            child: const Text('Have a code?'),
                          ),
                        ),
                      ],
                      if (!active && _showCode) ...[
                        const SizedBox(height: 16),
                        SimpleSection(
                          title: 'Redeem',
                          note: 'One BULB code works on Android, iOS, and '
                              'macOS. A code can be claimed on one account only.',
                        ),
                        _codeRow(s),
                      ],
                      if (!active) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Subscriptions renew automatically for the same '
                          'period and price unless cancelled at least 24 hours '
                          'before the current period ends. Manage or cancel any '
                          'time in your App Store or Play Store account. Prices '
                          'come from the store and may vary by region.',
                          style: AppTextStyles.body(color: s.inkFaint, size: 11),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Center(
                        child: Wrap(
                          spacing: 18,
                          children: [
                            _footerLink('Privacy Policy', AppLinks.privacy),
                            _footerLink('Terms of Use', AppLinks.terms),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _feature(String title, SimpleColors s) {
    return SimpleTermRow(
      title: title,
      trailing: Icon(Icons.check, size: 18, color: s.connectedInk),
    );
  }

  Widget _planRow(Package package) {
    final annual = package.packageType == PackageType.annual;
    return SimpleTermRow(
      title: annual ? 'Yearly' : 'Monthly',
      sub: '${annual ? 'One charge a year' : 'One charge a month'} · '
          '${package.storeProduct.priceString}',
      trailing: SimpleKey(
        label: _busy ? 'Working…' : 'Choose',
        busy: _busy,
        onTap: _busy ? null : () => _buy(package),
      ),
    );
  }

  Widget _unavailable(SimpleColors s) {
    final premium = ref.read(premiumProvider);
    final unconfigured = premium.status == PremiumStatus.unconfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SimpleSection(
          title: 'Plans',
          note: unconfigured
              ? 'Store setup is not live in this build'
              : 'Plans could not be loaded',
        ),
        if (!unconfigured) ...[
          const SizedBox(height: 12),
          SimpleKey(
            label: _busy ? 'Retrying…' : 'Retry',
            busy: _busy,
            emphasis: true,
            onTap: _busy ? null : _retryOfferings,
          ),
        ],
        SimpleNote(
          text: unconfigured
              ? 'The tunnel keeps working for free. Purchases and '
                  'cross-platform codes turn on once the store products are '
                  'connected.'
              : 'Nothing was charged.',
        ),
      ],
    );
  }

  Widget _codeRow(SimpleColors s) {
    final premium = ref.read(premiumProvider);
    final canRedeem = premium.isConfigured && premiumRedeemUrl.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _code,
              enabled: canRedeem && !_busy,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              style: AppTextStyles.monoValue(color: s.ink, size: 15),
              decoration: InputDecoration(
                hintText:
                    canRedeem ? 'BULB-XXXX' : 'Codes are not live yet',
                hintStyle: AppTextStyles.monoValue(
                  color: s.inkFaint,
                  size: 15,
                ),
              ),
              onSubmitted: (_) => _redeem(),
            ),
          ),
          const SizedBox(width: 10),
          SimpleKey(
            label: canRedeem ? 'Redeem' : 'Soon',
            busy: _busy,
            onTap: canRedeem && !_busy ? _redeem : null,
          ),
        ],
      ),
    );
  }

  Widget _footerLink(String label, String url) {
    final mute = context.simple.inkFaint;
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      // 14 px of vertical padding lifts the glyph box to a 44 px target (§4);
      // an underlined 12 px label is tappable but not reachable.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Text(
          label,
          style: AppTextStyles.body(color: mute, size: 12.5).copyWith(
            decoration: TextDecoration.underline,
            decorationColor: mute,
          ),
        ),
      ),
    );
  }
}
