import 'package:bulbvpn/shared/providers/connection_state_provider.dart';

/// True while a tunnel is actually installed on the device, whether or not its
/// first byte has been judged yet.
///
/// `analyzing` is the window between a completed handshake and the throughput
/// verdict. It holds a real session, so recovery that fires inside it tears
/// down the very tunnel it is waiting to prove.
bool holdsLiveSession(ConnectionStatus status) =>
    status == ConnectionStatus.connected || status == ConnectionStatus.analyzing;
