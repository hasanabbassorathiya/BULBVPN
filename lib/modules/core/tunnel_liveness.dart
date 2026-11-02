import 'package:flutter/services.dart';

/// What Android still holds for us, independent of this process's memory.
///
/// The REALITY tunnel is owned by `XrayVPNService`, which the plugin declares
/// in its own process (`:RunSoLibXrayDaemon`). That process keeps forwarding
/// when the UI process is restarted, so "this Dart object has no session" is
/// not evidence that the tunnel is gone. These three flags are read from the
/// framework and from the process table instead.
class SystemVpnState {
  final bool reported;
  final bool vpnNetworkUp;
  final bool realityDaemonUp;

  const SystemVpnState({
    this.reported = false,
    this.vpnNetworkUp = false,
    this.realityDaemonUp = false,
  });

  static const unknown = SystemVpnState();

  factory SystemVpnState.fromMap(Map<Object?, Object?> map) => SystemVpnState(
    reported: true,
    vpnNetworkUp: map['vpnNetworkUp'] == true,
    realityDaemonUp: map['realityDaemonUp'] == true,
  );
}

enum OrphanTunnel {
  /// Nothing to adopt.
  none,

  /// Our daemon is still carrying the tunnel this app started.
  reality,

  /// A VPN is up, but it is not ours to claim or stop.
  otherOwner,
}

/// Pure decision over [SystemVpnState]; kept off the platform channel so the
/// rules that decide what the UI is allowed to claim are testable.
class TunnelLiveness {
  const TunnelLiveness._();

  static OrphanTunnel classify(
    SystemVpnState state, {
    required bool realitySessionRecorded,
  }) {
    if (!state.reported || !state.vpnNetworkUp) return OrphanTunnel.none;
    if (!state.realityDaemonUp) return OrphanTunnel.otherOwner;
    // The daemon is alive, but without a session we recorded there is no
    // tunnel this UI ever claimed, so nothing may be adopted from it.
    return realitySessionRecorded ? OrphanTunnel.reality : OrphanTunnel.none;
  }

  /// The persisted relay is only discarded once no tunnel of ours survives.
  static bool clearsSessionOnRestart(
    SystemVpnState state, {
    required bool realitySessionRecorded,
  }) => classify(state, realitySessionRecorded: realitySessionRecorded) !=
      OrphanTunnel.reality;

  /// True when a stop was requested but our daemon still holds the tunnel.
  static bool realityTunnelStillHeld(SystemVpnState state) =>
      state.reported && state.vpnNetworkUp && state.realityDaemonUp;
}

/// Asks the platform for the current [SystemVpnState]. A channel that is
/// missing or slow returns [SystemVpnState.unknown]: an unanswered query is
/// never read as a live tunnel, so it cannot manufacture a false Connected.
Future<SystemVpnState> querySystemVpnState() async {
  try {
    final raw = await const MethodChannel('app.bulbvpn.com/softether')
        .invokeMethod<Object?>('systemState')
        .timeout(const Duration(seconds: 2));
    if (raw is Map<Object?, Object?>) return SystemVpnState.fromMap(raw);
  } catch (_) {}
  return SystemVpnState.unknown;
}
