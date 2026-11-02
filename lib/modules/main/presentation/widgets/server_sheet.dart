import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/reality/reality_engine.dart';
import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/server_catalog.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/main/application/server_grouping.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/shared/air/trust_badge.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:bulbvpn/shared/widgets/staggered_in.dart';

/// Currently picked server (null = auto / test config).
final selectedServerProvider = StateProvider<VpnServer?>((ref) => null);

Future<void> showServerSheet(BuildContext context) {
  final air = context.air;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: air.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: const ServerSheet(),
          ),
        ),
      ),
    ),
  );
}

class ServerSheet extends ConsumerStatefulWidget {
  const ServerSheet({super.key});

  @override
  ConsumerState<ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends ConsumerState<ServerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Opening the sheet is a fresh look at the relay list; re-measure if the
    // last sweep is old enough. Runs post-frame so the catalog has loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPings());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// A live or starting tunnel owns the radio and the routing table. A probe
  /// measured through it would describe the tunnel, not the carrier path, and
  /// the sweep would compete with the handshake. Measure only while idle.
  bool get _canMeasure {
    final status = ref.read(connectionStateProvider).status;
    return status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error ||
        status == ConnectionStatus.noInternet;
  }

  void _refreshPings() {
    if (!mounted || !_canMeasure) return;
    final servers = ref.read(serversProvider).valueOrNull;
    if (servers == null || servers.isEmpty) return;
    unawaited(ref.read(serverPingProvider.notifier).ensureFresh(servers));
  }

  Future<void> _pingAll() async {
    if (!_canMeasure) return;
    final servers = ref.read(serversProvider).valueOrNull;
    if (servers == null || servers.isEmpty) return;
    await ref.read(serverPingProvider.notifier).pingAll(servers);
  }

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final serversAsync = ref.watch(serversProvider);
    final selected = ref.watch(selectedServerProvider);
    final pingState = ref.watch(serverPingProvider);
    final reality = ref.watch(realitySettingsProvider);
    final realitySupported = ref.watch(realitySupportedProvider);
    final realityRelays =
        ref.watch(realityRelaysProvider).valueOrNull ?? const <RealityRelay>[];

