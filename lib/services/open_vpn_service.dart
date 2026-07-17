import 'dart:async';
import 'dart:developer' as dev;
import 'package:axevpn_flutter/openvpn_flutter.dart' as axe;

class OpenVpnService {
  late axe.OpenVPN _openvpn;
  final _stageController = StreamController<OpenVpnStage>.broadcast();
  OpenVpnStage _currentStage = OpenVpnStage.disconnected;
  bool _initialized = false;
  bool _processStarted = false;
  String _lastRawStage = '';

  Stream<OpenVpnStage> get stageStream => _stageController.stream;
  OpenVpnStage get currentStage => _currentStage;
  String get lastRawStage => _lastRawStage;
  bool get processStarted => _processStarted;

  String get stageLabel {
    switch (_currentStage) {
      case OpenVpnStage.disconnected:
        return 'Disconnected';
      case OpenVpnStage.connecting:
        return _connectingLabel;
      case OpenVpnStage.connected:
        return 'Connected';
      case OpenVpnStage.disconnecting:
        return 'Disconnecting...';
      case OpenVpnStage.authenticating:
        return 'Authenticating...';
    }
  }

  String get _connectingLabel {
    if (_lastRawStage.contains('prepare')) return 'Preparing...';
    if (_lastRawStage.contains('auth')) return 'Authenticating...';
    if (_lastRawStage.contains('get_config')) return 'Getting config...';
    if (_lastRawStage.contains('tcp_connect')) return 'TCP connecting...';
    if (_lastRawStage.contains('udp_connect')) return 'UDP connecting...';
    if (_lastRawStage.contains('assign_ip')) return 'Assigning IP...';
    if (_lastRawStage.contains('resolve')) return 'Resolving DNS...';
    if (_lastRawStage.contains('wait')) return 'Waiting for network...';
    return 'Connecting...';
  }

  void _log(String msg) => dev.log('[BULB_VPN] $msg');

  Future<void> initialize() async {
    _log('initialize()');
    if (_initialized) return;

    _openvpn = axe.OpenVPN(
      onVpnStatusChanged: (status) {
        if (status != null) {
          _log('status: bytesIn=${status.byteIn}, bytesOut=${status.byteOut}, duration=${status.duration}');
        }
      },
      onVpnStageChanged: (stage, raw) {
        _log('native stage=$stage, raw=$raw');
        _lastRawStage = raw;
        final mapped = _mapStage(stage);
        _currentStage = mapped;
        if (mapped != OpenVpnStage.disconnected) {
          _processStarted = true;
        }
        _stageController.add(mapped);
      },
    );

    await _openvpn.initialize(
      groupIdentifier: 'group.app.bulbvpn.com',
      providerBundleIdentifier: 'app.bulbvpn.com.VPNExtension',
      localizedDescription: 'BULB VPN',
    );

    _openvpn.setNotificationConfig(
      appName: 'BULB VPN',
      connectedTitle: 'Connected to BULB VPN',
      connectedSubtitle: 'Your connection is secure',
      channelName: 'bulb_vpn_channel',
      channelDescription: 'VPN connection status',
    );

    _log('initialize() done');
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    _log('requestPermission()');
    try {
      final result = await _openvpn.requestPermissionAndroid();
      _log('requestPermission result: $result');
      return result;
    } catch (e) {
      _log('requestPermission error: $e');
      return false;
    }
  }

  Future<void> connect(String config, String serverName, {List<String>? bypassPackages, String? username, String? password}) async {
    _log('connect() server=$serverName configLen=${config.length} bypass=$bypassPackages user=$username');
    if (!_initialized) await initialize();

    _currentStage = OpenVpnStage.connecting;
    _stageController.add(OpenVpnStage.connecting);

    try {
      _openvpn.connect(
        config,
        serverName,
        bypassPackages: bypassPackages,
        username: username,
        password: password,
      );
      _log('connect() dispatched with user=$username bypass=${bypassPackages?.length ?? 0}');
    } catch (e) {
      _log('connect() FAILED: $e');
      _currentStage = OpenVpnStage.disconnected;
      _stageController.add(OpenVpnStage.disconnected);
    }
  }

  Future<void> disconnect() async {
    _log('disconnect()');
    _currentStage = OpenVpnStage.disconnecting;
    _stageController.add(OpenVpnStage.disconnecting);
    try {
      _openvpn.disconnect();
    } catch (e) {
      _log('disconnect error: $e');
    }
  }

  void resetState() {
    _currentStage = OpenVpnStage.disconnected;
  }

  OpenVpnStage stage() => _currentStage;
  bool isConnected() => _currentStage == OpenVpnStage.connected;

  OpenVpnStage _mapStage(axe.VPNStage stage) {
    switch (stage) {
      case axe.VPNStage.connected:
        return OpenVpnStage.connected;
      case axe.VPNStage.connecting:
      case axe.VPNStage.prepare:
      case axe.VPNStage.authenticating:
      case axe.VPNStage.wait_connection:
      case axe.VPNStage.get_config:
      case axe.VPNStage.tcp_connect:
      case axe.VPNStage.udp_connect:
      case axe.VPNStage.assign_ip:
      case axe.VPNStage.resolve:
        return OpenVpnStage.connecting;
      case axe.VPNStage.disconnecting:
      case axe.VPNStage.exiting:
        return OpenVpnStage.disconnecting;
      case axe.VPNStage.disconnected:
      case axe.VPNStage.denied:
      case axe.VPNStage.error:
      case axe.VPNStage.unknown:
        return OpenVpnStage.disconnected;
      default:
        return OpenVpnStage.disconnected;
    }
  }

  void dispose() {
    _log('dispose()');
    _stageController.close();
  }
}

enum OpenVpnStage { disconnected, connecting, connected, disconnecting, authenticating }
