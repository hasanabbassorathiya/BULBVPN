import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The last moment the live tunnel actually carried a request.
///
/// The engines report CONNECTED from their handshake, so the orb alone is not
/// evidence. This value is written only by a probe that completed through the
/// TUN (connect gate, steady-state watchdog, or a measured transfer), and is
/// cleared the moment the session ends. The UI can therefore say how long ago
/// traffic was verified instead of implying that a green light is proof.
class DataProofState {
  const DataProofState({
    required this.at,
    required this.engine,
    this.bytesPerSecond = 0,
  });

  final DateTime at;
  final String engine;

  /// Non-zero only when the proof came from a measured transfer.
  final int bytesPerSecond;
}

final dataProofProvider = StateProvider<DataProofState?>((ref) => null);
