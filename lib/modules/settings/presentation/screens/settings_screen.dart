import 'dart:async';
import 'dart:io' show Platform;

import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
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
import 'package:bulbvpn/shared/air/air_layout.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/air/air_rows.dart';
import 'package:bulbvpn/shared/air/horizon_field.dart';
import 'package:bulbvpn/shared/air/trust_badge.dart';
import 'package:bulbvpn/shared/layout/navbar/widgets/introduction_dialog.dart';
import 'package:bulbvpn/shared/services/firebase_analytics_service.dart';
import 'package:flutter/cupertino.dart' show showCupertinoDialog;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// The ledger: what the tunnel is doing, what it is allowed to touch, and the
/// paper trail. Rows sit on the ground between hairlines; nothing floats.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final air = context.air;
    final premium = ref.watch(premiumProvider);
    final split = ref.watch(splitTunnelProvider);
    final adsEnabled =
        ref.watch(adsEnabledProvider) &&
        ref.watch(adsVisibleProvider) &&
        AdConfig.canRequestAds;

    return HorizonField(
      phase: AirPhase.idle,
      showHorizon: false,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AirLayout.wideRail),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AirLayout.gutter,
                28,
                AirLayout.gutter,
                120,
              ),
              children: [
                Text(
                  'SETTINGS',
                  style: AppTextStyles.label(color: air.steel, size: 10.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tunnel',
                  style: AppTextStyles.display(color: air.ink, size: 32),
                ),
                const SizedBox(height: 24),
                AirSection(
                  title: 'Premium',
                  rows: [
                    AirRow(
                      title: 'BULBVPN Premium',
                      subtitle: premium.isActive
                          ? 'Active · ad-free, priority relays'
                          : 'Ad-free · priority relays',
                      trailing: Text(
                        premium.isActive ? 'Manage' : 'Plans',
                        style: AppTextStyles.label(
                          color: air.accentInk,
                          size: 11,
                        ),
                      ),
                      onTap: () => _push(context, const PremiumScreen()),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                AirSection(
                  title: 'Connection',
                  rows: [
                    if (Platform.isAndroid) ...[
                      const _KillSwitchRow(),
                      AirRow(
                        title: 'Split tunneling',
                        subtitle: _routingSummary(split),
                        onTap: () => _push(context, const RoutingScreen()),
                      ),
                    ],
                    const AirRow(
                      title: 'Protocol',
                      subtitle: 'The engine negotiates the path and re-dials '
                          'when one is blocked — recommended',
                      value: 'Automatic',
                      chevron: false,
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                AirSection(
                  title: 'Relays',
                  rows: [
                    AirRow(
                      title: 'Relay sources',
                      subtitle: 'Community relays can see your traffic. '
                          'Own servers arrive with the engine.',
                      trailing: TrustBadge(
                        tier: TrustTier.bootstrap,
                        compact: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                AirSection(
                  title: 'About',
                  note: Text(
                    'BULBVPN carries your traffic through community relays and '
                    'picks the lowest latency from this device. We do not '
                    'inspect traffic through the tunnel, and we are not '
                    'responsible for how it is used or for any loss that '
                    'follows from using it.',
                    style: AppTextStyles.body(color: air.steel, size: 12.5),
                  ),
                  rows: [
                    AirRow(
                      title: 'Introduction',
                      subtitle: 'What the relay can and cannot see',
                      onTap: () => showCupertinoDialog<void>(
                        context: context,
                        barrierDismissible: true,
                        builder: (_) => const IntroductionDialog(),
                      ),
                    ),
                    AirRow(
                      title: 'Share BULBVPN',
                      subtitle: 'Copies the invite link',
                      trailing: Icon(
                        Icons.ios_share,
                        size: 18,
                        color: air.mute,
                      ),
                      onTap: () => _share(context),
                    ),
                    AirRow(
                      title: 'Privacy',
                      onTap: () => _openUrl(AppLinks.privacy),
                    ),
                    AirRow(
                      title: 'Terms',
                      onTap: () => _openUrl(AppLinks.terms),
                    ),
                    AirRow(
                      title: 'Connection log',
                      subtitle: 'Saved on this device · copy when reporting',
                      onTap: () => _push(context, const LogsScreen()),
                    ),
                    if (AppLinks.hasSupport)
                      AirRow(
                        title: 'Support',
                        subtitle: _supportSubtitle,
                        onTap: () {
                          unawaited(
                            FirebaseAnalyticsService().logSupportOpened(
                              'teleform',
                            ),
                          );
                          unawaited(_openUrl(AppLinks.supportUrl));
                        },
                      ),
                    const _VersionRow(),
                  ],
                ),
                if (adsEnabled) ...[
                  const SizedBox(height: 26),
                  Text(
                    'SPONSORED',
                    style: AppTextStyles.label(color: air.steel, size: 10.5),
                  ),
                  const SizedBox(height: 10),
                  const AdBanner(horizontalInset: 40),
                ],
                if (PrivateApp.privateBuild) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Private build. Ads and subscriptions stay off.',
                    style: AppTextStyles.monoValue(color: air.mute, size: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  static String get _supportSubtitle {
    final url = AppLinks.supportUrl.toLowerCase();
    return url.contains('t.me') || url.contains('telegram')
        ? 'Telegram · opens the chat'
        : 'Teleform · send a message';
  }

  static Future<void> _openUrl(String url) => launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );

  static Future<void> _share(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: '${AppLinks.website} — BULBVPN, censorship-proof internet'),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Invite link copied.')),
      );
  }

  String _routingSummary(SplitTunnelConfig config) {
    final count = config.packages.length;
    return switch (config.mode) {
      TunnelMode.all => 'All apps use the tunnel',
      TunnelMode.bypass =>
        count == 0
            ? 'Bypass · no apps selected yet'
            : 'Bypass · $count ${count == 1 ? 'app' : 'apps'} outside',
      TunnelMode.allow =>
        count == 0
            ? 'Only apps · none selected yet'
            : 'Only · $count ${count == 1 ? 'app' : 'apps'} inside',
    };
  }
}

/// Kill switch. Polls the native service only while it is on, so the row can
/// say "blocking traffic" after a drop instead of pretending nothing happened.
class _KillSwitchRow extends ConsumerStatefulWidget {
  const _KillSwitchRow();

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
    final air = context.air;
    final enabled = ref.watch(killSwitchProvider);
    return AirRow(
      title: 'Kill switch',
      subtitle: _blocked
          ? 'Traffic blocked — tunnel lost'
          : 'Block traffic if the tunnel drops',
      titleColor: _blocked ? air.alertInk : null,
      chevron: false,
      trailing: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Switch.adaptive(
            value: enabled,
            onChanged: (value) => unawaited(
              ref.read(killSwitchProvider.notifier).setEnabled(value),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return AirRow(
          title: 'Version',
          value: info == null ? '—' : '${info.version} (${info.buildNumber})',
          chevron: false,
          // Diagnostics stay off the surface; holding the build number opens
          // the connection log for the rare support case.
          onLongPress: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const LogsScreen()),
          ),
        );
      },
    );
  }
}
