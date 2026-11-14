import 'dart:async';

import 'package:bulbvpn/core/theme/simple_colors.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
import 'package:bulbvpn/modules/core/split_tunnel.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart'
    show ConnectionStatus, connectionStateProvider;
import 'package:bulbvpn/shared/simple/simple_card.dart';
import 'package:bulbvpn/shared/simple/simple_field.dart';
import 'package:bulbvpn/shared/simple/simple_header.dart';
import 'package:bulbvpn/shared/simple/simple_key.dart';
import 'package:bulbvpn/shared/simple/simple_note.dart';
import 'package:bulbvpn/shared/simple/simple_section.dart';
import 'package:bulbvpn/shared/simple/simple_term_row.dart';
import 'package:bulbvpn/shared/simple/simple_type.dart';
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

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      child: SimpleCard(
        child: LayoutBuilder(
          builder: (context, c) {
            final type = SimpleType(c.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SimpleHeader(
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
                              SimpleNote(
                                text:
                                    'A tunnel is running. Disconnect and '
                                    'reconnect to apply routing.',
                              ),
                            SimpleSection(title: 'Tunnel scope'),
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
                              SimpleSection(
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
                                child: SimpleField(
                                  controller: _search,
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
                              SimpleNote(
                                text:
                                    'Changes apply the next time you connect. '
                                    'BULBVPN itself always stays inside the '
                                    'tunnel so the exit-IP check remains '
                                    'accurate. While routing is split, connect '
                                    'stops with an error instead of falling back '
                                    'to a full tunnel.',
                              ),
                            ] else
                              SimpleNote(
                                text: 'Changes apply the next time you connect.',
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

  final SimpleType type;
  final SplitTunnelConfig config;
  final TunnelMode mode;
  final String? unavailable;
  final ValueChanged<TunnelMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = config.mode == mode;
    final blocked = unavailable != null;
    final count = config.appCount;
    return SimpleTermRow(
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
      value: selected && mode != TunnelMode.all
          ? blocked
                ? 'cannot run'
                : count == 0
                ? 'none yet'
                : '$count ${mode == TunnelMode.bypass ? 'outside' : 'inside'}'
          : null,
      selected: selected,
      failed: blocked,
      onTap: blocked ? null : () => onSelect(mode),
    );
  }
}

class _AppleBody extends StatelessWidget {
  const _AppleBody({required this.type});

  final SimpleType type;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.only(bottom: type.px(40)),
      children: [
        SimpleNote(
          mark: 'ANDROID ONLY',
          text: 'Per-app routing is an Android feature.',
        ),
        SimpleNote(
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

  final SimpleType type;
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
          return SimpleNote(
            text: 'Reading the apps Android has installed……',
          );
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SimpleNote(
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
                  child: SimpleKey(label: 'Retry', onTap: onRetry),
                ),
              ),
            ],
          );
        }
        final all = snapshot.data ?? const <InstalledApp>[];
        if (all.isEmpty) {
          return SimpleNote(
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
          return SimpleNote(text: 'No apps match that search.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SimpleSection(
              title: 'Installed apps',
              note: '${filtered.length} of ${all.length}',
            ),
            for (final app in filtered)
              SimpleTermRow(
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
