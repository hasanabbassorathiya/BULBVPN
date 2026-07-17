import 'dart:async';
import 'package:axevpn_flutter/v2ray_flutter.dart' as axe;

enum V2RayVpnStage { disconnected, connecting, connected, disconnecting, error }

class V2RayService {
  late axe.V2Ray _v2ray;
  final _stageController = StreamController<V2RayVpnStage>.broadcast();
  V2RayVpnStage _currentStage = V2RayVpnStage.disconnected;
  bool _initialized = false;

  Stream<V2RayVpnStage> get stageStream => _stageController.stream;
  V2RayVpnStage get currentStage => _currentStage;

  String get stageLabel {
    switch (_currentStage) {
      case V2RayVpnStage.disconnected:
        return 'Disconnected';
      case V2RayVpnStage.connecting:
        return 'Connecting...';
      case V2RayVpnStage.connected:
        return 'Connected';
      case V2RayVpnStage.disconnecting:
        return 'Disconnecting...';
      case V2RayVpnStage.error:
        return 'Error';
    }
  }

  void _log(String msg) => print('[BULB_VPN] $msg');

  Future<void> initialize() async {
    _log('V2Ray initialize()');
    if (_initialized) return;

    _v2ray = axe.V2Ray(
      onVpnStatusChanged: (status) {
        if (status != null) {
          _log('status: bytesIn=${status.bytesIn}, bytesOut=${status.bytesOut}');
        }
      },
      onVpnStageChanged: (stage, rawStage) {
        _log('native stage=$stage, raw=$rawStage');
        final mapped = _mapStage(stage);
        _currentStage = mapped;
        _stageController.add(mapped);
      },
    );

    await _v2ray.initialize();
    _log('V2Ray initialize() done');
    _initialized = true;
  }

  Future<void> connect(
    String configJson,
    String name, {
    axe.V2RaySubProtocol subProtocol = axe.V2RaySubProtocol.vless,
    List<String>? bypassPackages,
  }) async {
    _log('connect() name=$name configLen=${configJson.length} subProtocol=$subProtocol bypass=${bypassPackages?.length ?? 0}');
    if (!_initialized) await initialize();

    _currentStage = V2RayVpnStage.connecting;
    _stageController.add(V2RayVpnStage.connecting);

    try {
      await _v2ray.connect(
        configJson,
        name,
        subProtocol: subProtocol,
        bypassPackages: bypassPackages,
      );
      _log('connect() dispatched');
    } catch (e) {
      _log('connect() FAILED: $e');
      _currentStage = V2RayVpnStage.error;
      _stageController.add(V2RayVpnStage.error);
    }
  }

  Future<void> disconnect() async {
    _log('disconnect()');
    _currentStage = V2RayVpnStage.disconnecting;
    _stageController.add(V2RayVpnStage.disconnecting);
    try {
      await _v2ray.disconnect();
    } catch (e) {
      _log('disconnect error: $e');
    }
  }

  Future<axe.V2RayStatus> status() => _v2ray.status();

  bool isConnected() => _currentStage == V2RayVpnStage.connected;

  V2RayVpnStage _mapStage(axe.V2RayStage stage) {
    switch (stage) {
      case axe.V2RayStage.connected:
        return V2RayVpnStage.connected;
      case axe.V2RayStage.preparing:
      case axe.V2RayStage.connecting:
        return V2RayVpnStage.connecting;
      case axe.V2RayStage.disconnecting:
        return V2RayVpnStage.disconnecting;
      case axe.V2RayStage.error:
      case axe.V2RayStage.denied:
      case axe.V2RayStage.unknown:
        return V2RayVpnStage.error;
      case axe.V2RayStage.disconnected:
        return V2RayVpnStage.disconnected;
    }
  }

  void dispose() {
    _log('dispose()');
    _stageController.close();
  }
}
