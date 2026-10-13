import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bulbvpn/modules/core/vpn_service.dart';
import 'package:bulbvpn/core/utils/screen_security.dart';

enum ConnectionStatus {
  disconnected,
  loading,
  connecting,
  analyzing,
  connected,
  disconnecting,
  error,
  noInternet,
}

extension ConnectionStatusExtension on ConnectionStatus {
  int toInt() => index;
  static ConnectionStatus fromInt(int value) => ConnectionStatus.values[value];
}

class ConnectionState {
  final ConnectionStatus status;
  final VPNStage? vpnStage;
  final VpnStatus? vpnStatus;

  const ConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.vpnStage,
    this.vpnStatus,
  });

  ConnectionState copyWith({
    ConnectionStatus? status,
    VPNStage? vpnStage,
    VpnStatus? vpnStatus,
  }) {
    return ConnectionState(
      status: status ?? this.status,
      vpnStage: vpnStage ?? this.vpnStage,
      vpnStatus: vpnStatus ?? this.vpnStatus,
    );
  }
}

final connectionStateProvider =
    StateNotifierProvider<ConnectionStateNotifier, ConnectionState>((ref) {
  return ConnectionStateNotifier();
});

class ConnectionStateNotifier extends StateNotifier<ConnectionState> {
  static const String _connectionStatusKey = 'connection_status';
  final VpnService _vpnService = VpnService();

  ConnectionStateNotifier() : super(const ConnectionState()) {
    _initVpnListeners();
  }

  Future<void> _initVpnListeners() async {
    // Initialize the VPN service
    try {
      await _vpnService.initialize();
    } catch (e, stackTrace) {
      debugPrint('[ConnectionStateNotifier] ERROR initializing VPN service: $e');
      debugPrint('[ConnectionStateNotifier] Stack trace: $stackTrace');
      setError();
      return;
    }

    // Listen to VPN stage changes via the VpnService
    // The VpnService already has internal listeners that update its state
    // We'll poll the status periodically to keep UI in sync
    _startStatusPolling();
  }

  Timer? _pollingTimer;

  void _startStatusPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      try {
        final stage = await _vpnService.getStage();
        final status = await _vpnService.getStatus();
        _updateFromVpnStage(stage, status);
      } catch (e) {
        debugPrint('[ConnectionStateNotifier] Error polling VPN status: $e');
      }
    });
  }

  void _updateFromVpnStage(VPNStage stage, VpnStatus status) {
    // Surface a failed connection attempt (e.g. auth_failed) as an error state.
    if (_vpnService.consumeConnectionFailed()) {
      debugPrint('[ConnectionStateNotifier] Connection failed (auth_failed)');
      state = state.copyWith(
        status: ConnectionStatus.error,
        vpnStage: stage,
        vpnStatus: status,
      );
      ScreenSecurity.disableScreenSecurity();
      return;
    }

    final lastStage = state.vpnStage;
    final lastByteIn = state.vpnStatus?.byteIn;
    final bool stageChanged = lastStage != stage;
    final bool statsChanged = lastByteIn != status.byteIn;
    if (!stageChanged && !statsChanged) return;

    if (stageChanged) {
      debugPrint('[ConnectionStateNotifier] VPN Stage: ${stage.name}, Status: ${status.toJson()}');
    }
    ConnectionStatus newStatus;
    switch (stage) {
      case VPNStage.connecting:
      case VPNStage.authenticating:
      case VPNStage.authentication:
      case VPNStage.prepare:
      case VPNStage.wait_connection:
      case VPNStage.vpn_generate_config:
      case VPNStage.get_config:
      case VPNStage.tcp_connect:
      case VPNStage.udp_connect:
      case VPNStage.assign_ip:
      case VPNStage.resolve:
        newStatus = ConnectionStatus.connecting;
        break;
      case VPNStage.connected:
        newStatus = ConnectionStatus.connected;
        break;
      case VPNStage.disconnecting:
      case VPNStage.exiting:
        newStatus = ConnectionStatus.disconnecting;
        break;
      case VPNStage.denied:
      case VPNStage.error:
        newStatus = ConnectionStatus.error;
        break;
      case VPNStage.disconnected:
      case VPNStage.unknown:
        newStatus = ConnectionStatus.disconnected;
        break;
    }

    // Keep an error visible until the user starts a new attempt; otherwise the
    // stage poller would silently downgrade it back to Standby.
    if (state.status == ConnectionStatus.error &&
        (newStatus == ConnectionStatus.disconnected ||
            newStatus == ConnectionStatus.disconnecting)) {
      state = state.copyWith(vpnStage: stage, vpnStatus: status);
      return;
    }

    if (newStatus != state.status) {
      state = state.copyWith(
        status: newStatus,
        vpnStage: stage,
        vpnStatus: status,
      );
      debugPrint('[ConnectionStateNotifier] Updated connection status to: $newStatus');
    } else {
      // Update vpnStage and vpnStatus even if connection status didn't change
      state = state.copyWith(
        vpnStage: stage,
        vpnStatus: status,
      );
    }

    // Handle screen security based on connection state
    if (newStatus == ConnectionStatus.connected) {
      ScreenSecurity.enableScreenSecurity();
    } else if (newStatus == ConnectionStatus.disconnected ||
        newStatus == ConnectionStatus.error) {
      ScreenSecurity.disableScreenSecurity();
    }
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_connectionStatusKey, state.status.toInt());
      debugPrint('[ConnectionStateNotifier] Saved connection state: ${state.status}');
    } catch (e) {
      debugPrint('[ConnectionStateNotifier] Error saving connection state: $e');
    }
  }

  void setLoading() => _setStatus(ConnectionStatus.loading);
  void setConnected() => _setStatus(ConnectionStatus.connected);
  void setDisconnected() => _setStatus(ConnectionStatus.disconnected);
  void setDisconnecting() => _setStatus(ConnectionStatus.disconnecting);
  void setError() => _setStatus(ConnectionStatus.error);
  void setNoInternet() => _setStatus(ConnectionStatus.noInternet);
  void setAnalyzing() => _setStatus(ConnectionStatus.analyzing);

  void _setStatus(ConnectionStatus status) {
    state = state.copyWith(status: status);
    _saveState();
    
    if (status == ConnectionStatus.connected) {
      ScreenSecurity.enableScreenSecurity();
    } else if (status == ConnectionStatus.disconnected) {
      ScreenSecurity.disableScreenSecurity();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _vpnService.dispose();
    super.dispose();
  }
}