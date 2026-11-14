import 'dart:async';
import 'dart:io' show Platform;

import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';
import 'package:bulbvpn/modules/core/kill_switch.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/modules/core/split_tunnel.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:bulbvpn/modules/monetization/ad_banner.dart';
import 'package:bulbvpn/modules/monetization/ad_config.dart';
import 'package:bulbvpn/modules/monetization/ads_remote_config.dart';
import 'package:bulbvpn/modules/monetization/paywall_screen.dart';
import 'package:bulbvpn/modules/monetization/premium.dart';
import 'package:bulbvpn/modules/monetization/private_app.dart';
import 'package:bulbvpn/modules/settings/presentation/screens/logs_screen.dart';
import 'package:bulbvpn/modules/settings/presentation/screens/routing_screen.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/introduction_dialog.dart';
import 'package:bulbvpn/shared/services/firebase_analytics_service.dart';
import 'package:bulbvpn/shared/simple/simple_header.dart';
import 'package:bulbvpn/shared/simple/simple_note.dart';
import 'package:bulbvpn/shared/simple/simple_section.dart';
import 'package:bulbvpn/shared/simple/simple_term_row.dart';
import 'package:bulbvpn/shared/simple/simple_type.dart';
import 'package:flutter/cupertino.dart' show showCupertinoDialog;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// The card's terms: what the tunnel is allowed to touch, what it costs, and
/// the paper trail it leaves on this phone.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.simple;
    final premium = ref.watch(premiumProvider);
    final split = ref.watch(splitTunnelProvider);
    final adsEnabled =
        ref.watch(adsEnabledProvider) &&
        ref.watch(adsVisibleProvider) &&
        AdConfig.canRequestAds;

    return LayoutBuilder(
      builder: (context, c) {
        final type = SimpleType(c.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SimpleHeader(
              title: 'Settings',
              note: premium.isActive
                  ? 'Premium · no ads, priority relays'
                  : 'Free plan · community relays',
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: 80 + type.px(24),
                ),
                children: [
                  SimpleSection(title: 'Premium'),
                  SimpleTermRow(
                    title: 'BULBVPN Premium',
                    sub: premium.isActive
                        ? 'Active · ad-free, priority relays'
                        : 'Ad-free · priority relays',
                    value: premium.isActive ? 'MANAGE' : 'PLANS',
                    onTap: () => _push(context, const PremiumScreen()),
                  ),
                  SimpleSection(title: 'Connection'),
                  if (Platform.isAndroid) ...[
                    _KillSwitchRow(type: type),
                    SimpleTermRow(
                      title: 'Split tunneling',
                      sub: split.scopeSummary,
                      value: 'ROUTING',
                      onTap: () => _push(context, const RoutingScreen()),
                    ),
                  ],
                  SimpleTermRow(
                    title: 'Protocol',
                    sub:
                        'The engine negotiates the path and re-dials '
                        'when one is blocked',
                    value: 'AUTOMATIC',
                  ),
                  SimpleSection(title: 'Relays'),
                  SimpleTermRow(
                    title: 'Relay sources',
                    sub:
                        'Community relays can see your traffic. '
                        'Own servers arrive with the engine.',
                    trailing: SimpleTrustMark(
                      label: 'NOT PRIVATE',
                      semantic: TrustTier.bootstrap.disclosure,
                    ),
                  ),
                  SimpleSection(title: 'About'),
                  SimpleNote(
                    text:
                        'BULBVPN carries your traffic through community '
                        'relays and picks the lowest latency from this device. '
                        'We do not inspect traffic through the tunnel, and we '
                        'are not responsible for how it is used or for any loss '
                        'that follows from using it.',
                  ),
                  SimpleTermRow(
                    title: 'Introduction',
                    sub: 'What the relay can and cannot see',
                    value: 'READ',
                    onTap: () => showCupertinoDialog<void>(
                      context: context,
                      barrierDismissible: true,
                      builder: (_) => const IntroductionDialog(),
                    ),
                  ),
                  SimpleTermRow(
                    title: 'Share BULBVPN',
                    sub: 'Copies the invite link',
                    value: 'COPY',
                    onTap: () => _share(context),
                  ),
                  SimpleTermRow(
                    title: 'Privacy',
                    value: 'OPEN',
                    onTap: () => _openUrl(AppLinks.privacy),
                  ),
                  SimpleTermRow(
                    title: 'Terms',
                    value: 'OPEN',
                    onTap: () => _openUrl(AppLinks.terms),
                  ),
                  SimpleTermRow(
                    title: 'Connection log',
                    sub: 'Saved on this device · copy when reporting',
                    value: 'OPEN',
                    onTap: () => _push(context, const LogsScreen()),
                  ),
                  if (AppLinks.hasSupport)
                    SimpleTermRow(
                      title: 'Support',
                      sub: _supportSubtitle,
                      value: 'OPEN',
                      onTap: () {
                        unawaited(
                          FirebaseAnalyticsService().logSupportOpened(
                            'teleform',
                          ),
                        );
                        unawaited(_openUrl(AppLinks.supportUrl));
                      },
                    ),
                  _VersionRow(type: type),
                  if (adsEnabled) ...[
                    SimpleSection(title: 'Sponsored'),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        type.px(26),
                        type.px(20),
                        type.px(24),
                        type.px(20),
                      ),
                      child: const AdBanner(),
                    ),
                  ],
                  if (PrivateApp.privateBuild)
                    SimpleNote(
                      text: 'Private build. Ads and subscriptions stay off.',
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  static String get _supportSubtitle {
    final url = AppLinks.supportUrl.toLowerCase();
    return url.contains('t.me') || url.contains('telegram')
        ? 'Telegram · opens the chat'
        : 'Teleform · send a message';
  }

  static Future<void> _openUrl(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  static Future<void> _share(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(
        text: '${AppLinks.website} — BULBVPN, censorship-proof internet',
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Invite link copied.')));
  }
}

/// Kill switch. Polls the native service only while it is on, so the line can
/// say "blocking traffic" after a drop instead of pretending nothing happened.
class _KillSwitchRow extends ConsumerStatefulWidget {
  const _KillSwitchRow({required this.type});

  final SimpleType type;

  @override
  ConsumerState<_KillSwitchRow> createState() => _KillSwitchRowState();
}

class _KillSwitchRowState extends ConsumerState<_KillSwitchRow> {
  Timer? _poll;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!ref.read(killSwitchProvider)) {
      if (_blocked && mounted) setState(() => _blocked = false);
      return;
    }
    final status = await SoftEtherVpn.status();
    if (!mounted) return;
    if (status.lockedDown != _blocked) {
      setState(() => _blocked = status.lockedDown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    final enabled = ref.watch(killSwitchProvider);
    final type = widget.type;
    void set(bool value) =>
        unawaited(ref.read(killSwitchProvider.notifier).setEnabled(value));
    return SimpleTermRow(
      title: 'Kill switch',
      sub: _blocked
          ? 'Traffic blocked — tunnel lost'
          : 'Block traffic if the tunnel drops',
      failed: _blocked,
      onTap: () => set(!enabled),
      trailing: SizedBox(
        width: type.px(56),
        height: type.px(28),
        child: Switch(
          key: const ValueKey('kill-switch'),
          value: enabled,
          onChanged: set,
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.type});

  final SimpleType type;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return SimpleTermRow(
          title: 'Version',
          value: info == null ? '—' : '${info.version} (${info.buildNumber})',
          onLongPress: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const LogsScreen())),
        );
      },
    );
  }
}
