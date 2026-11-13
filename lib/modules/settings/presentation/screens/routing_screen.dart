import 'dart:async';

import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/modules/core/split_tunnel.dart';
import 'package:bulbvpn/shared/metered/card_ground.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/slip_list.dart';
import 'package:bulbvpn/shared/metered/terms_panel.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart'
    show ConnectionStatus, connectionStateProvider;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this build can offer per-app routing at all.
///
/// `defaultTargetPlatform` rather than `dart:io Platform`, because the plate
/// harness runs on a desktop host and `Platform.isAndroid` there can only ever
/// print the Apple branch — the face under review would be the one row of copy
/// above an empty card. Same answer on every shipped device, and a test or a
/// plate can now print the Android half.
bool get _perAppRoutingAvailable =>
    defaultTargetPlatform == TargetPlatform.android;

/// Chooses which apps use the tunnel. Android only: Apple's packet tunnel
/// routes the whole device and exposes no per-app API.
///
/// This face is pushed, so it owns its own ground: the card the tear is mounted
/// on stays behind it, and a second plate printed over the first is the only
/// way the pushed face can be the same object as the tabs.
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
    if (_perAppRoutingAvailable) _loadApps();
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
    final config = ref.watch(splitTunnelProvider);
    final connected =
        ref.watch(connectionStateProvider).status == ConnectionStatus.connected;

    return CardGround(
      insets: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final type = MeteredType(c.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FaceHeader(
                type: type,
                title: 'Routing',
                onBack: () => Navigator.of(context).maybePop(),
                note: _perAppRoutingAvailable ? config.scopeSummary : null,
              ),
              Expanded(
                child: !_perAppRoutingAvailable
                    ? _AppleBody(type: type)
                    : ListView(
                        padding: EdgeInsets.only(bottom: type.px(40)),
                        children: [
                          if (connected)
                            SlipNote(
                              type: type,
                              text:
                                  'A tunnel is running. Disconnect and '
                                  'reconnect to apply routing.',
                            ),
                          SlipSection(type: type, title: 'Tunnel scope'),
                          for (final mode in TunnelMode.values)
                            _ModeRow(
                              type: type,
                              config: config,
                              mode: mode,
                              // Android's tunnel is REALITY/XHTTP, whose plugin
                              // takes only a deny list, so "only these apps"
                              // cannot be honoured there. Bypass can.
                              unavailable: mode == TunnelMode.allow
                                  ? 'Not available on Android: the tunnel this '
                                        'app dials excludes apps but cannot '
                                        'admit only some. Use Bypass apps to '
                                        'keep local traffic off it.'
                                  : null,
                              onSelect: (value) => unawaited(
                                ref
                                    .read(splitTunnelProvider.notifier)
                                    .setMode(value),
                              ),
                            ),
                          if (config.isSplit) ...[
                            SlipSection(
                              type: type,
                              title: 'Apps',
                              note: '${config.appCount} selected',
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                type.px(26),
                                type.px(20),
                                type.px(24),
                                type.px(8),
                              ),
                              child: SlottedField(
                                controller: _search,
                                type: type,
                                hint: 'Search apps',
                                autocorrect: false,
                                enableSuggestions: false,
                                textCapitalization: TextCapitalization.none,
                                onChanged: (value) =>
                                    setState(() => _query = value.trim()),
                              ),
                            ),
                            _AppList(
                              type: type,
                              apps: _apps,
                              query: _query,
                              selected: config.packages,
                              onToggle: (app, selected) => unawaited(
                                ref
                                    .read(splitTunnelProvider.notifier)
                                    .setPackage(
                                      app.package,
                                      selected: selected,
                                    ),
                              ),
                              onRetry: _loadApps,
                            ),
                            SlipNote(
                              type: type,
                              text:
                                  'Changes apply the next time you connect. '
                                  'BULBVPN itself always stays inside the '
                                  'tunnel so the exit-IP check remains '
                                  'accurate. While routing is split, connect '
                                  'stops with an error instead of falling back '
                                  'to a full tunnel.',
                            ),
                          ] else
                            SlipNote(
                              type: type,
                              text: 'Changes apply the next time you connect.',
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The three scopes, printed as three lines of the same face rather than as
/// three cards: the plate marks the one the phone runs with its register, not
/// with a radio button it would have to invent a material for.
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.type,
    required this.config,
    required this.mode,
    required this.onSelect,
    this.unavailable,
  });

  final MeteredType type;
  final SplitTunnelConfig config;
  final TunnelMode mode;
  final String? unavailable;
  final ValueChanged<TunnelMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = config.mode == mode;
    final blocked = unavailable != null;
    final count = config.appCount;
    return TermRow(
      type: type,
      title: switch (mode) {
        TunnelMode.all => 'All apps',
        TunnelMode.bypass => 'Bypass apps',
        TunnelMode.allow => 'Only selected apps',
      },
      sub: switch ((mode, blocked)) {
        // A scope the dialled engine cannot express is stated as unavailable
        // where the promise used to be: the reader learns the limit at the
        // line they would have chosen it on, not after a failed connect.
        (TunnelMode.allow, true) => unavailable,
        (TunnelMode.all, _) => 'Every app and service uses the tunnel.',
        (TunnelMode.bypass, _) =>
          'Everything uses the tunnel except the apps you pick — banking, '
              'casting, local devices.',
        (TunnelMode.allow, _) =>
          'Only the apps you pick use the tunnel; the rest stay on the '
              'carrier for speed.',
      },
      // The count rides the line it belongs to, so the face says how many are
      // picked without making the reader hold the header note in memory.
      value: selected && mode != TunnelMode.all
          ? blocked
                ? 'cannot run'
                : count == 0
                ? 'none yet'
                : '$count ${mode == TunnelMode.bypass ? 'outside' : 'inside'}'
          : null,
      selected: selected,
      onTap: blocked ? null : () => onSelect(mode),
    );
  }
}

class _AppleBody extends StatelessWidget {
  const _AppleBody({required this.type});

  final MeteredType type;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.only(bottom: type.px(40)),
      children: [
        SlipNote(
          type: type,
          mark: 'ANDROID ONLY',
          text: 'Per-app routing is an Android feature.',
        ),
        SlipNote(
          type: type,
          text:
              'iOS and macOS route the whole device through the tunnel. '
              'The full tunnel keeps every app consistent, including Google '
              'services.',
        ),
      ],
    );
  }
}

