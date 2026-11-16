import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';
import 'package:bulbvpn/modules/core/relay_verdict.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/home_composition.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/layout/navbar/defyx_navbar.dart';
import 'package:bulbvpn/shared/simple/simple_card.dart';
import 'package:bulbvpn/shared/simple/simple_key.dart';
import 'package:bulbvpn/shared/simple/simple_note.dart';
import 'package:bulbvpn/shared/simple/simple_section.dart';
import 'package:bulbvpn/shared/simple/simple_term_row.dart';

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

                    SimpleCard(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Status section header
                            SimpleSection(
                              title: 'STATUS',
                              disclosure: live ? 'CONNECTED' : 'DISCONNECTED',
                              disclosureSemantics:
                                  live
                                      ? 'Connection status: connected'
                                      : 'Connection status: disconnected',
                              proven: live,
                            ),
                            const SizedBox(height: 16),

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
                            SimpleNote(
                              text: state.statusDetail,
                              failed: !live && state.phase.isFault,
                            ),
                            const SizedBox(height: 24),

                            // Session timer (only when connected)
                            if (live) ...[
                              SimpleSection(
                                title: 'SESSION',
                                disclosure: state.clockLabel,
                                disclosureSemantics:
                                    'Session duration ${state.clockLabel}',
                              ),
                              const SizedBox(height: 16),
                              Text(
                                state.clockLabel,
                                style: AppTextStyles.metric(
                                  color: s.connected,
                                  size: 32,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Exit IP
                            if (state.exitIp.isNotEmpty) ...[
                              SimpleTermRow(
                                title: 'EXIT NODE',
                                sub: state.exitLocation,
                                value: state.exitIp,
                                onTap: onScratch,
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Stats row
                            Row(
                              children: [
                                Expanded(child: _StatCell('DOWN', state.downLabel, s)),
                                Expanded(child: _StatCell('UP', state.upLabel, s)),
                                Expanded(child: _StatCell('TRAFFIC', state.trafficLabel, s)),
                                Expanded(child: _StatCell('PING', state.pingLabel, s)),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Relay list header
                            if (rows.isNotEmpty) ...[
                              SimpleSection(
                                title: 'RELAYS',
                                disclosure: '${rows.length}',
                                disclosureSemantics: '${rows.length} relays available',
                              ),
                              const SizedBox(height: 12),
                              ...rows.asMap().entries.map((entry) {
                                final row = entry.value;
                                final failed = row.verdict == RelayVerdict.blocked;
                                return SimpleTermRow(
                                  title: row.destination,
                                  sub: row.measured,
                                  value: row.verdict.word,
                                  failed: failed,
                                  onTap: onOpenRelays,
                                );
                              }),
                              const SizedBox(height: 24),
                            ],

                            // Connect button - the only primary action
                            SimpleKey(
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
                              emphasis: live,
                              onTap: state.phase != AirPhase.closing ? onConnect : null,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Bottom navigation bar
            DefyxNavBar(),

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

/// A stat cell: a label above a monospace value.
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
