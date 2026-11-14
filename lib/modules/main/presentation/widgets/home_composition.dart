import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';

class HomeViewState {
  const HomeViewState({
    required this.phase,
    required this.statusTitle,
    required this.statusDetail,
    required this.networkLabel,
    required this.clockLabel,
    required this.pingLabel,
    required this.downLabel,
    required this.upLabel,
    required this.trafficLabel,
    required this.protocolLabel,
    required this.relayLabel,
    required this.exitIp,
    required this.exitLocation,
    this.flagCode = '',
    this.trustTier,
    required this.live,
    this.proven = false,
    this.measuring = false,
    this.proofAge,
    this.tight = false,
    this.connectStage,
    this.busyWitness,
  });

  final AirPhase phase;
  final String statusTitle;
  final String statusDetail;
  final String networkLabel;
  final String clockLabel;
  final String pingLabel;
  final String downLabel;
  final String upLabel;

  /// Cumulative bytes this session, not a rate. The credit meter needs a
  /// total; printing the rate twice would be a reading the card cannot back.
  final String trafficLabel;
  final String protocolLabel;
  final String relayLabel;
  final String exitIp;
  final String exitLocation;
  final String flagCode;
  final TrustTier? trustTier;
  final bool live;

  /// True only while the watchdog holds a recent byte-count proof that traffic
  /// crossed this tunnel. `live` alone is an engine claim and may not be
  /// decorated as verification.
  final bool proven;
  final bool measuring;

  /// How long ago a byte was last confirmed crossing this tunnel. `proven`
  /// says a reading exists; this says how old it is, which is the part the
  /// credit window prints. Null when the session has never been proven.
  final Duration? proofAge;
  final bool tight;

  /// Non-null while a dial is in flight; switches the detail line to the
  /// three-step trace instead of an indeterminate spinner.
  final ConnectStage? connectStage;

  /// What the dial is doing right now, from the controller (engine, path N of
  /// M, relay). Real work, never an invented percentage.
  final String? busyWitness;
}

