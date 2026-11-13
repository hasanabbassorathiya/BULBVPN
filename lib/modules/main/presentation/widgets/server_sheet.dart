import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/metered_colors.dart';
import 'package:bulbvpn/modules/core/reality/reality_engine.dart';
import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/reality/relay_link.dart';
import 'package:bulbvpn/modules/core/reality/relay_vault.dart';
import 'package:bulbvpn/modules/core/relay_verdict.dart';
import 'package:bulbvpn/modules/core/server_catalog.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/main/application/relay_evidence_provider.dart';
import 'package:bulbvpn/modules/main/application/server_grouping.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/relay_import_sheet.dart';
import 'package:bulbvpn/shared/metered/card_ground.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/slip_list.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';

/// Currently picked server (null = auto / test config).
final selectedServerProvider = StateProvider<VpnServer?>((ref) => null);

/// The relay slip: the connect card's four columns and its verdict words,
/// unrolled long enough to read every relay this phone can dial.
Future<void> showServerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // The slip is a card, not a panel, so the plate's own ground carries its
    // corners, its scuffs and its shadow. A sheet that painted its own
    // background would be a rectangle with the card's print pasted on it.
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: const FractionallySizedBox(
        heightFactor: 0.82,
        child: ServerSheet(),
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

  /// Pull both catalogs again without leaving the sheet. The screen is usually
  /// opened from a network that already blocked one fetch, so the empty state
  /// has to offer a real retry. Errors stay rendered by the list itself; the
  /// awaits only bound the pull-down spinner.
  Future<void> _reloadCatalog() async {
    ref.invalidate(serversProvider);
    ref.invalidate(realityRelaysProvider);
    ref.invalidate(relayEvidenceProvider);
    await ref.read(serversProvider.future).catchError((_) => <VpnServer>[]);
    await ref
        .read(realityRelaysProvider.future)
        .catchError((_) => <RealityRelay>[]);
  }

  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serversProvider);
    final pingState = ref.watch(serverPingProvider);
    final realitySupported = ref.watch(realitySupportedProvider);
    final realityRelays =
        ref.watch(realityRelaysProvider).valueOrNull ?? const <RealityRelay>[];

    ref.listen(serversProvider, (_, next) {
      if (next.valueOrNull?.isNotEmpty == true) _refreshPings();
    });

    return CardGround(
      child: LayoutBuilder(
        builder: (context, c) {
          final type = MeteredType(c.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SlipHeader(
                type: type,
                note: _headerNote(
                  serversAsync,
                  realityRelays,
                  realitySupported,
                  pingState,
                ),
                probing: pingState.probing,
                canMeasure: _canMeasure,
                onMeasure: _pingAll,
                onClose: () => Navigator.maybePop(context),
              ),
              // The trust contract stays on screen while people pick; it is
              // never a one-time dialog they can dismiss and forget.
              SlipNote(
                type: type,
                mark: 'NOT PRIVATE',
                markSemantic: TrustTier.bootstrap.disclosure,
                text:
                    'Bootstrap relays are community-contributed. They are not '
                    'private and may see your traffic.',
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  type.px(26),
                  type.px(20),
                  type.px(24),
                  type.px(18),
                ),
                child: SlottedField(
                  controller: _search,
                  type: type,
                  hint: 'Search country',
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              Expanded(
                child: serversAsync.when(
                  loading: () => _SlipSkeletons(type: type),
                  error: (e, _) => _SheetMessage(
                    type: type,
                    title: 'Catalog unavailable',
                    detail: 'Check the connection and try again.',
                    actionLabel: 'RETRY',
                    onAction: () => ref.invalidate(serversProvider),
                  ),
                  data: (servers) => _slip(type, servers),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The body of the slip: the entries the search leaves, grouped, on the
  /// card's own column register.
  Widget _slip(MeteredType type, List<VpnServer> servers) {
    final m = context.metered;
    final selected = ref.watch(selectedServerProvider);
    final pingState = ref.watch(serverPingProvider);
    final reality = ref.watch(realitySettingsProvider);
    final realitySupported = ref.watch(realitySupportedProvider);
    final realityRelays =
        ref.watch(realityRelaysProvider).valueOrNull ?? const <RealityRelay>[];
    final evidence =
        ref.watch(relayEvidenceProvider).valueOrNull ?? RelayEvidence.empty;

    if (servers.isEmpty && realityRelays.isEmpty) {
      return _SheetMessage(
        type: type,
        title: 'No relays loaded',
        detail:
            'The catalog did not reach this network. Pull down to load it '
            'again.',
        onRefresh: _reloadCatalog,
      );
    }

    final measuredByIp = pingState.byIp;
    final matching = _query.isEmpty
        ? servers
        : servers
              .where(
                (s) =>
                    _matches(_query, s.countryLong) ||
                    _matches(_query, s.countryShort) ||
                    _matches(_query, s.displayCountry) ||
                    _matches(_query, s.hostName) ||
                    _matches(_query, s.ip),
              )
              .toList();
    final matchingReality = !realitySupported
        ? const <RealityRelay>[]
        : (_query.isEmpty
              ? realityRelays
              : realityRelays
                    .where(
                      (r) =>
                          _matches(_query, r.countryName) ||
                          _matches(_query, r.countryCode) ||
                          _matches(_query, r.city) ||
                          _matches(_query, r.host),
                    )
                    .toList());
    if (matching.isEmpty && matchingReality.isEmpty) {
      return _SheetMessage(
        type: type,
        title: 'No servers match',
        detail: 'Try another country.',
      );
    }

    // Grouping is the ordering promise: countries rank by the strongest
    // evidence available, so a relay this phone already carried traffic
    // through beats one with a pretty handshake. The proof needs no section of
    // its own — it is printed in the row and it decides the row's place, which
    // is what keeps a relay from appearing twice under two different claims.
    final groups = groupServersByCountry(
      matching,
      measuredByIp,
      proven: evidence.proven.keys.toSet(),
    );
    final orderedReality = _orderByProof(
      matchingReality.where((relay) => !relay.private).toList(),
      evidence,
    );
    // The user's own relays are listed whether or not the community switch is
    // on. They do not need that consent — the user named these addresses — so
    // hiding them behind a toggle about *strangers'* relays would make a
    // bought server undiscoverable.
    final orderedYours = _orderByProof(
      matchingReality.where((relay) => relay.private).toList(),
      evidence,
    );
    final entries = <_Entry>[
      if (realitySupported) ...[
        const _SectionEntry('Your servers'),
        for (final relay in orderedYours)
          _RealityEntry(relay: relay, selected: reality.selectedId == relay.id),
        const _AddRelayEntry(),
        const _SectionEntry('Censorship-resistant'),
        _RealitySwitchEntry(enabled: reality.enabled),
        if (reality.enabled) ...[
          _RealityAutoEntry(
            selected: reality.selectedId == null,
            count: orderedReality.length + orderedYours.length,
          ),
          for (final relay in orderedReality)
            _RealityEntry(
              relay: relay,
              selected: reality.selectedId == relay.id,
            ),
          const _RealityNoticeEntry(),
        ],
      ],
      if (matching.isNotEmpty) const _SectionEntry('Bootstrap'),
      const _AutoEntry(),
      for (final group in groups) ...[
        _CountryEntry(group),
        for (var i = 0; i < group.servers.length; i++)
          _ServerEntry(group.servers[i], i + 1),
      ],
    ];

    return RefreshIndicator(
      color: m.value,
      backgroundColor: m.card,
      onRefresh: _pingAll,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: type.px(32)),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final entry = entries[i];
          return KeyedSubtree(
            key: ValueKey(entry.entryKey),
            child: switch (entry) {
              _RealitySwitchEntry(:final enabled) => SlipToggleRow(
                type: type,
                code: 'VLESS',
                title: 'TLS + REALITY',
                // One line of what the handshake does, because a control that
                // out-prints the relays under it is a control people skip. The
                // trade — a community operator can see the traffic — is printed
                // once, in the notice that sits with the relays it is about.
                sub:
                    'Ordinary TLS on port 443, so networks that '
                    'drop VPN let it through.',
                on: enabled,
                toggleKey: const ValueKey('reality-toggle'),
                onChanged: (value) => unawaited(
                  ref.read(realitySettingsProvider.notifier).setEnabled(value),
                ),
              ),
              _RealityAutoEntry(:final selected, :final count) => SlipRow(
                type: type,
                code: 'AUTO',
                title: 'Auto',
                sub: 'VLESS + REALITY',
                reading: '—',
                qualifier: count > 0 ? '$count ready' : 'none ready',
                verdict: RelayVerdict.untried,
                selected: selected,
                onTap: () => _pickReality(null),
              ),
              _RealityEntry(:final relay, :final selected) => _realityRow(
                type,
                relay,
                evidence,
                selected,
              ),
              _RealityNoticeEntry() => SlipNote(
                type: type,
                mark: 'NOT PRIVATE',
                markSemantic: TrustTier.community.disclosure,
                text:
                    'Community relays. The operator can see your traffic. '
                    'They are dialled unless you switch them off above.',
              ),
              _AddRelayEntry() => SlipAction(
                type: type,
                title: 'Add your own server',
                // What goes in the hole, not what the tunnel can read: the
                // protocol list is printed once, on the slip that asks for the
                // text. An action row that quotes the manual is an action row
                // nobody taps.
                text: 'Paste a link or an https subscription address.',
                keyLabel: 'ADD',
                onTap: _openImport,
              ),
              _AutoEntry() => SlipRow(
                type: type,
                code: 'AUTO',
                title: 'Auto',
                // The transport Auto will actually dial. Android dials one
                // engine and Apple another, so a single label here is a
                // promise one platform cannot keep.
                sub: defaultTargetPlatform == TargetPlatform.android
                    ? 'REALITY/XHTTP'
                    : 'SoftEther SSL-VPN',
                reading: '—',
                qualifier: _canMeasure ? 'best below' : 'paused: tunnel open',
                verdict: RelayVerdict.untried,
                selected: selected == null && !reality.usable,
                onTap: () {
                  ref.read(selectedServerProvider.notifier).state = null;
                  Navigator.maybePop(context);
                },
              ),
              _SectionEntry(:final label) => SlipSection(
                type: type,
                title: label,
              ),
              _CountryEntry(:final group) => SlipSection(
                type: type,
                title: group.countryName,
                proven: group.proven,
                leading: _flag(group.countryCode),
                note: _groupNote(group),
                disclosure: group.proven
                    ? null
                    : _trustMark(group.servers.first.trustTier),
                disclosureSemantics: group.proven
                    ? null
                    : group.servers.first.trustTier.disclosure,
              ),
              _ServerEntry(:final server, :final number) => _bootstrapRow(
                type,
                server,
                number,
                evidence.reading(
                  dial: server.ip,
                  ping: measuredByIp[server.ip],
                ),
                selected?.ip == server.ip,
              ),
            },
          );
        },
      ),
    );
  }

  /// A bootstrap relay. The country section already says the tier is not
  /// private, so the row spends its measure on the reading instead of
  /// repeating the warning four times down one column.
  SlipRow _bootstrapRow(
    MeteredType type,
    VpnServer server,
    int number,
    RelayReading reading,
    bool selected,
  ) {
    return SlipRow(
      type: type,
      code: _codeFor(server),
      title: 'Relay $number',
      sub: 'SoftEther SSL-VPN',
      subTail: server.ip,
      reading: reading.value,
      qualifier: reading.qualifier,
      verdict: reading.verdict,
      selected: selected,
      onTap: () => _pick(server, ref.read(selectedServerProvider)),
    );
  }

  SlipRow _realityRow(
    MeteredType type,
    RealityRelay relay,
    RelayEvidence evidence,
    bool selected,
  ) {
    final reading = evidence.reading(dial: relay.host, relayId: relay.id);
    final tier = relay.toTarget().trustTier!;
    return SlipRow(
      type: type,
      code: relay.private
          ? 'OWN'
          : relay.countryCode.isEmpty
          ? '—'
          : relay.countryCode,
      title: relay.city.isEmpty
          ? relay.countryName
          : '${relay.city}, ${relay.countryName}',
      // Printed from the config the core is handed, not from the link's own
      // text: an imported profile runs whatever transport it parsed to, and a
      // row that guessed would promise REALITY to a server that answers with
      // plain TLS. The transport and the address take two lines because one
      // line of both is wider than the column and the plate would shrink it
      // past reading.
      sub: DialShape.of(relay).summary,
      subTail: relay.endpoint,
      reading: reading.value,
      qualifier: reading.qualifier,
      verdict: reading.verdict,
      disclosure: _trustMark(tier),
      disclosureSemantics: tier.disclosure,
      selected: selected,
      onTap: () => _pickReality(relay.id),
      trailingKey: (!selected && relay.private) ? 'REMOVE' : null,
      onTrailing: relay.private ? () => _removeRelay(relay) : null,
    );
  }

  String _headerNote(
    AsyncValue<List<VpnServer>> serversAsync,
    List<RealityRelay> realityRelays,
    bool realitySupported,
    ServerPingState pingState,
  ) {
    return serversAsync.maybeWhen(
      data: (servers) {
        if (servers.isEmpty && realityRelays.isEmpty) return 'Loading catalog';
        // Count only what this platform can actually pick: REALITY is
        // Android-only, so listing its relays as available on iOS would be a
        // false promise.
        final listable = realitySupported
            ? realityRelays
            : const <RealityRelay>[];
        final total = servers.length + listable.length;
        // The sweep streams: show how many relays have answered instead of
        // pretending it is all-or-nothing.
        final measured = pingState.byIp.values
            .where((p) => p.status != PingStatus.pending)
            .length;
        final progress = pingState.probing
            ? ' · $measured/$total measured'
            : '';
        return '$total relays · '
            '${_countryLabel(_countryCount(servers) + _countryCountOfReality(listable))}'
            '$progress';
      },
      orElse: () => 'Loading catalog',
    );
  }

  Widget _flag(String code) {
    final flagCode = code.length == 2 ? code : 'xx';
    return SizedBox(
      width: 22,
      height: 16,
      child: SvgPicture.asset(
        'assets/flags/$flagCode.svg',
        fit: BoxFit.contain,
        // A missing flag is a missing part, not a missing country: the plate
        // leaves the hole rather than painting a globe over it.
        placeholderBuilder: (_) => const SizedBox.shrink(),
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  String _groupNote(ServerGroup group) {
    final count = group.servers.length;
    final best = group.bestPing;
    return '$count ${count == 1 ? 'relay' : 'relays'} · '
        '${group.proven
            ? 'yours'
            : best == null
            ? '—'
            : '${best.ms} ms'}';
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

  Future<void> _openImport() => showRelayImportSheet(context);

  /// Forgets one imported server.
  ///
  /// Removing the relay the tunnel is currently pointed at drops the pick back
  /// to the pool, so a delete never leaves the engine dialling an address that
  /// is no longer on the list.
  Future<void> _removeRelay(RealityRelay relay) async {
    await ref.read(importedRelaysProvider.notifier).remove(relay.id);
    if (!mounted) return;
    if (ref.read(realitySettingsProvider).selectedId != relay.id) return;
    await ref.read(realitySettingsProvider.notifier).select(null);
  }
}

/// The mark a row carries for a given operator. A private tier is named, a
/// public one is warned about — and neither borrows the red the plate uses for
/// a relay that did not deliver.
String _trustMark(TrustTier tier) =>
    tier.isPrivate ? tier.short : 'NOT PRIVATE';

String _codeFor(VpnServer server) {
  final code = server.countryShort.trim().toLowerCase();
  return code.length == 2 ? code : '—';
}

bool _matches(String query, String value) =>
    query.isEmpty || value.toLowerCase().contains(query);

int _countryCount(List<VpnServer> servers) {
  final names = servers.map(
    (s) => s.displayCountry.isEmpty
        ? 'Private relays'
        : s.displayCountry.toLowerCase(),
  );
  final unique = names.toSet().length;
  return unique;
}

int _countryCountOfReality(List<RealityRelay> relays) {
  // A remark is not a country. Counting the user's own servers here would
  // print "4 countries" over four names they typed themselves.
  final names = relays
      .where((r) => !r.private)
      .map((r) => r.countryName.trim().isEmpty ? r.countryCode : r.countryName);
  return names.map((n) => n.toLowerCase()).toSet().length;
}

/// Relays this phone has already carried traffic through come first.
List<RealityRelay> _orderByProof(
  List<RealityRelay> relays,
  RelayEvidence evidence,
) {
  return [...relays]..sort((a, b) {
    final byProof = (evidence.isProven(b.host) ? 1 : 0).compareTo(
      evidence.isProven(a.host) ? 1 : 0,
    );
    return byProof;
  });
}

String _countryLabel(int count) =>
    count == 1 ? '1 country' : '$count countries';

/// The slip's own head: what the sheet is, how many relays it holds, and the
/// two keys that end it. There is no drag handle — a card is picked up by its
/// edge, and the plate prints a grip tab only where it also prints a hole.
class _SlipHeader extends StatelessWidget {
  const _SlipHeader({
    required this.type,
    required this.note,
    required this.probing,
    required this.canMeasure,
    required this.onMeasure,
    required this.onClose,
  });

  final MeteredType type;
  final String note;
  final bool probing;

  /// A live tunnel owns the radio and the routing table, so the sweep is not
  /// offered while one runs.
  final bool canMeasure;
  final VoidCallback onMeasure;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: m.ruleStrong, width: type.px(2)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          type.px(26),
          type.px(24),
          type.px(24),
          type.px(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedLine(
                    'Relays',
                    AppTextStyles.title(
                      color: m.ink,
                      size: type.navLabelAttached,
                      weight: FontWeight.w700,
                      tracking: 0,
                    ),
                  ),
                  SizedBox(height: type.claim * 0.34),
                  FittedLine(
                    note,
                    AppTextStyles.monoValue(
                      color: m.inkSoft,
                      size: type.claim,
                      height: 1.0,
                      tracking: type.claimLeft,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: type.px(18)),
            CardKey(
              label: probing ? 'Measuring' : 'Measure',
              type: type,
              busy: probing,
              emphasis: canMeasure,
              onTap: canMeasure && !probing ? onMeasure : null,
            ),
            SizedBox(width: type.px(12)),
            CardKey(label: 'Close', type: type, onTap: onClose),
          ],
        ),
      ),
    );
  }
}

sealed class _Entry {
  const _Entry();

  /// Stable identity per row. Pings stream in while this list is open, and a
  /// row that loses its identity mid-scroll remounts and jumps.
  String get entryKey;
}

class _AutoEntry extends _Entry {
  const _AutoEntry();

  @override
  String get entryKey => 'auto';
}

class _RealitySwitchEntry extends _Entry {
  const _RealitySwitchEntry({required this.enabled});
  final bool enabled;

  @override
  String get entryKey => 'reality-switch';
}

class _RealityAutoEntry extends _Entry {
  const _RealityAutoEntry({required this.selected, required this.count});
  final bool selected;
  final int count;

  @override
  String get entryKey => 'reality-auto';
}

class _RealityEntry extends _Entry {
  const _RealityEntry({required this.relay, required this.selected});
  final RealityRelay relay;
  final bool selected;

  @override
  String get entryKey => 'reality:${relay.id}';
}

class _RealityNoticeEntry extends _Entry {
  const _RealityNoticeEntry();

  @override
  String get entryKey => 'reality-notice';
}

/// Opens the import sheet. Present whether or not the vault is empty: the
/// bundled pool is nine relays on SNIs a censor already blocks, and a user who
/// has their own server needs one place to say so.
class _AddRelayEntry extends _Entry {
  const _AddRelayEntry();

  @override
  String get entryKey => 'relay-add';
}

class _SectionEntry extends _Entry {
  const _SectionEntry(this.label);
  final String label;

  @override
  String get entryKey => 'section:$label';
}

class _CountryEntry extends _Entry {
  const _CountryEntry(this.group);
  final ServerGroup group;

  @override
  String get entryKey => 'country:${group.countryName}';
}

/// One bootstrap relay, numbered inside its own country.
class _ServerEntry extends _Entry {
  const _ServerEntry(this.server, this.number);
  final VpnServer server;
  final int number;

  @override
  String get entryKey => 'server:${server.ip}';
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({
    this.type,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
    this.onRefresh,
  });

  /// The card's scale, handed down the way every other row gets it.
  final MeteredType? type;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    final type = this.type ?? MeteredType(1024);
    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: type.px(60),
        vertical: type.px(64),
      ),
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.title(
            color: m.ink,
            size: type.tableRowMixed,
            weight: FontWeight.w600,
            tracking: 0,
          ),
        ),
        SizedBox(height: type.claim * 0.5),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: AppTextStyles.body(
            color: m.inkSoft,
            size: type.exitPlace,
            height: 1.34,
          ),
        ),
        if (actionLabel != null) ...[
          SizedBox(height: type.px(44)),
          Center(
            child: CardKey(
              label: actionLabel!,
              type: type,
              onTap: onAction,
              emphasis: true,
            ),
          ),
        ],
      ],
    );
    if (onRefresh == null) return content;
    return RefreshIndicator(
      color: m.value,
      backgroundColor: m.card,
      onRefresh: onRefresh!,
      child: content,
    );
  }
}

/// The catalog is on its way. The plate prints ruled rows with no ink in them
/// rather than a spinner, so what loads is the length of the list the reader
/// is about to get.
class _SlipSkeletons extends StatelessWidget {
  const _SlipSkeletons({required this.type});

  final MeteredType type;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return ListView.builder(
      padding: EdgeInsets.only(top: type.px(18)),
      itemCount: 8,
      itemBuilder: (context, i) => Container(
        height: type.px(96),
        margin: EdgeInsets.fromLTRB(type.px(26), 0, type.px(24), type.px(20)),
        decoration: BoxDecoration(
          color: m.well,
          borderRadius: BorderRadius.circular(type.px(10)),
          border: Border.all(color: m.rule, width: type.px(2)),
        ),
      ),
    );
  }
}
