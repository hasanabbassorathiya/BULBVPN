import 'package:bulbvpn/app/links.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/server_catalog.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
import 'package:bulbvpn/modules/monetization/private_app.dart';
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
    final relay = ref.watch(softEtherHostProvider);
    final picked = ref.watch(selectedServerProvider);
    final catalog = ref.watch(serversProvider).valueOrNull ?? const <VpnServer>[];

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
                    value: relay != null
                        ? publicRelayLabel(relay, catalog)
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
            if (kDebugMode) ...[
              const SizedBox(height: 18),
              Text('LOGS', style: AppTextStyles.microLabel()),
              const SizedBox(height: 8),
              _Card(
                child: ValueListenableBuilder<int>(
                  valueListenable: Log().version,
                  builder: (_, __, ___) {
                    final lines = Log().recent(40);
                    if (lines.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No tunnel logs yet.',
                          style: TextStyle(color: AppColors.mute, fontSize: 13),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in lines.take(12))
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            child: Text(
                              redactRelayDetail(line),
                              style: AppTextStyles.logLine(
                                color: AppColors.steel,
                              ),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: Log().clearLogs,
                            child: const Text(
                              'Clear',
                              style: TextStyle(color: AppColors.amber),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text('ABOUT', style: AppTextStyles.microLabel()),
            const SizedBox(height: 8),
            const _Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'BULBVPN opens a private tunnel and picks the lowest latency from this device. We do not inspect traffic through the tunnel, and we are not responsible for how it is used or for any loss that follows from using it.',
                  style: TextStyle(color: AppColors.steel, fontSize: 13, height: 1.45),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              child: Column(
                children: [
                  _Link(title: 'Privacy', url: AppLinks.privacy),
                  _Link(title: 'Terms', url: AppLinks.terms),
                  _Link(title: 'Support', url: 'mailto:${AppLinks.contactEmail}'),
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
  final String url;
  const _Link({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(color: AppColors.ink, fontSize: 16))),
            const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.mute),
          ],
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
        final version = info == null ? '—' : '${info.version} (${info.buildNumber})';
        return _Row(label: 'Version', value: version);
      },
    );
  }
}