class _AppList extends StatelessWidget {
  const _AppList({
    required this.type,
    required this.apps,
    required this.query,
    required this.selected,
    required this.onToggle,
    required this.onRetry,
  });

  final MeteredType type;
  final Future<List<InstalledApp>> apps;
  final String query;
  final Set<String> selected;
  final void Function(InstalledApp app, bool selected) onToggle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InstalledApp>>(
      future: apps,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // The plate has no spinner: the hole that will not take input prints
          // dead, and a line that is still being read prints as a running one.
          return SlipNote(
            type: type,
            text: 'Reading the apps Android has installed……',
          );
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SlipNote(
                type: type,
                failed: true,
                mark: 'NOT READ',
                text: 'Android did not answer with an app list.',
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
                  child: CardKey(label: 'Retry', type: type, onTap: onRetry),
                ),
              ),
            ],
          );
        }
        final all = snapshot.data ?? const <InstalledApp>[];
        if (all.isEmpty) {
          return SlipNote(
            type: type,
            text: 'No launchable apps found on this device.',
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
          return SlipNote(type: type, text: 'No apps match that search.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SlipSection(
              type: type,
              title: 'Installed apps',
              note: '${filtered.length} of ${all.length}',
            ),
            for (final app in filtered)
              TermRow(
                type: type,
                title: app.label,
                sub: app.package,
                selected: selected.contains(app.package),
                onTap: () => onToggle(app, !selected.contains(app.package)),
              ),
          ],
        );
      },
    );
  }
}
