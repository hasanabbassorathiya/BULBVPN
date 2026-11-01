import 'dart:async';
import 'dart:io' show Platform;

import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/split_tunnel.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/shared/air/air_layout.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/air/air_rows.dart';
import 'package:bulbvpn/shared/air/horizon_field.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart'
    show ConnectionStatus, connectionStateProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Chooses which apps use the tunnel. Android only: Apple's packet tunnel
/// routes the whole device and exposes no per-app API.
class RoutingScreen extends ConsumerStatefulWidget {
  const RoutingScreen({super.key});

  @override
  ConsumerState<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends ConsumerState<RoutingScreen> {
  late Future<List<InstalledApp>> _apps;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _apps = Future.value(const <InstalledApp>[]);
    if (Platform.isAndroid) _loadApps();
  }

  void _loadApps() {
    setState(() {
      _apps = SoftEtherVpn.installedApps();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final config = ref.watch(splitTunnelProvider);
    final connected =
        ref.watch(connectionStateProvider).status == ConnectionStatus.connected;

    return HorizonField(
      phase: AirPhase.idle,
      showHorizon: false,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AirLayout.wideRail),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, AirLayout.gutter, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Routing',
                        style: AppTextStyles.title(color: air.ink, size: 21),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: !Platform.isAndroid
                      ? _appleBody()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AirLayout.gutter,
                            16,
                            AirLayout.gutter,
                            40,
                          ),
                          children: [
                            if (connected) ...[
                              const _ConnectedNote(),
                              const SizedBox(height: 20),
                            ],
                            AirSection(
                              title: 'Tunnel scope',
                              rows: [
                                _modeRow(
                                  config: config,
                                  mode: TunnelMode.all,
                                  title: 'All apps',
                                  subtitle:
                                      'Every app and service uses the tunnel.',
                                ),
                                _modeRow(
                                  config: config,
                                  mode: TunnelMode.bypass,
                                  title: 'Bypass apps',
                                  subtitle:
                                      'Everything uses the tunnel except the '
                                      'apps you pick — banking, casting, local '
                                      'devices.',
                                ),
                                _modeRow(
                                  config: config,
                                  mode: TunnelMode.allow,
                                  title: 'Only selected apps',
                                  subtitle:
                                      'Only the apps you pick use the tunnel; '
                                      'the rest stay on the carrier for speed.',
                                ),
                              ],
                            ),
                            if (config.isSplit) ...[
                              const SizedBox(height: 26),
                              Row(
                                children: [
                                  Text(
                                    'APPS',
                                    style: AppTextStyles.label(
                                      color: air.steel,
                                      size: 10.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${config.appCount} selected',
                                    style: AppTextStyles.monoValue(
                                      color: air.steel,
                                      size: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _SearchField(
                                controller: _search,
                                onChanged: (value) =>
                                    setState(() => _query = value.trim()),
                              ),
                              const SizedBox(height: 10),
                              _AppList(
                                apps: _apps,
                                query: _query,
                                selected: config.packages,
                                onToggle: (app, selected) => unawaited(
                                  ref
                                      .read(splitTunnelProvider.notifier)
                                      .setPackage(app.package, selected: selected),
                                ),
                                onRetry: _loadApps,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Changes apply the next time you connect. '
                                'BULBVPN itself always stays inside the tunnel '
                                'so the exit-IP check remains accurate. While '
                                'routing is split, connect stops with an error '
                                'instead of falling back to a full tunnel.',
                                style: AppTextStyles.body(
                                  color: air.steel,
                                  size: 12.5,
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 16),
                              Text(
                                'Changes apply the next time you connect.',
                                style: AppTextStyles.body(
                                  color: air.steel,
                                  size: 12.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeRow({
    required SplitTunnelConfig config,
    required TunnelMode mode,
    required String title,
    required String subtitle,
  }) {
    final air = context.air;
    final selected = config.mode == mode;
    return AirRow(
      title: title,
      subtitle: subtitle,
      selected: selected,
      chevron: false,
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 18,
        color: selected ? air.accentInk : air.mute,
      ),
      onTap: () => unawaited(
        ref.read(splitTunnelProvider.notifier).setMode(mode),
      ),
    );
  }

  Widget _appleBody() {
    final air = context.air;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Per-app routing is an Android feature.',
              textAlign: TextAlign.center,
              style: AppTextStyles.title(color: air.ink, size: 17),
            ),
            const SizedBox(height: 8),
            Text(
              'iOS and macOS route the whole device through the tunnel. '
              'The full tunnel keeps every app consistent, including '
              'Google services.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: air.steel, size: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedNote extends StatelessWidget {
  const _ConnectedNote();

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: air.accentInk),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'A tunnel is running. Disconnect and reconnect to apply routing.',
            style: AppTextStyles.body(color: air.steel, size: 12.5),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTextStyles.body(color: air.ink, size: 14),
        cursorColor: air.accentInk,
        decoration: InputDecoration(
          hintText: 'Search apps',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          prefixIcon: Icon(Icons.search, size: 19, color: air.mute),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 42,
            minHeight: 42,
          ),
        ),
      ),
    );
  }
}

class _AppList extends StatelessWidget {
  const _AppList({
    required this.apps,
    required this.query,
    required this.selected,
    required this.onToggle,
    required this.onRetry,
  });

  final Future<List<InstalledApp>> apps;
  final String query;
  final Set<String> selected;
  final void Function(InstalledApp app, bool selected) onToggle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return FutureBuilder<List<InstalledApp>>(
      future: apps,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: air.accentInk,
                ),
              ),
            ),
          );
        }
        final all = snapshot.data ?? const <InstalledApp>[];
        if (all.isEmpty) {
          return Column(
            children: [
              Text(
                'No launchable apps found.',
                style: AppTextStyles.body(color: air.steel, size: 13),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          );
        }
        final needle = query.toLowerCase();
        final filtered = needle.isEmpty
            ? all
            : all
                  .where(
                    (app) =>
                        app.label.toLowerCase().contains(needle) ||
                        app.package.toLowerCase().contains(needle),
                  )
                  .toList();
        if (filtered.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No apps match that search.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: air.steel, size: 13),
            ),
          );
        }
        return AirSection(
          title: 'Installed apps',
          rows: [
            for (final app in filtered)
              _AppRow(
                app: app,
                selected: selected.contains(app.package),
                onChanged: (value) => onToggle(app, value),
              ),
          ],
        );
      },
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.selected,
    required this.onChanged,
  });

  final InstalledApp app;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final letter = app.label.isEmpty ? '?' : app.label[0].toUpperCase();
    return AirRow(
      dense: true,
      selected: selected,
      chevron: false,
      title: app.label,
      subtitle: app.package,
      titleColor: selected ? air.ink : null,
      leading: SizedBox(
        width: 18,
        child: Text(
          letter,
          style: AppTextStyles.monoValue(
            color: selected ? air.accentInk : air.steel,
            size: 13,
          ),
        ),
      ),
      trailing: Icon(
        selected ? Icons.check : Icons.add,
        size: 18,
        color: selected ? air.accentInk : air.mute,
      ),
      onTap: () => onChanged(!selected),
    );
  }
}
