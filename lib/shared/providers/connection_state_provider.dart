import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvpn_dart/vpn_status.dart' as vpn_status;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/softether_vpn.dart';
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
  /// App-level connection status (superset: adds loading/analyzing/error/noInternet).
  final ConnectionStatus status;
  /// Engine status from openvpn_dart (connecting/connected/disconnecting/disconnected/unknown).
  final vpn_status.ConnectionStatus? vpnStatus;
  /// Cumulative session bytes downloaded (fed to the throughput gauge).
  final int totalDownload;

  const ConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.vpnStatus,
    this.totalDownload = 0,
  });

  ConnectionState copyWith({
    ConnectionStatus? status,
    vpn_status.ConnectionStatus? vpnStatus,
    int? totalDownload,
  }) {
    return ConnectionState(
      status: status ?? this.status,
      vpnStatus: vpnStatus ?? this.vpnStatus,
      totalDownload: totalDownload ?? this.totalDownload,
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

  StreamSubscription? _statusSub;
  Timer? _statsTimer;
  bool _holdEngineEvents = false;
  DateTime? _ignoreDisconnectUntil;

  /// The OS tunnel is already up. Ignore a stale `disconnected` replay
  /// from the OpenVPN engine while the UI catches up.
  void adoptLiveTunnel({required bool holdEngine}) {
    _ignoreDisconnectUntil = DateTime.now().add(const Duration(seconds: 4));
    holdEngineEvents(holdEngine);
    setConnected();
  }

  /// While a SoftEther tunnel owns the session, ignore OpenVPN status events
  /// so a stray `disconnected` does not tear the UI back down.
  void holdEngineEvents(bool hold) {
    _holdEngineEvents = hold;
  }

  ConnectionStateNotifier() : super(const ConnectionState()) {
    _initVpnListeners();
  }

  Future<void> _initVpnListeners() async {
    try {
      await _vpnService.initialize();
      Log().addLog('[ConnectionStateNotifier] VPN service initialized');
    } catch (e, stackTrace) {
      Log().addLog('[ConnectionStateNotifier] ERROR initializing VPN service: $e');
      debugPrint('[ConnectionStateNotifier] Stack trace: $stackTrace');
      try {
        FirebaseCrashlytics.instance.recordError(e, stackTrace, reason: 'ConnectionStateNotifier init', fatal: false);
        FirebaseCrashlytics.instance.log('vpn init error: $e');
      } catch (_) {}
      setError();
      return;
    }

    // Event-driven: openvpn_dart pushes status transitions instead of the
    // 1s polling the old openvpn_flutter wrapper used.
    _statusSub = _vpnService.statusStream().listen(_onStatusEvent, onError: (e, s) {
      debugPrint('[ConnectionStateNotifier] statusStream error: $e');
      try {
        FirebaseCrashlytics.instance.recordError(e as Object, s, reason: 'vpn statusStream', fatal: false);
      } catch (_) {}
    });

    // Poll cumulative traffic for the throughput gauge (engine reports totals only).
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      try {
        if (_holdEngineEvents && state.status == ConnectionStatus.connected) {
          final tunnel = await SoftEtherVpn.status();
          if (!tunnel.running) {
            Log().addLog('[ConnectionStateNotifier] SoftEther tunnel dropped');
            holdEngineEvents(false);
            setDisconnected();
            return;
          }
        }
        final total = _holdEngineEvents
            ? await SoftEtherVpn.bytesReceived()
            : await _openVpnBytes();
        if (total != state.totalDownload) {
          state = state.copyWith(totalDownload: total);
        }
      } catch (e) {
        debugPrint('[ConnectionStateNotifier] Error polling tunnel statistics: $e');
      }
    });
  }

  Future<int> _openVpnBytes() async {
    await _vpnService.refreshTunnelStatistics();
    return _vpnService.totalDownload;
  }

  void _onStatusEvent(vpn_status.ConnectionStatus status) {
    if (_holdEngineEvents) return;
    final ignoreUntil = _ignoreDisconnectUntil;
    if (ignoreUntil != null &&
        DateTime.now().isBefore(ignoreUntil) &&
        (status == vpn_status.ConnectionStatus.disconnected ||
            status == vpn_status.ConnectionStatus.unknown)) {
      return;
    }
    // After rotation fails, keep the error screen. A stale NEVPN
    // `.connecting` must not flip the orb back to "opening tunnel".
    if (state.status == ConnectionStatus.error &&
        status == vpn_status.ConnectionStatus.connecting) {
      return;
    }
    debugPrint('[ConnectionStateNotifier] VPN status: ${status.name}');
    try {
      FirebaseCrashlytics.instance.log('vpn status ${status.name}');
    } catch (_) {}

    ConnectionStatus newStatus;
    switch (status) {
      case vpn_status.ConnectionStatus.connecting:
        newStatus = ConnectionStatus.connecting;
        break;
      case vpn_status.ConnectionStatus.connected:
        newStatus = ConnectionStatus.connected;
        break;
      case vpn_status.ConnectionStatus.disconnecting:
        newStatus = ConnectionStatus.disconnecting;
        break;
      case vpn_status.ConnectionStatus.disconnected:
      case vpn_status.ConnectionStatus.unknown:
        // Surface a disconnected-after-error as an error only if we were erroring.
        newStatus = state.status == ConnectionStatus.error
            ? ConnectionStatus.error
            : ConnectionStatus.disconnected;
        break;
    }

    if (newStatus == ConnectionStatus.connected) {
      ScreenSecurity.enableScreenSecurity();
    } else if (newStatus == ConnectionStatus.disconnected ||
        newStatus == ConnectionStatus.error) {
      ScreenSecurity.disableScreenSecurity();
    }

    if (newStatus != state.status || status != state.vpnStatus) {
      state = state.copyWith(status: newStatus, vpnStatus: status);
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
  void setConnecting() => _setStatus(ConnectionStatus.connecting);
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
    _statusSub?.cancel();
    _statsTimer?.cancel();
    _vpnService.dispose();
    super.dispose();
  }
}
