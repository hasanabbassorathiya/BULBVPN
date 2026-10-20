import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvpn_dart/vpn_status.dart' as vpn_status;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/relay_target.dart';
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
  return ConnectionStateNotifier(ref);
});

class ConnectionStateNotifier extends StateNotifier<ConnectionState> {
  ConnectionStateNotifier(this._ref) : super(const ConnectionState()) {
    // no_screenshot persists FLAG_SECURE in SharedPreferences and re-applies
    // it on every activity attach. A previous session would therefore black
    // out the app even after the tunnel is gone. Start unsecured and let the
    // real status transitions below enable it only for a live tunnel.
    ScreenSecurity.disableScreenSecurity();
    _initVpnListeners();
  }

  final Ref _ref;
  static const String _connectionStatusKey = 'connection_status';
  final VpnService _vpnService = VpnService();

  StreamSubscription? _statusSub;
  Timer? _statsTimer;
  bool _holdEngineEvents = false;
  DateTime? _ignoreDisconnectUntil;
  DateTime? _connectedAt;
  DateTime? _lastEngineCheck;
  int _engineMisses = 0;

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
    if (hold) {
      _connectedAt = DateTime.now();
      _engineMisses = 0;
    }
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
    // The same tick reconciles real tunnel liveness. A stale `connected` state
    // after the OS/VPN service died is the single worst failure mode for a VPN:
    // the orb says protected while traffic is already going out in the clear.
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      try {
        if (state.status == ConnectionStatus.connected) {
          if (_holdEngineEvents) {
            final tunnel = await SoftEtherVpn.status();
            if (!tunnel.isLive) {
              Log().addLog(
                '[ConnectionStateNotifier] SoftEther tunnel dropped '
                '(reason=${tunnel.reason.isEmpty ? 'unknown' : tunnel.reason})',
              );
              _dropUnclean();
              return;
            }
          } else {
            _engineMisses = await _reconcileEngineLiveness(_engineMisses);
            if (!mounted) return;
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

  /// Returns the number of consecutive liveness misses. Two misses (about
  /// 8 seconds) are required before dropping, so an engine that is briefly
  /// reconnecting does not flicker the UI back to disconnected.
  Future<int> _reconcileEngineLiveness(int misses) async {
    final now = DateTime.now();
    final connectedAt = _connectedAt;
    if (connectedAt != null && now.difference(connectedAt).inSeconds < 6) {
      return 0;
    }
    final last = _lastEngineCheck;
    if (last != null && now.difference(last).inSeconds < 4) {
      return misses;
    }
    _lastEngineCheck = now;
    final engine = await _vpnService.getStatus();
    final alive = engine == vpn_status.ConnectionStatus.connected ||
        engine == vpn_status.ConnectionStatus.connecting ||
        engine == vpn_status.ConnectionStatus.disconnecting;
    if (alive) return 0;
    final next = misses + 1;
    if (next < 2) return next;
    Log().addLog(
      '[ConnectionStateNotifier] Engine is ${engine.name} while UI says connected',
    );
    _dropUnclean();
    return 0;
  }

  /// Clears every piece of state that claims a tunnel exists.
  void _dropUnclean() {
    holdEngineEvents(false);
    _ref.read(connectedRelayProvider.notifier).state = null;
    _ref.read(softEtherHostProvider.notifier).state = null;
    _engineMisses = 0;
    _connectedAt = null;
    setDisconnected();
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
      _connectedAt = DateTime.now();
      _engineMisses = 0;
      ScreenSecurity.enableScreenSecurity();
    } else if (newStatus == ConnectionStatus.disconnected ||
        newStatus == ConnectionStatus.error) {
      _connectedAt = null;
      _ref.read(connectedRelayProvider.notifier).state = null;
      _ref.read(softEtherHostProvider.notifier).state = null;
      ScreenSecurity.disableScreenSecurity();
    }

    if (newStatus != state.status || status != state.vpnStatus) {
      state = state.copyWith(
        status: newStatus,
        vpnStatus: status,
        totalDownload: newStatus == ConnectionStatus.disconnected ||
                newStatus == ConnectionStatus.error
            ? 0
            : null,
      );
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
    if (status == ConnectionStatus.connected) {
      _connectedAt = DateTime.now();
      _engineMisses = 0;
    }
    final terminal = status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error ||
        status == ConnectionStatus.noInternet;
    if (terminal) {
      _connectedAt = null;
      _engineMisses = 0;
      _ref.read(connectedRelayProvider.notifier).state = null;
      _ref.read(softEtherHostProvider.notifier).state = null;
    }
    state = terminal
        ? state.copyWith(status: status, totalDownload: 0)
        : state.copyWith(status: status);
    _saveState();

    if (status == ConnectionStatus.connected) {
      ScreenSecurity.enableScreenSecurity();
    } else if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error ||
        status == ConnectionStatus.noInternet) {
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
