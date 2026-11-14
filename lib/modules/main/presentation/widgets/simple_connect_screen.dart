import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';
import 'package:bulbvpn/modules/core/relay_verdict.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/home_composition.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';

/// The simple connect face: a status word, a timer, a single button, and the
/// exit IP. Nothing moves unless bytes moved.
class SimpleConnectScreen extends StatelessWidget {
  const SimpleConnectScreen({
    super.key,
    required this.state,
    required this.rows,
    required this.onConnect,
    required this.onOpenRelays,
    required this.onScratch,
    this.banner,
  });

  final HomeViewState state;
  final List<RelayRow> rows;
  final VoidCallback onConnect;
  final VoidCallback onOpenRelays;
  final VoidCallback onScratch;
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    final live = state.live;

    return Scaffold(
      backgroundColor: s.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'BULB VPN',
                style: AppTextStyles.title(
                  color: s.ink,
                  size: 20,
                  weight: FontWeight.w700,
                ),
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),

                    // Status word
                    Text(
                      state.statusTitle,
                      style: AppTextStyles.display(
                        color: live ? s.connected : s.ink,
                        size: 40,
                        weight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Status detail
                    Text(
                      state.statusDetail,
                      style: AppTextStyles.body(
                        color: s.inkSoft,
                        size: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 32),

                    // Session timer (only when connected)
                    if (live) ...[
                      Text(
                        'SESSION',
                        style: AppTextStyles.label(
                          color: s.inkFaint,
                          size: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        state.clockLabel,
                        style: AppTextStyles.metric(
                          color: s.connected,
                          size: 32,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                    ],

                    // Exit IP
                    if (state.exitIp.isNotEmpty) ...[
                      _ExitIpRow(
                        ip: state.exitIp,
                        location: state.exitLocation,
                        onTap: onScratch,
                        simple: s,
                      ),
                      const SizedBox(height: 32),
                    ],

                    // Stats row
                    _StatsRow(
                      down: state.downLabel,
                      up: state.upLabel,
                      traffic: state.trafficLabel,
                      ping: state.pingLabel,
                      simple: s,
                    ),

                    const SizedBox(height: 40),

                    // Relay list header
                    if (rows.isNotEmpty) ...[
                      Text(
                        'RELAYS',
                        style: AppTextStyles.label(
                          color: s.inkFaint,
                          size: 10,
                        ),
                        textAlign: TextAlign.left,
                      ),
                      const SizedBox(height: 12),
                      ...rows.asMap().entries.map((entry) {
                        final i = entry.key;
                        final row = entry.value;
                        return _RelayRow(
                          index: i + 1,
                          row: row,
                          onTap: onOpenRelays,
                          simple: s,
                        );
                      }),
                      const SizedBox(height: 32),
                    ],

                    // Connect button - the only primary action
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _ConnectButton(
                        label: state.connectStage != null
                            ? (state.busyWitness ?? 'DIALLING')
                            : switch (state.phase) {
                                AirPhase.connected ||
                                    AirPhase.verifying =>
                                  'TAP TO DISCONNECT',
                                AirPhase.connecting ||
                                    AirPhase.preparing =>
                                  'TAP TO CANCEL',
                                AirPhase.closing =>
                                  'RELEASING',
                                _ => 'TAP TO CONNECT',
                              },
                        busy: state.connectStage != null,
                        enabled: state.phase != AirPhase.closing,
                        connected: live,
                        onTap: onConnect,
                        simple: s,
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Ad banner (stays at the bottom)
            if (banner != null) banner!,
          ],
        ),
      ),
    );
  }
}

/// One relay row in the simple connect face.
class RelayRow {
  const RelayRow({
    required this.rank,
    required this.destination,
    required this.measured,
    required this.verdict,
  });

  final String rank;
  final String destination;
  final String measured;
  final RelayVerdict verdict;
}

class _ExitIpRow extends StatelessWidget {
  const _ExitIpRow({
    required this.ip,
    required this.location,
    required this.onTap,
    required this.simple,
  });

  final String ip;
  final String? location;
  final VoidCallback onTap;
  final SimpleColors simple;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: simple.surface,
          border: Border.all(color: simple.hairline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.launch, color: simple.connected, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EXIT NODE',
                    style: AppTextStyles.label(
                      color: simple.inkFaint,
                      size: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ip,
                    style: AppTextStyles.monoValue(
                      color: simple.ink,
                      size: 14,
                    ),
                  ),
                  if (location != null && location!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      location!,
                      style: AppTextStyles.body(
                        color: simple.inkSoft,
                        size: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.copy,
              color: simple.inkSoft,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.down,
    required this.up,
    required this.traffic,
    required this.ping,
    required this.simple,
  });

  final String down;
  final String up;
  final String traffic;
  final String ping;
  final SimpleColors simple;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCell('DOWN', down, simple)),
        Expanded(child: _StatCell('UP', up, simple)),
        Expanded(child: _StatCell('TRAFFIC', traffic, simple)),
        Expanded(child: _StatCell('PING', ping, simple)),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(this.label, this.value, this.simple);

  final String label;
  final String value;
  final SimpleColors simple;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppTextStyles.label(
            color: simple.inkFaint,
            size: 10,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.monoValue(
            color: simple.inkSoft,
            size: 13,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _RelayRow extends StatelessWidget {
  const _RelayRow({
    required this.index,
    required this.row,
    required this.onTap,
    required this.simple,
  });

  final int index;
  final RelayRow row;
  final VoidCallback onTap;
  final SimpleColors simple;

  @override
  Widget build(BuildContext context) {
    final failed = row.verdict == RelayVerdict.blocked;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: failed ? simple.error.withValues(alpha: 0.08) : simple.surface,
          border: Border.all(
            color: failed ? simple.error : simple.hairline,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(
              index.toString().padLeft(2, '0'),
              style: AppTextStyles.monoValue(
                color: failed ? simple.error : simple.inkFaint,
                size: 13,
                weight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.destination,
                    style: AppTextStyles.body(
                      color: failed ? simple.error : simple.ink,
                      size: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    row.measured,
                    style: AppTextStyles.monoValue(
                      color: simple.inkSoft,
                      size: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              row.verdict.word,
              style: AppTextStyles.monoValue(
                color: failed
                    ? simple.error
                    : row.verdict == RelayVerdict.carried
                    ? simple.connected
                    : simple.inkFaint,
                size: 11,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.label,
    required this.busy,
    required this.enabled,
    required this.connected,
    required this.onTap,
    required this.simple,
  });

  final String label;
  final bool busy;
  final bool enabled;
  final bool connected;
  final VoidCallback onTap;
  final SimpleColors simple;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? (connected ? simple.connected : simple.primary)
        : simple.inkFaint;
    final textColor = enabled ? simple.connectedInk : simple.inkFaint;

    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: AppTextStyles.body(
                color: textColor,
                size: 15,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
