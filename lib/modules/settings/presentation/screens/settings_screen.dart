import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
import 'package:bulbvpn/modules/monetization/ad_banner.dart';
import 'package:bulbvpn/modules/monetization/ad_config.dart';
import 'package:bulbvpn/modules/monetization/ad_service.dart';
import 'package:bulbvpn/modules/monetization/ads_remote_config.dart';
import 'package:bulbvpn/modules/monetization/private_app.dart';
import 'package:bulbvpn/modules/settings/presentation/screens/logs_screen.dart';
import 'package:bulbvpn/shared/layout/main_screen_background.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Connection details, tunnel logs, and the product disclaimer.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionStateProvider);
    final connectedRelay = ref.watch(connectedRelayProvider);
    final picked = ref.watch(selectedServerProvider);
    final live = connection.status == ConnectionStatus.connected;
    final adsEnabled = ref.watch(adsEnabledProvider) && AdConfig.canRequestAds;

    return MainScreenBackground(
      connectionStatus: connection.status,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
          children: [
            Text('TUNNEL', style: AppTextStyles.microLabel()),
            const SizedBox(height: 8),
            const Text(
              'Info',
              style: TextStyle(
                fontSize: 32,
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 22),
            _Card(
              child: Column(
                children: [
                  _Row(label: 'Status', value: _statusLabel(connection.status)),
                  _Row(
                    label: 'Relay',
                    value: live
                        ? (connectedRelay?.displayName ?? 'Connected relay')
                        : (picked?.publicLabel ?? 'Fastest available'),
                  ),
                  _Row(
                    label: 'Downloaded',
                    value: _formatBytes(connection.totalDownload),
                  ),
                  const _Row(label: 'Build', value: 'Private'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Logs are a debugging tool; store builds ship without them.
            if (kDebugMode) ...[
              Text('DIAGNOSTICS', style: AppTextStyles.microLabel()),
              const SizedBox(height: 8),
              _Card(
                child: InkWell(
                  onTap: () => _openLogs(context),
                  child: ValueListenableBuilder<int>(
                    valueListenable: Log().version,
                    builder: (_, __, ___) {
                      final count = Log().lines.length;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 13, 6, 13),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.receipt_long_rounded,
                              size: 20,
                              color: AppColors.amber,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Connection logs',
                                    style: TextStyle(
                                      color: AppColors.ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    count == 0
                                        ? 'No entries yet · tap to open'
                                        : '$count lines · newest first',
                                    style: const TextStyle(
                                      color: AppColors.mute,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy logs',
                              onPressed: () => copyLogs(context, ref),
                              icon: const Icon(
                                Icons.copy_rounded,
                                size: 19,
                                color: AppColors.steel,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: AppColors.mute,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (adsEnabled) ...[
              Text('SPONSORED', style: AppTextStyles.microLabel()),
              const SizedBox(height: 8),
              const AdBanner(horizontalInset: 40),
              const SizedBox(height: 18),
            ],
            Text('ABOUT', style: AppTextStyles.microLabel()),
            const SizedBox(height: 8),
            const _Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'BULBVPN opens a private tunnel and picks the lowest latency from this device. We do not inspect traffic through the tunnel, and we are not responsible for how it is used or for any loss that follows from using it.',
                  style: TextStyle(
                    color: AppColors.steel,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              child: Column(
                children: [
                  _Link(title: 'Privacy', url: AppLinks.privacy),
                  _Link(title: 'Terms', url: AppLinks.terms),
                  if (adsEnabled) const _AdPrivacyLink(),
                  _Link(
                    title: 'Support',
                    url: 'mailto:${AppLinks.contactEmail}',
                  ),
                  const _VersionRow(),
                ],
              ),
            ),
            if (PrivateApp.privateBuild) ...[
              const SizedBox(height: 14),
              const Text(
                'Private build. Ads and subscriptions stay off.',
                style: TextStyle(color: AppColors.mute, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openLogs(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LogsScreen()));
  }

  String _statusLabel(ConnectionStatus status) {
    return switch (status) {
      ConnectionStatus.connected => 'Connected',
      ConnectionStatus.connecting ||
      ConnectionStatus.loading ||
      ConnectionStatus.analyzing => 'Connecting',
      ConnectionStatus.disconnecting => 'Disconnecting',
      ConnectionStatus.error => 'Failed',
      ConnectionStatus.noInternet => 'Offline',
      ConnectionStatus.disconnected => 'Standby',
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: child,
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(label, style: AppTextStyles.microLabel()),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.ink, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  final String title;
  final String? url;
  final VoidCallback? onTap;
  const _Link({required this.title, this.url, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:
          onTap ??
          () =>
              launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: AppColors.ink, fontSize: 16),
              ),
            ),
            Icon(
              onTap == null ? Icons.open_in_new_rounded : Icons.tune_rounded,
              size: 16,
              color: AppColors.mute,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown only where Google requires a privacy options entry point (EEA, UK,
/// Switzerland). Tapping it reopens the consent form.
class _AdPrivacyLink extends StatelessWidget {
  const _AdPrivacyLink();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AdService.needsPrivacyOptions(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return _Link(
          title: 'Ad privacy options',
          onTap: AdService.showPrivacyOptions,
        );
      },
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
        final version = info == null
            ? '—'
            : '${info.version} (${info.buildNumber})';
        return _Row(label: 'Version', value: version);
      },
    );
  }
}
