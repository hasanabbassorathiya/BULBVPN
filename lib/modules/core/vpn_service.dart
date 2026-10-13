import 'dart:async';
import 'dart:io' show Platform;
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:bulbvpn/modules/core/log.dart';

class VpnService {
  VpnService._internal();
  static final VpnService _instance = VpnService._internal();
  factory VpnService() => _instance;

  final Log _log = Log();
  late final OpenVPN _openVpn;
  bool _initialized = false;
  StreamSubscription? _stageSubscription;
  StreamSubscription? _statusSubscription;

  VPNStage? _currentStage;
  VpnStatus? _currentStatus;
  DateTime? _lastConnectedOn;
  bool _connectionFailed = false;

  /// True when OpenVPN reported a failed connection attempt (e.g. auth_failed).
  bool get connectionFailed => _connectionFailed;

  /// Returns the failure flag once and clears it.
  bool consumeConnectionFailed() {
    final failed = _connectionFailed;
    _connectionFailed = false;
    return failed;
  }

  VPNStage? get currentStage => _currentStage;
  VpnStatus? get currentStatus => _currentStatus;
  bool get isConnected => _currentStage == VPNStage.connected;
  bool get isConnecting => _currentStage == VPNStage.connecting || _currentStage == VPNStage.authenticating || _currentStage == VPNStage.authentication;
  bool get isDisconnecting => _currentStage == VPNStage.disconnecting;

  Future<void> initialize() async {
    if (_initialized) {
      _log.addLog('[VpnService] Already initialized');
      return;
    }
    // Set initialized flag early to prevent race conditions
    _initialized = true;

    _openVpn = OpenVPN(
      onVpnStatusChanged: _onVpnStatusChanged,
      onVpnStageChanged: _onVpnStageChanged,
    );

    final groupIdentifier = 'group.com.bulbvpn.app';
    final localizedDescription = 'BULBVPN Secure Connection';
    final providerBundleIdentifier = Platform.isMacOS
        ? 'com.bulbvpn.app.macos.VPNExtension'
        : 'com.bulbvpn.app.VPNExtension';

    _log.addLog('[VpnService] Initializing OpenVPN with:');
    _log.addLog('[VpnService]   groupIdentifier: $groupIdentifier');
    _log.addLog('[VpnService]   providerBundleIdentifier: $providerBundleIdentifier');
    _log.addLog('[VpnService]   localizedDescription: $localizedDescription');
    _log.addLog('[VpnService]   Platform: ${Platform.operatingSystem}');

    try {
      await _openVpn.initialize(
        groupIdentifier: groupIdentifier,
        providerBundleIdentifier: providerBundleIdentifier,
        localizedDescription: localizedDescription,
        lastStatus: (status) {
          _currentStatus = status;
          _log.addLog('[VpnService] Initial status: ${status.toJson()}');
        },
        lastStage: (stage) {
          _currentStage = stage;
          _log.addLog('[VpnService] Initial stage: ${stage.name}');
        },
      );
      _log.addLog('[VpnService] OpenVPN initialized successfully');
    } catch (e, stackTrace) {
      _initialized = false; // Reset on failure
      _log.addLog('[VpnService] ERROR initializing OpenVPN: $e');
      _log.addLog('[VpnService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  void _onVpnStatusChanged(VpnStatus? status) {
    _currentStatus = status;
    // Log only on session transitions; byte counters update every second.
    final connectedOn = status?.connectedOn;
    if (connectedOn == _lastConnectedOn) return;
    _lastConnectedOn = connectedOn;
    _log.addLog('[VpnService] Status changed: ${status?.toJson() ?? 'null'}');
  }

  void _onVpnStageChanged(VPNStage stage, String rawStage) {
    _currentStage = stage;
    if (rawStage == 'auth_failed') {
      _connectionFailed = true;
    }
    _log.addLog('[VpnService] Stage changed: ${stage.name} (raw: $rawStage)');
  }

  Future<void> connect({
    required String config,
    required String name,
    String? username,
    String? password,
    bool? certIsRequired,
  }) async {
    if (!_initialized) {
      throw StateError('VpnService not initialized. Call initialize() first.');
    }

    _log.addLog('[VpnService] Connecting to VPN...');
    _log.addLog('[VpnService] Config name: $name');
    _log.addLog('[VpnService] Has username: ${username != null}');
    _log.addLog('[VpnService] Has password: ${password != null}');
    _log.addLog('[VpnService] Config length: ${config.length}');
    _connectionFailed = false;

    try {
      // Android: VPN Gate uses username/password auth, not client certificates
      // iOS/macOS: certIsRequired: true is required to avoid "stuck on connecting"
      // If explicitly provided, use it; otherwise default to platform behavior
      final effectiveCertIsRequired = certIsRequired ?? !Platform.isAndroid;
      
      await _openVpn.connect(
        config,
        name,
        username: username,
        password: password,
        bypassPackages: [],
        certIsRequired: effectiveCertIsRequired,
      );
      _log.addLog('[VpnService] Connect call completed (certIsRequired: $effectiveCertIsRequired)');
    } catch (e, stackTrace) {
      _log.addLog('[VpnService] ERROR connecting: $e');
      _log.addLog('[VpnService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (!_initialized) {
      _log.addLog('[VpnService] Disconnect called but not initialized');
      return;
    }

    _log.addLog('[VpnService] Disconnecting VPN...');
    _openVpn.disconnect();
    _log.addLog('[VpnService] Disconnect call completed');
  }

  Future<bool> requestAndroidPermission() async {
    if (!Platform.isAndroid) return true;

    _log.addLog('[VpnService] Requesting Android VPN permission...');
    try {
      final granted = await _openVpn.requestPermissionAndroid();
      _log.addLog('[VpnService] Android permission result: $granted');
      return granted;
    } catch (e, stackTrace) {
      _log.addLog('[VpnService] ERROR requesting Android permission: $e');
      _log.addLog('[VpnService] Stack trace: $stackTrace');
      return false;
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;

    _log.addLog('[VpnService] Requesting Android notification permission...');
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) {
        _log.addLog('[VpnService] Notification permission already granted');
        return true;
      }
      final result = await Permission.notification.request();
      _log.addLog('[VpnService] Notification permission request result: $result');
      return result.isGranted;
    } catch (e, stackTrace) {
      _log.addLog('[VpnService] ERROR requesting notification permission: $e');
      _log.addLog('[VpnService] Stack trace: $stackTrace');
      return false;
    }
  }

  Future<void> checkAndRequestPermissions() async {
    _log.addLog('[VpnService] Checking and requesting permissions...');
    await requestNotificationPermission();
    if (Platform.isAndroid) {
      await requestAndroidPermission();
    }
  }

  Future<VpnStatus> getStatus() async {
    if (!_initialized) {
      return VpnStatus.empty();
    }
    return await _openVpn.status();
  }

  Future<VPNStage> getStage() async {
    if (!_initialized) {
      return VPNStage.disconnected;
    }
    return await _openVpn.stage();
  }

  Future<bool> isTunnelRunning() async {
    return await _openVpn.isConnected();
  }

  void dispose() {
    _log.addLog('[VpnService] Disposing...');
    _stageSubscription?.cancel();
    _statusSubscription?.cancel();
    if (_initialized) {
      _openVpn.disconnect();
    }
    _initialized = false;
    _log.addLog('[VpnService] Disposed');
  }
}