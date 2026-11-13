import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bulbvpn/modules/core/reality/reality_health.dart';
import 'package:bulbvpn/modules/core/relay_memory.dart';
import 'package:bulbvpn/modules/core/relay_verdict.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/shared/widgets/staggered_in.dart' show formatRate;

/// How strong a claim a relay row is making. The order matters: `ownSession` is
/// a fact about this user's network, `fleetProbe` is a guess from someone else's
/// datacenter, and `handshake` only proves a TLS process answered — which is
/// exactly the number that used to sit at the top of this list while the relay
/// behind it carried nothing.
enum ReadingKind {
  ownSession,
  fleetProbe,
  handshake,
  measuring,

  /// A fleet probe dialled this relay and no session completed. Worse than
  /// `unreachable`: something is known here, and it is bad.
  probeFailed,
  unreachable,
  info,
  none,
}

/// One measured fact about a relay, split so the row can set the figure large
/// and the qualifier small without either being cut off on a 360 px phone.
///
/// [qualifier] always names the source of the number. A bare `761 ms` reads like
/// a speed; `761 ms` over `TLS only` reads like what it is.
class RelayReading {
  const RelayReading(this.kind, {required this.value, required this.qualifier});

  final ReadingKind kind;
  final String value;
  final String qualifier;

  /// Whether the figure is a number or the em dash the code prints when there
  /// is no figure. A stalled probe is a fleet probe with nothing measured, and
  /// the verdict column has to say so rather than borrow the fleet's `PROBED`.
  bool get hasFigure => value != '—';

  /// The finding this reading supports. Stated once, here, so the connect
  /// card's tariff sheet and the relay slip cannot grade the same host
  /// differently — and so a round trip that only proves a TLS process answered
  /// is never printed as a pass.
  RelayVerdict get verdict => switch (kind) {
    ReadingKind.ownSession => RelayVerdict.carried,
    ReadingKind.fleetProbe => hasFigure
        ? RelayVerdict.probed
        : RelayVerdict.unproven,
    ReadingKind.handshake => RelayVerdict.unproven,
    ReadingKind.probeFailed || ReadingKind.unreachable => RelayVerdict.blocked,
    ReadingKind.measuring || ReadingKind.info || ReadingKind.none =>
      RelayVerdict.untried,
  };

  static const missing = RelayReading(
    ReadingKind.none,
    value: '—',
    qualifier: 'not measured',
  );
}

/// Every measurement the relay list is allowed to print, in one place, so a row
/// can never confuse "this phone carried traffic through here" with "a probe
/// answered a few hours ago".
class RelayEvidence {
  const RelayEvidence({required this.proven, required this.health});

  static const empty = RelayEvidence(proven: {}, health: null);

  /// Dial keys this device completed a session through, with the rate it saw.
  final Map<String, SessionProof> proven;

  /// Fleet measurements, or null when the bundled/fetched file is unusable.
  final RealityHealth? health;

  SessionProof? proofFor(String dial) => proven[dial];

  bool isProven(String dial) => proofFor(dial) != null;

  RealityHealthEntry? fleetFor(String relayId) {
    final source = health;
    if (source == null || !source.usable) return null;
    return source.byId[relayId];
  }

  /// The fleet file is one measurement round shared by every relay, so its age
  /// is the age of the whole snapshot.
  DateTime? get fleetAt =>
      (health?.usable ?? false) ? health!.generatedAt : null;

  /// Strongest available reading for one relay: the user's own session first,
  /// then the fleet probe, then this device's TLS handshake.
  RelayReading reading({
    String? dial,
    String? relayId,
    ServerPing? ping,
    DateTime? now,
  }) {
    final own = dial == null ? null : proofFor(dial);
    if (own != null) {
      return RelayReading(
        ReadingKind.ownSession,
        value: formatRate(own.bytesPerSecond),
        qualifier: 'you · ${_ago(own.at, now)}',
      );
    }

    final id = relayId;
    final fleet = id == null ? null : fleetFor(id);
    if (fleet != null) {
      // A failure carries no age: `RealityHealth.usable` already refuses to
      // serve a snapshot older than 18 h, and this column has to stay short
      // enough to read on a 360 dp phone.
      if (!fleet.ok) {
        return const RelayReading(
          ReadingKind.probeFailed,
          value: '—',
          qualifier: 'probe failed',
        );
      }
      if (fleet.bps <= 0) {
        return const RelayReading(
          ReadingKind.fleetProbe,
          value: '—',
          qualifier: 'probe stalled',
        );
      }
      final stamp = fleetAt == null
          ? 'probe'
          : 'probe · ${_ago(fleetAt!, now)}';
      return RelayReading(
        ReadingKind.fleetProbe,
        value: formatRate(fleet.bps),
        qualifier: stamp,
      );
    }

    if (ping == null) return RelayReading.missing;
    return switch (ping.status) {
      PingStatus.pending => const RelayReading(
        ReadingKind.measuring,
        value: '—',
        qualifier: 'measuring',
      ),
      PingStatus.timeout => const RelayReading(
        ReadingKind.unreachable,
        value: '—',
        qualifier: 'no handshake',
      ),
      PingStatus.ok => RelayReading(
        ReadingKind.handshake,
        value: '${ping.ms} ms',
        qualifier: 'TLS only',
      ),
    };
  }
}

String _ago(DateTime at, DateTime? now) {
  final since = (now ?? DateTime.now()).difference(at);
  if (since.inMinutes < 1) return 'now';
  if (since.inHours < 1) return '${since.inMinutes} min';
  if (since.inDays < 1) return '${since.inHours} h';
  return since.inDays == 1 ? '1 day' : '${since.inDays} days';
}

/// Loads both sources once per sheet open. Proofs and the health snapshot are
/// small local reads; a failure in either leaves the row showing `—`.
final relayEvidenceProvider = FutureProvider<RelayEvidence>((ref) async {
  final results = await Future.wait([
    RelayMemory.sessionProofs('reality'),
    RelayMemory.sessionProofs('softether'),
    RealityHealthStore.load(),
  ]);
  final proven = <String, SessionProof>{};
  for (final entry in [
    results[0] as List<SessionProof>,
    results[1] as List<SessionProof>,
  ]) {
    for (final proof in entry) {
      // Newest wins: sessionProofs returns most recent first, so the first
      // write for a dial is the freshest measurement of it.
      proven.putIfAbsent(proof.dial, () => proof);
    }
  }
  return RelayEvidence(proven: proven, health: results[2] as RealityHealth?);
});
