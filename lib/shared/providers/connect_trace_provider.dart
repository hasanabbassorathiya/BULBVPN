import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The live dial the controller is performing right now.
///
/// Every field is reported by the connect path itself, so the surface can say
/// what is actually happening ("REALITY · path 2 of 3 · Germany") instead of a
/// generic spinner. An unknown value stays empty rather than being filled with
/// a plausible-looking placeholder.
class ConnectTraceState {
  const ConnectTraceState({
    this.engine = '',
    this.attempt = 0,
    this.total = 0,
    this.relay = '',
    this.verifying = false,
  });

  /// Engine that owns the dial: REALITY, SoftEther, OpenVPN.
  final String engine;

  /// 1-based attempt within this engine's queue. 0 when not reported.
  final int attempt;

  /// How many paths this engine may try on this tap. 0 when not reported.
  final int total;

  /// Country or endpoint the controller is dialling, short enough for one line.
  final String relay;

  /// The handshake succeeded and the first-byte gate is running.
  final bool verifying;

  ConnectTraceState copyWith({
    String? engine,
    int? attempt,
    int? total,
    String? relay,
    bool? verifying,
  }) {
    return ConnectTraceState(
      engine: engine ?? this.engine,
      attempt: attempt ?? this.attempt,
      total: total ?? this.total,
      relay: relay ?? this.relay,
      verifying: verifying ?? this.verifying,
    );
  }

  /// One mono line under the stage trace.
  String get witness {
    final parts = <String>[
      if (engine.isNotEmpty) engine,
      if (verifying)
        'first bytes'
      else if (attempt > 0 && total > 0)
        'path $attempt of $total',
      if (relay.isNotEmpty) relay,
    ];
    return parts.join(' · ');
  }
}

final connectTraceProvider = StateProvider<ConnectTraceState?>((ref) => null);
