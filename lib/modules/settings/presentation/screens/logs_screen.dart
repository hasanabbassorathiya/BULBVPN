import 'dart:io' show Platform;

import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/home_region.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/shared/air/air_layout.dart';
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
    final air = context.air;
    return Scaffold(
      backgroundColor: air.ground,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AirLayout.wideRail),
            child: ValueListenableBuilder<int>(
              valueListenable: Log().version,
              builder: (context, _, __) {
                final lines = Log().lines;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          Expanded(
                            child: Text(
                              'Connection logs',
                              style: AppTextStyles.title(
                                color: air.ink,
                                size: 19,
                              ),
                            ),
                          ),
                          if (lines.isNotEmpty) ...[
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: IconButton(
                                tooltip: 'Copy all logs',
                                onPressed: () => copyLogs(context, ref),
                                icon: const Icon(Icons.copy_all, size: 20),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _confirmClear(context),
                              child: const Text('Clear'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: air.surface,
                          border: Border(
                            top: BorderSide(color: air.hairline),
                          ),
                        ),
                        child: lines.isEmpty
                            ? Center(
                                child: Text(
                                  'No events yet.',
                                  style: AppTextStyles.body(
                                    color: air.steel,
                                    size: 14,
                                  ),
                                ),
                              )
                            : SelectionArea(
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    AirLayout.gutter,
                                    16,
                                    AirLayout.gutter,
                                    28,
                                  ),
                                  itemCount: lines.length + 1,
                                  itemBuilder: (context, index) {
                                    if (index == lines.length) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          top: 18,
                                        ),
                                        child: Text(
                                          'Newest first. Saved on this device '
                                          'and kept across restarts; copied '
                                          'logs are chronological and include '
                                          'a device/relay header.',
                                          style: AppTextStyles.monoValue(
                                            color: air.mute,
                                            size: 11,
                                          ),
                                        ),
                                      );
                                    }
                                    return _LogLine(
                                      line: lines[lines.length - 1 - index],
                                    );
                                  },
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final air = context.air;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Clear logs?',
          style: AppTextStyles.title(color: air.ink, size: 18),
        ),
        content: Text(
          'This removes the current tunnel log from this device.',
          style: AppTextStyles.body(color: air.steel, size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: air.alertInk),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) Log().clearLogs();
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.line});

  final String line;

  static const int _maxMessageChars = 400;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final close = line.indexOf('] ');
    final stamp = close > 9 ? line.substring(1, close) : null;
    final message = close > 0 ? line.substring(close + 2) : line;
    final shown = message.length > _maxMessageChars
        ? '${message.substring(0, _maxMessageChars)}…'
        : message;
    final lower = shown.toLowerCase();
    final color = lower.contains('fail') ||
            lower.contains('error') ||
            lower.contains('exception') ||
            lower.contains('refused') ||
            lower.contains('timeout')
        ? air.alertInk
        : lower.contains('connected') || lower.contains('success')
        ? air.connectedInk
        : air.steel;
    final time = stamp != null && stamp.length >= 19
        ? stamp.substring(11, 19)
        : stamp ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              time,
              style: AppTextStyles.monoValue(color: air.ink, size: 10),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              shown,
              style: TextStyle(
                fontFamily: AppTextStyles.mono,
                fontSize: 11,
                height: 1.6,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
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
          content: Text('Copied $count log lines. Paste them into the chat.'),
        ),
      );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not copy logs: $error')),
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
