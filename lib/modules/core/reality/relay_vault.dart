import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/reality/relay_link.dart';

/// The servers the user brought.
///
/// Kept apart from the bundled catalog because they are not the same kind of
/// thing: a catalog relay is chosen by this app and can be replaced by the next
/// build, while a vault relay is the user's own server and losing it on upgrade
/// means losing the only connection they trust. The vault is written to the
/// app's private preferences, the same place the session and relay history
/// already live, so an imported link is no more exposed on a rooted phone than
/// the user's saved relay history already is.
class RelayVault {
  RelayVault._();

  static const _key = 'bulb_relay_vault_v1';

  /// A generous ceiling, not a paging strategy. Past this many profiles the
  /// sheet is unusable and the import has almost certainly been handed a
  /// scraped public list rather than a subscription.
  static const maxRelays = 200;

  static List<RealityRelay>? _cached;

  /// The read currently in flight, so concurrent callers share one parse of the
  /// same file rather than each publishing their own snapshot of it.
  static Future<List<RealityRelay>>? _reading;

  /// Bumped by every write, which is how a read knows its bytes are stale.
  static int _writes = 0;

  static List<RealityRelay> get cached => _cached ?? const <RealityRelay>[];

  static Future<List<RealityRelay>> load() {
    final memo = _cached;
    if (memo != null) return Future.value(memo);
    var pending = _reading;
    if (pending != null) return pending;
    final generation = _writes;
    pending = _read().whenComplete(() {
      // A write that landed during this read installed a newer cache and is
      // responsible for clearing the slot; nulling it here would only let a
      // second read start against the same stale file.
      if (_writes == generation) _reading = null;
    });
    _reading = pending;
    return pending;
  }

  static Future<List<RealityRelay>> _read() async {
    final generation = _writes;
    List<RealityRelay> relays = const <RealityRelay>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        relays = parse(raw);
      }
    } catch (_) {
      relays = const <RealityRelay>[];
    }
    // Published only while nothing has written since this read began. The first
    // import after a launch races the hydration read it triggered — these bytes
    // were taken before the server the user just pasted existed, and posting
    // them would empty the list underneath a sheet that just said "added".
    if (generation == _writes) _cached = relays;
    return _cached ?? relays;
  }

  /// Pure reader, so the on-disk shape is testable without a preferences
  /// plugin. A body this app cannot read is dropped whole rather than
  /// half-restored: a vault of one usable server out of nine imported is worse
  /// than an empty vault the user can refill.
  static List<RealityRelay> parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const <RealityRelay>[];
    }
    if (decoded is! List) return const <RealityRelay>[];
    final relays = <RealityRelay>[];
    final seen = <String>{};
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final relay = RealityRelay.fromStoredJson(
        entry.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (relay == null) continue;
      if (!seen.add(relay.id)) continue;
      relays.add(relay);
      if (relays.length >= maxRelays) break;
    }
    return relays;
  }

  /// Merges [incoming] into the vault, keyed by dial address and port.
  ///
  /// Re-pasting the same link replaces its entry instead of stacking a second
  /// identical server, which is what makes "refresh my subscription" safe to
  /// press twice.
  static Future<List<RealityRelay>> merge(List<RealityRelay> incoming) async {
    final current = await load();
    final byDial = {for (final relay in current) relay.dialKey: relay};
    for (final relay in incoming) {
      byDial[relay.dialKey] = relay;
    }
    final next = byDial.values.take(maxRelays).toList(growable: false);
    await _write(next);
    return next;
  }

  static Future<List<RealityRelay>> remove(String id) async {
    final current = await load();
    final next = [
      for (final relay in current)
        if (relay.id != id) relay,
    ];
    await _write(next);
    return next;
  }

  static Future<List<RealityRelay>> clear() async {
    await _write(const <RealityRelay>[]);
    return const <RealityRelay>[];
  }

  static Future<void> _write(List<RealityRelay> relays) async {
    _cached = relays;
    _writes++;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (relays.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(
          _key,
          jsonEncode([for (final relay in relays) relay.toStoredJson()]),
        );
      }
    } catch (_) {}
  }

  @visibleForTesting
  static void resetCache() {
    _cached = null;
    _reading = null;
    _writes = 0;
  }
}

/// Imported relays, watchable so the sheet and the connect order agree on one
/// list rather than each loading their own copy.
final importedRelaysProvider =
    StateNotifierProvider<ImportedRelaysNotifier, List<RealityRelay>>(
      (ref) => ImportedRelaysNotifier(),
    );

class ImportedRelaysNotifier extends StateNotifier<List<RealityRelay>> {
  ImportedRelaysNotifier() : super(RelayVault.cached) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final loaded = await RelayVault.load();
    if (mounted) state = loaded;
  }

  /// Imports link or subscription-body text. Returns the profiles that landed,
  /// so the caller can name what was added instead of announcing a bare
  /// success.
  ///
  /// A fetched subscription arrives here too, rather than through a second
  /// method that would fetch it again: the preview the user approved and the
  /// list that gets stored must be read from the same bytes.
  Future<List<RealityRelay>> addLinks(String text) async {
    final relays = relaysFromSubscription(text);
    if (relays.isEmpty) return const <RealityRelay>[];
    state = await RelayVault.merge(relays);
    return relays;
  }

  Future<void> remove(String id) async {
    state = await RelayVault.remove(id);
  }

  Future<void> clear() async {
    state = await RelayVault.clear();
  }
}
