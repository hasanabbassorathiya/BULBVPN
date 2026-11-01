import '../providers/connection_state_provider.dart';
import 'air_phase.dart';

/// The only place app-level status becomes an interface phase.
AirPhase airPhaseFor(ConnectionStatus status) => switch (status) {
  ConnectionStatus.disconnected => AirPhase.idle,
  ConnectionStatus.loading => AirPhase.preparing,
  ConnectionStatus.connecting => AirPhase.connecting,
  ConnectionStatus.analyzing => AirPhase.verifying,
  ConnectionStatus.connected => AirPhase.connected,
  ConnectionStatus.disconnecting => AirPhase.closing,
  ConnectionStatus.error => AirPhase.failed,
  ConnectionStatus.noInternet => AirPhase.offline,
};
