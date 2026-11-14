import 'dart:io' show Platform;

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';
import 'package:bulbvpn/modules/core/home_region.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:bulbvpn/shared/simple/simple_card.dart';
import 'package:bulbvpn/shared/simple/simple_header.dart';
import 'package:bulbvpn/shared/simple/simple_key.dart';
import 'package:bulbvpn/shared/simple/simple_note.dart';
import 'package:bulbvpn/shared/simple/simple_section.dart';
import 'package:bulbvpn/shared/simple/simple_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Full, copyable tunnel log. This screen is available in release builds too:
/// when a connection fails on a carrier the log is the only evidence the user
/// can hand back, and hiding it behind kDebugMode made support impossible.
///
/// Pushed route, so it prints its own ground. The reading is the plate's own
/// small mono: a log is a receipt, and a receipt is not set in a display face.
class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      child: SimpleCard(
        child: LayoutBuilder(
          builder: (context, c) {
            final type = SimpleType(c.maxWidth);
            return ValueListenableBuilder<int>(
              valueListenable: Log().version,
              builder: (context, _, __) {
                final lines = Log().lines;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SimpleHeader(
                      title: 'Connection log',
                      note:
                          '${lines.length} '
                          '${lines.length == 1 ? 'line' : 'lines'} on this device',
                      onBack: () => Navigator.of(context).maybePop(),
                      trailing: lines.isEmpty
                          ? null
                          : SimpleKey(
                              label: 'Copy',
                              onTap: () => copyLogs(context, ref),
                            ),
                    ),
                    Expanded(
                      child: lines.isEmpty
                          ? _NoEvents(type: type)
                          : SelectionArea(
                              child: ListView.builder(
                                padding: EdgeInsets.only(
                                  top: type.px(18),
                                  bottom: type.px(40),
                                ),
                                itemCount: lines.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == lines.length) {
                                    return _LogFooter(
                                      type: type,
                                      onClear: () => _confirmClear(context),
                                    );
                                  }
                                  return _LogLine(
                                    line: lines[lines.length - 1 - index],
                                    type: type,
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ClearDialog(),
    );
    if (confirmed == true) Log().clearLogs();
  }
}

class _NoEvents extends StatelessWidget {
  const _NoEvents({required this.type});

  final SimpleType type;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: type.px(120)),
        child: Text(
          'No events yet.',
          textAlign: TextAlign.center,
          style: AppTextStyles.monoValue(
            color: s.inkSoft,
            size: type.tableRowMixed,
            weight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// One line of the receipt: the clock in its own slot, the message wrapped in
/// the rest of the card.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.line, required this.type});

  final String line;
  final SimpleType type;

  static const int _maxMessageChars = 400;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    final close = line.indexOf('] ');
    final stamp = close > 9 ? line.substring(1, close) : null;
    final message = close > 0 ? line.substring(close + 2) : line;
    final shown = message.length > _maxMessageChars
        ? '${message.substring(0, _maxMessageChars)}…'
        : message;
    final lower = shown.toLowerCase();
    // The red is reserved for what did not deliver. A line that says the
    // tunnel came up is a fact the card read, not a payment, so it prints in
    // the card's own ivory rather than borrowing the accent.
    final color =
        lower.contains('fail') ||
            lower.contains('error') ||
            lower.contains('exception') ||
            lower.contains('refused') ||
            lower.contains('timeout')
        ? s.error
        : lower.contains('connected') || lower.contains('success')
        ? s.ink
        : s.inkSoft;
    final time = stamp != null && stamp.length >= 19
        ? stamp.substring(11, 19)
        : stamp ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(type.px(26), 0, type.px(24), type.px(9)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: type.px(150),
            child: Text(
              time,
              style: AppTextStyles.monoValue(
                color: s.inkFaint,
                size: type.claim,
                weight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
          SizedBox(width: type.px(16)),
          Expanded(
            child: Text(
              shown,
              style: AppTextStyles.monoValue(
                color: color,
                size: type.claim,
                weight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How the log was kept, then the one key that throws it away. The destructive
/// action sits at the end of the reading, not beside the heading that describes
/// the thing it destroys.
class _LogFooter extends StatelessWidget {
  const _LogFooter({required this.type, required this.onClear});

  final SimpleType type;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SimpleNote(
          text:
              'Newest first. Saved on this device and kept across restarts; '
              'copied logs are chronological and include a device/relay header.',
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            type.px(26),
            type.px(20),
            type.px(24),
            type.px(20),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SimpleKey(label: 'Clear', onTap: onClear),
          ),
        ),
      ],
    );
  }
}

/// The confirmation on its own plate. The card does not own a modal material,
/// so the dialog is a second card laid over the first rather than a sheet of
/// something else.
class _ClearDialog extends StatelessWidget {
  const _ClearDialog();

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width * 0.08,
        vertical: 24,
      ),
      child: SimpleCard(
        child: LayoutBuilder(
          builder: (context, c) {
            final type = SimpleType(c.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SimpleSection(title: 'Clear the log'),
                SimpleNote(
                  text: 'This removes the current tunnel log from this device.',
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    type.px(26),
                    type.px(20),
                    type.px(24),
                    type.px(20),
                  ),
                  child: Row(
                    children: [
                      SimpleKey(
                        label: 'Keep',
                        onTap: () => Navigator.pop(context, false),
                      ),
                      SizedBox(width: type.px(14)),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SimpleKey(
                            label: 'Clear',
                            emphasis: true,
                            onTap: () => Navigator.pop(context, true),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not copy logs: $error')));
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
