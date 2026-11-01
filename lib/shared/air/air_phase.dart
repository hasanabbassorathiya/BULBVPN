/// The eight states the interface is allowed to show. One phase, one word.
enum AirPhase {
  idle,
  preparing,
  connecting,
  verifying,
  connected,
  closing,
  failed,
  offline,
}

extension AirPhaseX on AirPhase {
  /// Work in flight: a tap must not start a second attempt.
  bool get isBusy =>
      this == AirPhase.preparing ||
      this == AirPhase.connecting ||
      this == AirPhase.verifying ||
      this == AirPhase.closing;

  /// The attempt ended without a working data path.
  bool get isFault => this == AirPhase.failed || this == AirPhase.offline;

  /// The single word shown beside the aperture.
  String get word => switch (this) {
    AirPhase.idle => 'Standby',
    AirPhase.preparing => 'Preparing',
    AirPhase.connecting => 'Connecting',
    AirPhase.verifying => 'Verifying',
    AirPhase.connected => 'Connected',
    AirPhase.closing => 'Closing',
    AirPhase.failed => 'Blocked',
    AirPhase.offline => 'No internet',
  };
}
