import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:openvpn_dart/openvpn_dart.dart';
import 'package:openvpn_dart/vpn_status.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:bulbvpn/modules/core/log.dart';

/// Thin wrapper around the `openvpn_dart` engine (ics-openvpn on Android,
/// NetworkExtension on iOS/macOS). Exposes the app's connection lifecycle as
/// [ConnectionStatus] (the only status the engine reports) plus cumulative
/// session tunnel bytes via [tunnelStatistics].
///
/// Credentials are always carried inline in the `.ovpn` config as an
/// `<auth-user-pass>` block — the engine has no separate username/password.
class VpnService {
  VpnService._internal();
  static final VpnService _instance = VpnService._internal();
  factory VpnService() => _instance;

  final Log _log = Log();
  final OpenVPNDart _openVpn = OpenVPNDart();
  bool _initialized = false;

  ConnectionStatus? _currentStatus;
  int _totalDownload = 0;
  int _totalUpload = 0;

  ConnectionStatus? get currentStatus => _currentStatus;
  bool get isConnected => _currentStatus == ConnectionStatus.connected;
  bool get isConnecting =>
      _currentStatus == ConnectionStatus.connecting ||
      _currentStatus == ConnectionStatus.unknown;
  bool get isDisconnecting => _currentStatus == ConnectionStatus.disconnecting;

  /// Cumulative session bytes; fed to the UI's throughput gauge.
  int get totalDownload => _totalDownload;
  int get totalUpload => _totalUpload;

  Future<void> initialize() async {
    if (_initialized) {
      _log.addLog('[VpnService] Already initialized');
      return;
    }
    _initialized = true;

    final groupIdentifier = 'group.com.bulbvpn.app';
    final localizedDescription = 'BULBVPN Secure Connection';
    final providerBundleIdentifier = 'app.bulbvpn.com.VPNExtension';

    _log.addLog('[VpnService] Initializing OpenVPNDart with:');
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
          _log.addLog('[VpnService] Initial status: ${status.name}');
        },
      );
      _log.addLog('[VpnService] OpenVPNDart initialized successfully');
    } catch (e, stackTrace) {
      _initialized = false;
      _log.addLog('[VpnService] ERROR initializing OpenVPNDart: $e');
      _log.addLog('[VpnService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Real-time engine status events (connecting/connected/disconnected/...).
  Stream<ConnectionStatus> statusStream() {
    return _openVpn.statusStream().map((status) {
      _currentStatus = status;
      _log.addLog('[VpnService] Status changed: ${status.name}');
      try {
        FirebaseCrashlytics.instance.log('vpn status ${status.name}');
      } catch (_) {}
      return status;
    });
  }

  Future<void> connect({
    required String config,
    required String name,
  }) async {
    if (!_initialized) {
      throw StateError('VpnService not initialized. Call initialize() first.');
    }

    _log.addLog('[VpnService] Connecting to VPN...');
    _log.addLog('[VpnService] Config name: $name');
    _log.addLog('[VpnService] Config length: ${config.length}');
    _log.addLog('[VpnService] Has inline auth-user-pass: ${config.contains('<auth-user-pass>')}');

    try {
      await _openVpn.connect(config);
      _log.addLog('[VpnService] Connect requested (status follows via statusStream)');
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

  Future<bool> checkAndRequestPermissions() async {
    _log.addLog('[VpnService] Checking and requesting permissions...');
    final notifOk = await requestNotificationPermission();
    _log.addLog('[VpnService] notification permission: $notifOk');
    if (Platform.isAndroid) {
      final vpnOk = await requestAndroidPermission();
      _log.addLog('[VpnService] vpn permission: $vpnOk');
      return notifOk && vpnOk;
    }
    return notifOk;
  }

  Future<ConnectionStatus> getStatus() async {
    if (!_initialized) return ConnectionStatus.disconnected;
    final status = await _openVpn.getVPNStatus();
    _currentStatus = status;
    return status;
  }

  Future<bool> isTunnelRunning() async {
    return await _openVpn.isConnected();
  }

  /// Reads cumulative session traffic and caches it for the UI gauge.
  Future<void> refreshTunnelStatistics() async {
    try {
      final stats = await _openVpn.tunnelStatistics();
      if (stats != null) {
        _totalDownload = stats.totalDownload;
        _totalUpload = stats.totalUpload;
      }
    } catch (e) {
      _log.addLog('[VpnService] tunnelStatistics error: $e');
    }
  }

  void dispose() {
    _log.addLog('[VpnService] Disposing...');
    if (_initialized) {
      try {
        _openVpn.disconnect();
      } catch (_) {}
    }
    _initialized = false;
    _log.addLog('[VpnService] Disposed');
  }
}
