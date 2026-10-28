import 'dart:io' show Platform;

import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/home_region.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Full, copyable tunnel log. This screen is available in release builds too:
/// when a connection fails on a carrier the log is the only evidence the user
/// can hand back, and hiding it behind kDebugMode made support impossible.
class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text(
          'Connection logs',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy all logs',
            onPressed: () => copyLogs(context, ref),
            icon: const Icon(Icons.copy_all_rounded, size: 21),
          ),
          IconButton(
            tooltip: 'Clear logs',
            onPressed: () => _confirmClear(context),
            icon: const Icon(Icons.delete_outline_rounded, size: 21),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: Log().version,
        builder: (context, _, __) {
          final lines = Log().lines;
          if (lines.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No tunnel logs yet.\nConnect once, then come back here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.mute,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            );
          }
          return SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              // Newest first: the reason a connection just failed is the line
              // the user needs, without scrolling through a long session.
              itemCount: lines.length + 1,
              itemBuilder: (context, index) {
                if (index == lines.length) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 18, bottom: 8),
                    child: Text(
                      'Copied logs are chronological and include a device/relay header. Select any line to copy part of it.',
                      style: TextStyle(
                        color: AppColors.mute,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  );
                }
                final line = lines[lines.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    line,
                    style: AppTextStyles.logLine(color: AppColors.steel),
                  ),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.amber,
                    foregroundColor: AppColors.canvas,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => copyLogs(context, ref),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text(
                    'Copy all logs',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Copy the last 200 lines',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.raised,
                  foregroundColor: AppColors.steel,
                  minimumSize: const Size(46, 46),
                ),
                onPressed: () => copyLogs(context, ref, recentOnly: true),
                icon: const Icon(Icons.history_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Clear logs?',
          style: TextStyle(color: AppColors.ink),
        ),
        content: const Text(
          'This removes the current tunnel log from this device.',
          style: TextStyle(color: AppColors.steel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep', style: TextStyle(color: AppColors.steel)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) Log().clearLogs();
  }
}

/// Copies a self-contained support blob: device/app context, the relay that
/// actually carries the session, the native tunnel snapshot, then the log.
///
/// The log itself is sanitized on write ([Log.addLog]) and never contains the
/// VPN Gate hostname, catalog URLs, or credentials. Relay IPs are kept: they
/// are the single most useful fact when a carrier-specific relay fails.
Future<void> copyLogs(
  BuildContext context,
  WidgetRef ref, {
  bool recentOnly = false,
}) async {
  final connection = ref.read(connectionStateProvider);
  final relay = ref.read(connectedRelayProvider);
  final app = await _appVersion();
  final native = await _nativeSnapshot();
  final relayRegion = relay?.countryCode ?? '';
  final home = HomeRegion.countryCode ?? 'unknown';
  final ipv6 = Platform.isAndroid
      ? 'blocked (VpnService IPv4-only tunnel)'
      : 'captured and dropped (no IPv6 leak)';
  final int count;
  final String body;
  if (recentOnly) {
    final recent = Log().recent(200);
    count = recent.length;
    body = recent.reversed.join('\n');
  } else {
    count = Log().lines.length;
    body = Log().getLogs();
  }
  final header = <String>[
    'BULBVPN diagnostics',
    'time: ${DateTime.now().toIso8601String()}',
    'app: $app',
    'platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'status: ${connection.status.name}',
    'relay: ${relay == null ? 'none' : '${relay.displayName} (${relay.code.isEmpty ? '??' : relay.code}) ${relay.dial}'}',
    'region: device-locale=${HomeRegion.locale} tz=${HomeRegion.timezone} '
        'home=$home relay=${relayRegion.isEmpty ? 'unknown' : relayRegion} '
        'same-country-exit=${relayRegion.isNotEmpty && HomeRegion.isHome(relayRegion)}',
    'dns: resolved inside the tunnel (all-traffic match domain)',
    'region-note: tunnel DNS, IPv6 and exit country are controlled here '
        '(ipv6=$ipv6); Google can also use account country, GPS and timezone, '
        'which no VPN changes',
    if (native.isNotEmpty) native,
    '--- logs ($count lines${recentOnly ? ', newest 200' : ''}) ---',
  ];
  final text = '${header.join('\n')}\n$body';
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Copied $count log lines. Paste them into the chat.',
            style: const TextStyle(color: AppColors.ink, fontSize: 13),
          ),
          backgroundColor: AppColors.raised,
          behavior: SnackBarBehavior.floating,
        ),
      );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not copy logs: $error',
          style: const TextStyle(color: AppColors.ink, fontSize: 13),
        ),
        backgroundColor: AppColors.raised,
      ),
    );
  }
}

Future<String> _appVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber} (${info.packageName})';
  } catch (_) {
    return 'unknown';
  }
}

/// Android exposes the live service snapshot; iOS/macOS return a down status
/// because the packet tunnel owns the session. Omit an empty snapshot so the
/// copied blob stays clean.
Future<String> _nativeSnapshot() async {
  try {
    final diag = await SoftEtherVpn.diagnostics();
    if (diag != null) {
      final reason = (diag['reason'] as String?) ?? '';
      final out = <String>[
        'native-service: running=${diag['running']} tunnelUp=${diag['tunnelUp']} '
            'host=${diag['host']} reason=${reason.isEmpty ? 'none' : reason} '
            'carrierUp=${diag['carrierUp']} effectiveIp=${diag['effectiveIp']} '
            'connectedForMs=${diag['connectedForMs']} protected=${diag['protectedSockets']} '
            'client=${diag['clientAlive']} tunFd=${diag['tunFd']}',
      ];
      final native =
          (diag['nativeLog'] as List?)
              ?.map((line) => line.toString())
              .toList() ??
          const <String>[];
      if (native.isNotEmpty) {
        out.add('--- native service log (${native.length} lines) ---');
        out.addAll(native);
      }
      return out.join('\n');
    }
  } catch (_) {}
  try {
    final status = await SoftEtherVpn.status();
    if (!status.running &&
        status.host.isEmpty &&
        status.reason.isEmpty &&
        status.effectiveIp.isEmpty) {
      return '';
    }
    return 'native: running=${status.running} host=${status.host} '
        'reason=${status.reason.isEmpty ? 'none' : status.reason} '
        'carrierUp=${status.carrierUp} effectiveIp=${status.effectiveIp}';
  } catch (_) {
    return '';
  }
}