    ref.listen(serversProvider, (_, next) {
      if (next.valueOrNull?.isNotEmpty == true) _refreshPings();
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: air.hairlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Relays',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.title(color: air.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      serversAsync.maybeWhen(
                        data: (servers) {
                          if (servers.isEmpty) return 'Loading catalog';
                          // The sweep streams: show how many relays have
                          // answered instead of pretending it is all-or-nothing.
                          final measured = pingState.byIp.values
                              .where((p) => p.status != PingStatus.pending)
                              .length;
                          final progress = pingState.probing
                              ? ' · $measured/${servers.length} measured'
                              : '';
                          return '${servers.length} relays · '
                              '${_countryLabel(_countryCount(servers))}'
                              '$progress';
                        },
                        orElse: () => 'Loading catalog',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: air.steel, size: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Ping all — real device latency, not the server-reported ms.
              if (MediaQuery.sizeOf(context).width < 380)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    onPressed: pingState.probing ? null : _pingAll,
                    padding: EdgeInsets.zero,
                    tooltip: 'Ping all',
                    icon: pingState.probing
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: air.accent,
                            ),
                          )
                        : Icon(Icons.speed, size: 20, color: air.accent),
                  ),
                )
              else
                TextButton.icon(
                  onPressed: pingState.probing ? null : _pingAll,
                  icon: pingState.probing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: air.accent,
                          ),
                        )
                      : Icon(Icons.speed, size: 18, color: air.accent),
                  label: Text(
                    pingState.probing ? 'Measuring' : 'Ping all',
                    style: AppTextStyles.body(
                      color: air.accentInk,
                      size: 13,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  padding: EdgeInsets.zero,
                  tooltip: 'Close',
                  icon: Icon(Icons.close, color: air.steel, size: 22),
                ),
              ),
            ],
          ),
        ),
        // The trust contract stays on screen while people pick; it is never a
        // one-time dialog they can dismiss and forget.
        const _BootstrapNotice(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              style: AppTextStyles.body(color: air.ink, size: 14),
              decoration: InputDecoration(
                hintText: 'Search country',
                hintStyle: AppTextStyles.body(color: air.mute, size: 14),
                prefixIcon: Icon(Icons.search, color: air.steel, size: 20),
                prefixIconConstraints: const BoxConstraints(minWidth: 42),
                filled: true,
                fillColor: air.raised,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: serversAsync.when(
            loading: () => const _ServerSkeletons(),
            error: (e, _) => _SheetMessage(
              title: 'Catalog unavailable',
              detail: 'Check the connection and try again.',
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(serversProvider),
            ),
            data: (servers) {
              if (servers.isEmpty) {
                return _SheetMessage(
                  title: 'No relays measured yet',
                  detail: 'Pull to refresh.',
                  onRefresh: _pingAll,
                );
              }
              final measuredByIp = pingState.byIp;
              final matching = _query.isEmpty
                  ? servers
                  : servers
                        .where(
                          (s) =>
                              s.countryLong.toLowerCase().contains(_query) ||
                              s.countryShort.toLowerCase().contains(_query) ||
                              s.displayCountry.toLowerCase().contains(_query),
                        )
                        .toList();
              final matchingReality = !realitySupported
                  ? const <RealityRelay>[]
                  : (_query.isEmpty
                        ? realityRelays
                        : realityRelays
                              .where(
                                (r) =>
                                    r.countryName.toLowerCase().contains(
                                      _query,
                                    ) ||
                                    r.countryCode.toLowerCase().contains(
                                      _query,
                                    ) ||
                                    r.city.toLowerCase().contains(_query),
                              )
                              .toList());
              if (matching.isEmpty && matchingReality.isEmpty) {
                return const _SheetMessage(
                  title: 'No servers match',
                  detail: 'Try another country.',
                );
              }
              // Grouping is the ordering promise: countries themselves are
              // ranked by their fastest measured relay, so the country with
              // the lowest ping sits on top.
              final groups = groupServersByCountry(matching, measuredByIp);
              final minPing = groups
                  .map((g) => g.bestPing?.ms)
                  .whereType<int>()
                  .fold<int>(
                    0,
                    (best, ms) => best == 0 || ms < best ? ms : best,
                  );
              final fastest = _fastestNow(matching, measuredByIp);
              // The fast list repeats relays from the country sections, so it
              // has to name them the same way those sections do.
              final relayNumbers = <String, int>{
                for (final group in groups)
                  for (var i = 0; i < group.servers.length; i++)
                    group.servers[i].ip: i + 1,
              };
              final entries = <_Entry>[
                if (realitySupported) ...[
                  const _SectionEntry('Censorship-resistant'),
                  _RealitySwitchEntry(enabled: reality.enabled),
                  if (reality.enabled) ...[
                    _RealityAutoEntry(
                      selected: reality.selectedId == null,
                      count: matchingReality.length,
                    ),
                    for (final relay in matchingReality)
                      _RealityEntry(
                        relay: relay,
                        selected: reality.selectedId == relay.id,
                      ),
                    const _RealityNoticeEntry(),
                  ],
                ],
                const _AutoEntry(),
                if (fastest.isNotEmpty) ...[
                  const _SectionEntry('Fastest now'),
                  for (final server in fastest)
                    _FastestEntry(server, relayNumbers[server.ip] ?? 1),
                ],
                if (matching.isNotEmpty) const _SectionEntry('Bootstrap'),
                for (final group in groups) ...[
                  _CountryEntry(group, minPing),
                  for (var i = 0; i < group.servers.length; i++)
                    _ServerEntry(group.servers[i], i + 1),
                ],
              ];
              return RefreshIndicator(
                color: air.accent,
                backgroundColor: air.raised,
                onRefresh: _pingAll,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    final row = switch (entry) {
                      _RealitySwitchEntry(:final enabled) => _RealitySwitch(
                        enabled: enabled,
                        onChanged: (value) => unawaited(
                          ref
                              .read(realitySettingsProvider.notifier)
                              .setEnabled(value),
                        ),
                      ),
                      _RealityAutoEntry(:final selected, :final count) =>
                        _RelayRow(
                          code: 'AUTO',
                          title: 'Auto',
                          subtitle:
                              'Ranked by success on this network'
                              '${count > 0 ? ' · $count relays' : ''}',
                          latency: '',
                          selected: selected,
                          onTap: () => _pickReality(null),
                        ),
                      _RealityEntry(:final relay, :final selected) => _RelayRow(
                        code: relay.countryCode.isEmpty
                            ? '—'
                            : relay.countryCode,
                        title: relay.city.isEmpty
                            ? relay.countryName
                            : '${relay.city}, ${relay.countryName}',
                        subtitle: relay.endpoint,
                        latency: '',
                        selected: selected,
                        badge: const TrustBadge(
                          tier: TrustTier.community,
                          compact: true,
                        ),
                        onTap: () => _pickReality(relay.id),
                      ),
                      _RealityNoticeEntry() => const _RealityNotice(),
                      _AutoEntry() => _RelayRow(
                        code: 'AUTO',
                        title: 'Auto',
                        subtitle: 'Fastest measured relay',
                        latency: '',
                        selected: selected == null && !reality.usable,
                        onTap: () {
                          ref.read(selectedServerProvider.notifier).state =
                              null;
                          Navigator.maybePop(context);
                        },
                      ),
                      _SectionEntry(:final label) => _SectionHeader(label),
                      _FastestEntry(:final server, :final number) => _RelayRow(
                        code: _codeFor(server),
                        title: 'Relay $number',
                        subtitle:
                            '${server.publicLabel} · ${server.speedMbps} Mbps',
                        latency: _latencyLabel(measuredByIp[server.ip], false),
                        latencyColor: _latencyColor(
                          measuredByIp[server.ip],
                          air,
                        ),
                        latencySize: 13,
                        badge: TrustBadge(
                          tier: server.trustTier,
                          compact: true,
                        ),
                        selected: selected?.ip == server.ip,
                        onTap: () => _pick(server, selected),
                      ),
                      _CountryEntry(:final group, :final minPing) =>
                        _CountryHeader(group: group, minPing: minPing),
                      _ServerEntry(:final server, :final number) => _RelayRow(
                        code: _codeFor(server),
                        title: 'Relay $number',
                        subtitle:
                            '${server.speedMbps} Mbps · '
                            '${server.numVpnSessions} sessions',
                        latency: _latencyLabel(measuredByIp[server.ip], false),
                        latencyColor: _latencyColor(
                          measuredByIp[server.ip],
                          air,
                        ),
                        latencySize: 12,
                        selected: selected?.ip == server.ip,
                        onTap: () => _pick(server, selected),
                      ),
                    };
                    return StaggeredIn(
                      delayMs: (i * 24).clamp(0, 320),
                      offset: 8,
                      child: row,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _pick(VpnServer server, VpnServer? selected) {
    final notifier = ref.read(selectedServerProvider.notifier);
    // Tapping the current pick returns to auto.
    notifier.state = selected?.ip == server.ip ? null : server;
    // A bootstrap pick is an explicit route. Leaving the opt-in REALITY engine
    // on would silently override the country the user just chose.
    final reality = ref.read(realitySettingsProvider.notifier);
    unawaited(reality.select(null));
    unawaited(reality.setEnabled(false));
    Navigator.maybePop(context);
  }

  void _pickReality(String? relayId) {
    final reality = ref.read(realitySettingsProvider.notifier);
    unawaited(reality.select(relayId));
    ref.read(selectedServerProvider.notifier).state = null;
    Navigator.maybePop(context);
  }
}

String _codeFor(VpnServer server) {
  final code = server.countryShort.trim().toLowerCase();
  return code.length == 2 ? code : '—';
}

List<VpnServer> _fastestNow(
  List<VpnServer> servers,
  Map<String, ServerPing> byIp,
) {
  final measured = servers.where((s) => byIp[s.ip]?.status == PingStatus.ok);
  final sorted = measured.toList()
    ..sort((a, b) => byIp[a.ip]!.ms.compareTo(byIp[b.ip]!.ms));
  return sorted.take(3).toList();
}

String _latencyLabel(ServerPing? ping, bool probing) {
  if (probing) return '…';
  if (ping == null) return '—';
  return switch (ping.status) {
    PingStatus.ok => '${ping.ms} ms',
    PingStatus.timeout => '—',
    PingStatus.pending => '…',
  };
}

/// Green means a latency a tunnel can actually carry traffic at; a measured
/// 1.1 s handshake is evidence, not a healthy signal.
Color _latencyColor(ServerPing? ping, AirColors air) {
  if (ping == null) return air.mute;
  return switch (ping.status) {
    PingStatus.ok => ping.ms <= 300 ? air.connectedInk : air.ink,
    PingStatus.timeout => air.mute,
    PingStatus.pending => air.steel,
  };
}

int _countryCount(List<VpnServer> servers) {
  final names = servers.map(
    (s) => s.displayCountry.isEmpty
        ? 'Private relays'
        : s.displayCountry.toLowerCase(),
  );
  final unique = names.toSet().length;
  return unique;
}

String _countryLabel(int count) =>
    count == 1 ? '1 country' : '$count countries';

class _BootstrapNotice extends StatelessWidget {
  const _BootstrapNotice();

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: TrustBadge(tier: TrustTier.bootstrap, compact: true),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bootstrap relays are community-contributed. They are not '
              'private and may see your traffic.',
              style: AppTextStyles.body(color: air.steel, size: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opt-in switch for the REALITY transport. Off by default: its relays are
/// community-run, which is a different privacy stance from the owned tiers.
class _RealitySwitch extends StatelessWidget {
  const _RealitySwitch({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return InkWell(
      onTap: () => onChanged(!enabled),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                'VLESS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.label(color: air.steel, size: 11),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TLS + REALITY',
                    style: AppTextStyles.body(color: air.ink, size: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'A real TLS handshake on 443, then a private tunnel. Gets '
                    'through networks that drop VPN handshakes.',
                    style: AppTextStyles.body(color: air.steel, size: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(value: enabled, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _RealityNotice extends StatelessWidget {
  const _RealityNotice();

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: TrustBadge(tier: TrustTier.community, compact: true),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Community relays. The operator can see your traffic; use them '
              'only if you accept that trade.',
              style: AppTextStyles.body(color: air.steel, size: 13),
            ),
          ),
        ],
      ),
    );
  }
}

sealed class _Entry {
  const _Entry();
}

class _AutoEntry extends _Entry {
  const _AutoEntry();
}

class _RealitySwitchEntry extends _Entry {
  const _RealitySwitchEntry({required this.enabled});
  final bool enabled;
}

class _RealityAutoEntry extends _Entry {
  const _RealityAutoEntry({required this.selected, required this.count});
  final bool selected;
  final int count;
}

class _RealityEntry extends _Entry {
  const _RealityEntry({required this.relay, required this.selected});
  final RealityRelay relay;
  final bool selected;
}

class _RealityNoticeEntry extends _Entry {
  const _RealityNoticeEntry();
}

class _SectionEntry extends _Entry {
  const _SectionEntry(this.label);
  final String label;
}

class _FastestEntry extends _Entry {
  const _FastestEntry(this.server, this.number);
  final VpnServer server;
  final int number;
}

class _CountryEntry extends _Entry {
  const _CountryEntry(this.group, this.minPing);
  final ServerGroup group;
  final int minPing;
}

class _ServerEntry extends _Entry {
  const _ServerEntry(this.server, this.number);
  final VpnServer server;
  final int number;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 6),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.label(color: air.steel),
      ),
    );
  }
}

class _RelayRow extends StatelessWidget {
  const _RelayRow({
    required this.code,
    required this.title,
    required this.latency,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.latencyColor,
    this.latencySize = 12,
    this.badge,
  });

  final String code;
  final String title;
  final String? subtitle;
  final String latency;
  final Color? latencyColor;
  final double latencySize;
  final bool selected;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
        decoration: selected
            ? BoxDecoration(
                color: air.accentWash,
                border: BorderDirectional(
                  start: BorderSide(color: air.accent, width: 2),
                ),
              )
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                code.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.label(color: air.steel, size: 11),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(color: air.ink, size: 15),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.monoValue(
                          color: air.steel,
                          size: 11,
                        ),
                      ),
                    ),
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: badge,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              latency,
              maxLines: 1,
              style: AppTextStyles.monoValue(
                color: latencyColor ?? air.steel,
                size: latencySize,
              ),
            ),
            SizedBox(
              width: 26,
              child: selected
                  ? Icon(Icons.check, size: 16, color: air.accent)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryHeader extends StatelessWidget {
  const _CountryHeader({required this.group, required this.minPing});

  final ServerGroup group;
  final int minPing;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final best = group.bestPing;
    final isFastestCountry = best != null && minPing > 0 && best.ms == minPing;
    final code = group.countryCode;
    final flagCode = code.length == 2 ? code : 'xx';
    final count = group.servers.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                height: 16,
                child: SvgPicture.asset(
                  'assets/flags/$flagCode.svg',
                  fit: BoxFit.contain,
                  placeholderBuilder: (_) =>
                      Icon(Icons.public, size: 16, color: air.steel),
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.public, size: 16, color: air.steel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.countryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(
                    color: isFastestCountry ? air.accentInk : air.ink,
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$count ${count == 1 ? 'relay' : 'relays'} · '
                '${best == null ? '—' : '${best.ms} ms'}',
                style: AppTextStyles.monoValue(color: air.mute, size: 11),
              ),
              TrustBadge(tier: group.servers.first.trustTier, compact: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
    this.onRefresh,
  });

  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.body(color: air.ink, size: 15),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: AppTextStyles.body(color: air.mute, size: 13),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: AppTextStyles.body(
                  color: air.accentInk,
                  size: 14,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
    if (onRefresh == null) return content;
    return RefreshIndicator(
      color: air.accent,
      backgroundColor: air.raised,
      onRefresh: onRefresh!,
      child: content,
    );
  }
}

class _ServerSkeletons extends StatelessWidget {
  const _ServerSkeletons();

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: 8,
      separatorBuilder: (_, __) => Divider(height: 1, color: air.hairline),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: Row(
          children: [
            Container(width: 48, height: 12, color: air.raised),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.4 + (i % 3) * 0.1,
                    child: Container(height: 12, color: air.raised),
                  ),
                  const SizedBox(height: 6),
                  FractionallySizedBox(
                    widthFactor: 0.3,
                    child: Container(height: 9, color: air.raised),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
