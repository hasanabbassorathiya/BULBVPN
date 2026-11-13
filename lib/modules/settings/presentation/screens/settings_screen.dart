import 'dart:async';
import 'dart:io' show Platform;

import 'package:bulbvpn/app/links.dart';
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
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/metered_shell.dart';
import 'package:bulbvpn/shared/metered/slip_list.dart';
import 'package:bulbvpn/shared/metered/terms_panel.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/introduction_dialog.dart';
import 'package:bulbvpn/shared/services/firebase_analytics_service.dart';
import 'package:flutter/cupertino.dart' show showCupertinoDialog;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// The card's terms: what the tunnel is allowed to touch, what it costs, and
/// the paper trail it leaves on this phone.
///
/// The face is print on the plate the tear is already mounted on, so it pads
/// itself by the tear's depth instead of drawing a nav of its own, and it names
/// what it governs rather than repeating the tab it sits above.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(premiumProvider);
    final split = ref.watch(splitTunnelProvider);
    final adsEnabled =
        ref.watch(adsEnabledProvider) &&
        ref.watch(adsVisibleProvider) &&
        AdConfig.canRequestAds;

    return LayoutBuilder(
      builder: (context, c) {
        final type = MeteredType(c.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FaceHeader(
              type: type,
              title: 'Settings',
              // The plan is the one fact that changes what every line below is
              // worth, so it prints once at the head instead of as a badge on
              // each line it touches.
              note: premium.isActive
                  ? 'Premium · no ads, priority relays'
                  : 'Free plan · community relays',
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: meteredNavExtent(c.maxHeight) + type.px(24),
                ),
                children: [
                  SlipSection(type: type, title: 'Premium'),
                  TermRow(
                    type: type,
                    title: 'BULBVPN Premium',
                    sub: premium.isActive
                        ? 'Active · ad-free, priority relays'
                        : 'Ad-free · priority relays',
                    value: premium.isActive ? 'MANAGE' : 'PLANS',
                    onTap: () => _push(context, const PremiumScreen()),
                  ),
                  SlipSection(type: type, title: 'Connection'),
                  if (Platform.isAndroid) ...[
                    _KillSwitchRow(type: type),
                    TermRow(
                      type: type,
                      title: 'Split tunneling',
                      sub: split.scopeSummary,
                      value: 'ROUTING',
                      onTap: () => _push(context, const RoutingScreen()),
                    ),
                  ],
                  TermRow(
                    type: type,
                    title: 'Protocol',
                    sub:
                        'The engine negotiates the path and re-dials '
                        'when one is blocked',
                    // Not a switch: the engine picks, and the only honest value
                    // this line can print is that it decided for itself.
                    value: 'AUTOMATIC',
                  ),
                  SlipSection(type: type, title: 'Relays'),
                  TermRow(
                    type: type,
                    title: 'Relay sources',
                    sub:
                        'Community relays can see your traffic. '
                        'Own servers arrive with the engine.',
                    trailing: TrustMark(
                      label: 'NOT PRIVATE',
                      type: type,
                      semantic: TrustTier.bootstrap.disclosure,
                    ),
                  ),
                  SlipSection(type: type, title: 'About'),
                  SlipNote(
                    type: type,
                    text:
                        'BULBVPN carries your traffic through community '
                        'relays and picks the lowest latency from this device. '
                        'We do not inspect traffic through the tunnel, and we '
                        'are not responsible for how it is used or for any loss '
                        'that follows from using it.',
                  ),
                  TermRow(
                    type: type,
                    title: 'Introduction',
                    sub: 'What the relay can and cannot see',
                    value: 'READ',
                    onTap: () => showCupertinoDialog<void>(
                      context: context,
                      barrierDismissible: true,
                      builder: (_) => const IntroductionDialog(),
                    ),
                  ),
                  TermRow(
                    type: type,
                    title: 'Share BULBVPN',
                    sub: 'Copies the invite link',
                    value: 'COPY',
                    onTap: () => _share(context),
                  ),
                  TermRow(
                    type: type,
                    title: 'Privacy',
                    value: 'OPEN',
                    onTap: () => _openUrl(AppLinks.privacy),
                  ),
                  TermRow(
                    type: type,
                    title: 'Terms',
                    value: 'OPEN',
                    onTap: () => _openUrl(AppLinks.terms),
                  ),
                  TermRow(
                    type: type,
                    title: 'Connection log',
                    sub: 'Saved on this device · copy when reporting',
                    value: 'OPEN',
                    onTap: () => _push(context, const LogsScreen()),
                  ),
                  if (AppLinks.hasSupport)
                    TermRow(
                      type: type,
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
                    SlipSection(type: type, title: 'Sponsored'),
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
                    SlipNote(
                      type: type,
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

  final MeteredType type;

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
    final enabled = ref.watch(killSwitchProvider);
    final type = widget.type;
    void set(bool value) =>
        unawaited(ref.read(killSwitchProvider.notifier).setEnabled(value));
    return TermRow(
      type: type,
      title: 'Kill switch',
      sub: _blocked
          ? 'Traffic blocked — tunnel lost'
          : 'Block traffic if the tunnel drops',
      // The refusal red belongs to the finding, not to the switch: a kill
      // switch that is holding traffic is doing its job, and the line prints in
      // red because what it reports is traffic that did not get through.
      failed: _blocked,
      // The whole line throws the switch. A control this consequential is not
      // a target the width of a fingernail.
      onTap: () => set(!enabled),
      trailing: SizedBox(
        width: type.px(MeteredLayout.switchSlot.width),
        height: type.px(MeteredLayout.switchSlot.height),
        child: SlipSwitch(
          key: const ValueKey('kill-switch'),
          type: type,
          label: 'Kill switch',
          on: enabled,
          onChanged: set,
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.type});

  final MeteredType type;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return TermRow(
          type: type,
          title: 'Version',
          value: info == null ? '—' : '${info.version} (${info.buildNumber})',
          // Diagnostics stay off the surface; holding the build number opens
          // the connection log for the rare support case.
          onLongPress: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const LogsScreen())),
        );
      },
    );
  }
}
