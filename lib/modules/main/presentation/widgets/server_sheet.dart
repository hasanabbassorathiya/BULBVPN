import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/modules/main/presentation/screens/main_screen.dart';
import 'package:bulbvpn/shared/widgets/staggered_in.dart';

/// Currently picked server (null = auto / test config).
final selectedServerProvider = StateProvider<VpnServer?>((ref) => null);

Future<void> showServerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
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
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serversProvider);
    final selected = ref.watch(selectedServerProvider);
    final pingState = ref.watch(serverPingProvider);

    return Column(
      children: [
        // Grabber.
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.mute,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Header.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Servers',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      serversAsync.maybeWhen(
                        data: (servers) => servers.isEmpty
                            ? 'Loading catalog'
                            : '${servers.length} relays · lowest ping first',
                        orElse: () => 'Loading catalog',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: AppColors.mute, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Ping all — real device latency, not the server-reported ms.
              if (MediaQuery.sizeOf(context).width < 380)
                IconButton(
                  onPressed: pingState.probing
                      ? null
                      : () async {
                          final serversAsync = ref.read(serversProvider);
                          final servers = serversAsync.valueOrNull;
                          if (servers == null || servers.isEmpty) return;
                          await ref
                              .read(serverPingProvider.notifier)
                              .pingAll(servers);
                        },
                  tooltip: 'Ping all',
                  icon: pingState.probing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.amber,
                          ),
                        )
                      : const Icon(Icons.speed, size: 20, color: AppColors.amber),
                )
              else
                TextButton.icon(
                  onPressed: pingState.probing
                      ? null
                      : () async {
                          final serversAsync = ref.read(serversProvider);
                          final servers = serversAsync.valueOrNull;
                          if (servers == null || servers.isEmpty) return;
                          await ref
                              .read(serverPingProvider.notifier)
                              .pingAll(servers);
                        },
                  icon: pingState.probing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.amber,
                          ),
                        )
                      : const Icon(Icons.speed, size: 18, color: AppColors.amber),
                  label: Text(
                    pingState.probing ? 'Pinging…' : 'Ping all',
                    style: const TextStyle(
                      color: AppColors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.steel, size: 22),
                tooltip: 'Close',
              ),
            ],
          ),
        ),
        // Search field.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            style: const TextStyle(color: AppColors.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search country',
              hintStyle: const TextStyle(color: AppColors.mute, fontSize: 14),
              prefixIcon:
                  const Icon(Icons.search, color: AppColors.mute, size: 20),
              filled: true,
              fillColor: AppColors.raised,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        // Auto mode is an explicit choice, not a hidden "tap the selection
        // again" gesture. It resets the picker so the connect path is free to
        // use the fastest relay measured on this device.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              ref.read(selectedServerProvider.notifier).state = null;
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected == null
                    ? AppColors.amberTint
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected == null
                      ? AppColors.amber.withValues(alpha: 0.35)
                      : AppColors.hairline,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bolt,
                    size: 18,
                    color: selected == null ? AppColors.amber : AppColors.steel,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto',
                          style: TextStyle(
                            color: selected == null
                                ? AppColors.amber
                                : AppColors.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Fastest relay measured from this device',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: AppColors.mute, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (selected == null)
                    const Icon(
                      Icons.check_circle,
                      size: 18,
                      color: AppColors.amber,
                    ),
                ],
              ),
            ),
          ),
        ),
        // List.
        Expanded(
          child: serversAsync.when(
            loading: () => const _ServerSkeletons(),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load servers.\n$e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.steel, fontSize: 13),
                ),
              ),
            ),
            data: (servers) {
              final measuredByIp = pingState.byIp;
              final sorted = sortByMeasuredPing(servers, measuredByIp);
              final filtered = _query.isEmpty
                  ? sorted
                  : sorted
                      .where((s) =>
                          s.countryLong.toLowerCase().contains(_query) ||
                          s.countryShort.toLowerCase().contains(_query) ||
                          s.displayCountry.toLowerCase().contains(_query))
                      .toList();
              if (servers.isEmpty) {
                return const Center(
                  child: Text(
                    'Server list is still loading.',
                    style: TextStyle(color: AppColors.mute, fontSize: 13),
                  ),
                );
              }
              if (filtered.isEmpty) {
                return const Center(
                  child: Text('No servers match.',
                      style: TextStyle(color: AppColors.mute, fontSize: 13)),
                );
              }
              final okPings = filtered
                  .map((s) => measuredByIp[s.ip])
                  .whereType<ServerPing>()
                  .where((p) => p.status == PingStatus.ok)
                  .map((p) => p.ms)
                  .toList();
              final minPing = okPings.isEmpty
                  ? 0
                  : okPings.reduce((a, b) => a < b ? a : b);
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.hairline),
                itemBuilder: (context, i) => StaggeredIn(
                  delayMs: (i * 40).clamp(0, 400),
                  offset: 8,
                  child: _ServerRow(
                    server: filtered[i],
                    ping: measuredByIp[filtered[i].ip],
                    pingProbing: pingState.probing,
                    minPing: minPing,
                    isSelected: selected?.ip == filtered[i].ip,
                    onTap: () {
                      final notifier =
                          ref.read(selectedServerProvider.notifier);
                      // Go back to auto when tapping the current selection.
                      if (selected?.ip == filtered[i].ip) {
                        notifier.state = null;
                      } else {
                        notifier.state = filtered[i];
                      }
                      Navigator.pop(context);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.ping,
    required this.pingProbing,
    required this.minPing,
    required this.isSelected,
    required this.onTap,
  });

  final VpnServer server;
  final ServerPing? ping;
  final bool pingProbing;
  final int minPing;
  final bool isSelected;
  final VoidCallback onTap;

  String get _flagCode {
    final code = server.countryShort.toLowerCase();
    return code.length == 2 ? code : 'xx';
  }

  @override
  Widget build(BuildContext context) {
    final p = ping;
    final measured = p != null && p.status == PingStatus.ok ? p.ms : null;
    // Fall back to the server's own reported ms only when we haven't measured
    // yet — after "Ping all", the measured value takes over (per user: "don't
    // use server's ms info").
    final effectivePing = measured ?? (server.ping > 0 && p == null ? server.ping : 0);
    final pingLabel = p == null
        ? (effectivePing > 0 ? '$effectivePing ms' : '—')
        : pingProbing
            ? '…'
            : switch (p.status) {
                PingStatus.ok => '${p.ms} ms',
                PingStatus.timeout => '—',
                PingStatus.pending => '…',
              };
    final bars = effectivePing <= 0 || (p?.status == PingStatus.timeout)
        ? 0
        : effectivePing < 100
            ? 3
            : effectivePing < 200
                ? 2
                : 1;
    final isBest = measured != null && minPing > 0 && measured == minPing;
    final pingColor = switch (p?.status) {
      PingStatus.ok => p!.ms < 100
          ? AppColors.amber
          : p.ms < 250
              ? AppColors.steel
              : AppColors.mute,
      PingStatus.timeout => AppColors.red,
      _ => AppColors.steel,
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: isSelected
            ? BoxDecoration(
                color: AppColors.amberTint,
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Row(
          children: [
            const SizedBox(width: 8),
            SizedBox(
              width: 30,
              height: 22,
              child: SvgPicture.asset(
                'assets/flags/$_flagCode.svg',
                fit: BoxFit.contain,
                placeholderBuilder: (_) =>
                    const Icon(Icons.public, size: 20, color: AppColors.steel),
                errorBuilder: (_, __, ___) => const Icon(Icons.public,
                    size: 20, color: AppColors.steel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.publicLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? AppColors.amber : AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    server.countryLong.isEmpty
                        ? 'Private relay'
                        : '${server.countryLong} · relay',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.mute,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Latency bars.
            Row(
              children: List.generate(3, (i) {
                final on = i < bars;
                return Container(
                  width: 3,
                  height: 5.0 + i * 4,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: on
                        ? (isBest ? AppColors.amber : AppColors.steel)
                        : AppColors.graphite,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                );
              }),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                pingLabel,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: pingColor,
                  fontSize: 12,
                  fontFamily: 'GeistMono',
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              isSelected ? Icons.check_circle : Icons.chevron_right,
              size: 18,
              color: isSelected ? AppColors.amber : AppColors.mute,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _ServerSkeletons extends StatelessWidget {
  const _ServerSkeletons();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      itemCount: 8,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.hairline),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.raised,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120.0 + (i % 3) * 30,
                    height: 12,
                    color: AppColors.raised,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 90,
                    height: 9,
                    color: AppColors.raised,
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
