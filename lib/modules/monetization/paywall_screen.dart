import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/monetization/premium.dart';
import 'package:bulbvpn/shared/air/air_buttons.dart';
import 'package:bulbvpn/shared/air/air_layout.dart';
import 'package:bulbvpn/shared/air/air_rows.dart';
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
    final air = context.air;
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
      backgroundColor: air.ground,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AirLayout.wideRail),
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
                        style: AppTextStyles.title(color: air.ink, size: 19),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    // The shell's nav bar floats over the body, so the last
                    // legal line must clear it plus the home indicator.
                    padding: const EdgeInsets.fromLTRB(
                      AirLayout.gutter,
                      8,
                      AirLayout.gutter,
                      120,
                    ),
                    children: [
                      Text(
                        'A quieter tunnel.',
                        style: AppTextStyles.display(color: air.ink, size: 32),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'The VPN stays free. Premium removes ads and puts the '
                        'fastest, least-crowded relays at the front of every '
                        'connection.',
                        style: AppTextStyles.body(color: air.steel, size: 14),
                      ),
                      const SizedBox(height: 24),
                      AirSection(
                        title: 'Free',
                        rows: const [
                          AirRow(title: 'Community and bootstrap relays'),
                          AirRow(title: 'Speed test'),
                          AirRow(title: 'Split tunneling on Android'),
                        ],
                      ),
                      const SizedBox(height: 22),
                      AirSection(
                        title: 'Premium',
                        rows: [
                          _feature('Priority relays', air),
                          _feature('No ads', air),
                        ],
                      ),
                      const SizedBox(height: 26),
                      if (active)
                        AirSection(
                          title: 'Status',
                          rows: [
                            AirRow(
                              title: 'Premium is active',
                              subtitle:
                                  'Ads are off and priority relays are on for '
                                  'this account.',
                              chevron: false,
                              trailing: Icon(
                                Icons.check_circle,
                                size: 20,
                                color: air.connectedInk,
                              ),
                            ),
                          ],
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
                                  color: air.steel,
                                  size: 11,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (ordered.isNotEmpty)
                        AirSection(
                          title: 'Plans',
                          rows: [
                            for (final package in ordered)
                              _planRow(package),
                          ],
                        )
                      else
                        _unavailable(premium),
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
                        AirSection(
                          title: 'Redeem',
                          rows: [_codeRow(premium)],
                          note: Text(
                            'One BULB code works on Android, iOS, and macOS. '
                            'A code can be claimed on one account only.',
                            style: AppTextStyles.monoValue(
                              color: air.steel,
                              size: 11,
                            ),
                          ),
                        ),
                      ],
                      if (!active) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Subscriptions renew automatically for the same '
                          'period and price unless cancelled at least 24 hours '
                          'before the current period ends. Manage or cancel any '
                          'time in your App Store or Play Store account. Prices '
                          'come from the store and may vary by region.',
                          style: AppTextStyles.body(color: air.mute, size: 11),
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

  Widget _feature(String title, AirColors air) {
    return AirRow(
      title: title,
      chevron: false,
      trailing: Icon(Icons.check, size: 18, color: air.accentInk),
    );
  }

  Widget _planRow(Package package) {
    final annual = package.packageType == PackageType.annual;
    return AirRow(
      title: annual ? 'Yearly' : 'Monthly',
      subtitle: annual ? 'One charge a year' : 'One charge a month',
      chevron: false,
      value: package.storeProduct.priceString,
      trailing: AirButton.primary(
        label: _busy ? 'Working…' : 'Choose',
        expand: false,
        height: 44,
        onPressed: _busy ? null : () => _buy(package),
      ),
    );
  }

  Widget _unavailable(PremiumState premium) {
    final air = context.air;
    final unconfigured = premium.status == PremiumStatus.unconfigured;
    return AirSection(
      title: 'Plans',
      rows: [
        AirRow(
          title: unconfigured
              ? 'Store setup is not live in this build'
              : 'Plans could not be loaded',
          subtitle: unconfigured
              ? 'Purchases are off in this build.'
              : 'Check your connection and retry.',
          chevron: false,
          trailing: unconfigured
              ? null
              : AirButton.secondary(
                  label: _busy ? 'Retrying…' : 'Retry',
                  expand: false,
                  height: 44,
                  onPressed: _busy ? null : _retryOfferings,
                ),
        ),
      ],
      note: unconfigured
          ? Text(
              'The tunnel keeps working for free. Purchases and '
              'cross-platform codes turn on once the store products are '
              'connected.',
              style: AppTextStyles.body(color: air.steel, size: 12.5),
            )
          : Text(
              'Nothing was charged.',
              style: AppTextStyles.body(color: air.steel, size: 12.5),
            ),
    );
  }

  Widget _codeRow(PremiumState premium) {
    final air = context.air;
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
              style: AppTextStyles.monoValue(color: air.ink, size: 15),
              decoration: InputDecoration(
                hintText: canRedeem ? 'BULB-XXXX' : 'Codes are not live yet',
                hintStyle: AppTextStyles.monoValue(color: air.mute, size: 15),
              ),
              onSubmitted: (_) => _redeem(),
            ),
          ),
          const SizedBox(width: 10),
          AirButton.secondary(
            label: canRedeem ? 'Redeem' : 'Soon',
            expand: false,
            height: 44,
            onPressed: canRedeem && !_busy ? _redeem : null,
          ),
        ],
      ),
    );
  }

  Widget _footerLink(String label, String url) {
    final mute = context.air.mute;
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Text(
        label,
        style: TextStyle(
          color: mute,
          fontSize: 12,
          decoration: TextDecoration.underline,
          decorationColor: mute,
        ),
      ),
    );
  }
}
