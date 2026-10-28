/// Short-lived, per-network memory of which relays accepted a TCP 443 dial.
///
/// Lantern keeps a background URL-test history so a connect starts from a
/// relay it just measured instead of probing the whole catalog again. This is
/// the same idea with a much smaller budget: a probe that succeeded a few
/// seconds ago on this network is trusted, a probe that failed is skipped, and
/// a network handover throws the whole table away because reachability is
/// network-specific.
class RelayReachability {
  RelayReachability({this.ttl = const Duration(seconds: 45)});

  final Duration ttl;
  final Map<String, RelayProbe> _entries = {};
  String _network = '';

  String get network => _network;

  /// Drops every entry when the physical network changes.
  void useNetwork(String network) {
    if (network == _network) return;
    _network = network;
    _entries.clear();
  }

  /// Returns null when the entry is missing or older than [ttl].
  RelayProbe? lookup(String dial, {DateTime? now}) {
    final probe = _entries[dial];
    if (probe == null) return null;
    final at = now ?? DateTime.now();
    if (at.difference(probe.at) >= ttl) {
      _entries.remove(dial);
      return null;
    }
    return probe;
  }

  void record(
    String dial, {
    required bool ok,
    Duration elapsed = Duration.zero,
    DateTime? at,
  }) {
    _entries[dial] = RelayProbe(
      ok: ok,
      elapsed: elapsed,
      at: at ?? DateTime.now(),
    );
    if (_entries.length > 64) {
      var oldestKey = '';
      DateTime? oldestAt;
      _entries.forEach((key, value) {
        final at = value.at;
        if (oldestAt == null || at.isBefore(oldestAt!)) {
          oldestAt = at;
          oldestKey = key;
        }
      });
      if (oldestKey.isNotEmpty) _entries.remove(oldestKey);
    }
  }

  void markDead(String dial) => record(dial, ok: false);
  void markAlive(String dial) => record(dial, ok: true);

  void clear() => _entries.clear();
}

class RelayProbe {
  const RelayProbe({required this.ok, required this.elapsed, required this.at});

  final bool ok;
  final Duration elapsed;
  final DateTime at;
}
