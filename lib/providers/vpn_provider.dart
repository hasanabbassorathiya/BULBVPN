import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/connection_history.dart';
import '../models/imported_server.dart';
import '../screens/paywall_screen.dart';
import '../services/history_service.dart';
import '../services/tier_service.dart';
import '../services/analytics_service.dart';
import '../services/v2ray_service.dart';
import '../services/v2ray_config_parser.dart';
import '../services/server_storage_service.dart';
import '../services/storage_service.dart';
import '../services/notification_triggers.dart';
import 'package:axevpn_flutter/v2ray_flutter.dart' as axe_v2ray;

enum VPNStatus { disconnected, connecting, connected, disconnecting }

class VPNProvider extends ChangeNotifier {
  VPNStatus _status = VPNStatus.disconnected;
  DateTime? _connectedAt;
  double _downloadSpeed = 0;
  double _uploadSpeed = 0;
  double _totalDownload = 0;
  double _totalUpload = 0;
  Timer? _durationTimer;
  Timer? _speedTimer;
  Timer? _connectingTimeout;
  Timer? _autoReconnectTimer;
  Timer? _connectionReminderTimer;

  V2RayService? _v2rayService;
  final ServerStorageService _serverStorage = ServerStorageService();
  List<ImportedServer> _importedServers = [];
  ImportedServer? _selectedImportedServer;
  bool _initialized = false;
  bool _isSubscriber = false;
  String? _tierBlockReason;

  late StorageService _storageService;
  late HistoryService _historyService;
  late TierService _tierService;

  List<String> _favoriteIds = [];
  List<String> _bypassPackages = [];
  bool _autoConnect = false;
  bool _killSwitch = false;
  bool _autoReconnect = false;
  bool _darkMode = true;
  bool _userInitiatedDisconnect = false;
  bool _killSwitchActive = false;
  int _autoReconnectAttempts = 0;
  static const int _maxAutoReconnectAttempts = 3;

  VPNStatus get status => _status;
  double get downloadSpeed => _downloadSpeed;
  double get uploadSpeed => _uploadSpeed;
  bool get isConnected => _status == VPNStatus.connected;
  bool get isConnecting => _status == VPNStatus.connecting;
  bool get isDisconnected => _status == VPNStatus.disconnected;
  bool get isInitialized => _initialized;
  bool get isSubscriber => _isSubscriber;
  bool get showUpgradePrompt => !_isSubscriber;
  String? get tierBlockReason => _tierBlockReason;
  TierService get tierService => _tierService;
  bool get isKillSwitchActive => _killSwitchActive;
  int get autoReconnectAttempts => _autoReconnectAttempts;
  List<String> get bypassPackages => List.unmodifiable(_bypassPackages);
  String get vpnStageLabel => _v2rayService?.stageLabel ?? 'Disconnected';
  List<ImportedServer> get importedServers => List.unmodifiable(_importedServers);
  ImportedServer? get selectedImportedServer => _selectedImportedServer;
  bool get autoConnect => _autoConnect;
  bool get killSwitch => _killSwitch;
  bool get autoReconnect => _autoReconnect;
  bool get darkMode => _darkMode;
  List<ConnectionRecord> get connectionHistory => _historyService.getRecords();

  ImportedServer? get bestServer {
    if (_importedServers.isEmpty) return null;
    return _importedServers.first;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    _storageService = StorageService();
    await _storageService.initialize();
    _historyService = HistoryService();
    _tierService = TierService();
    await _tierService.initialize();

    _autoConnect = _storageService.autoConnect;
    _killSwitch = _storageService.killSwitch;
    _autoReconnect = _storageService.autoReconnect;
    _darkMode = _storageService.darkMode;
    _favoriteIds = List.from(_storageService.favorites);
    _bypassPackages = List.from(_storageService.getStringList('bypass_packages') ?? []);

    _v2rayService = V2RayService();
    _v2rayService!.stageStream.listen(_onV2RayStageChanged);
    _importedServers = await _serverStorage.loadServers();

    _initialized = true;
    notifyListeners();

    NotificationTriggers().recordActiveDate();
    NotificationTriggers().checkWelcomeBack();
    _startConnectionReminderTimer();

    if (_importedServers.isNotEmpty) {
      Future.delayed(const Duration(seconds: 3), () {
        if (isDisconnected && _importedServers.isNotEmpty) {
          _selectedImportedServer ??= _importedServers.first;
          connect();
        }
      });
    }
  }

  void _onV2RayStageChanged(V2RayVpnStage stage) {
    switch (stage) {
      case V2RayVpnStage.connected:
        _status = VPNStatus.connected;
        _connectedAt = DateTime.now();
        _killSwitchActive = false;
        _startDurationTimer();
        _recordConnectionStart();
        AnalyticsService().logConnected(
          server: _selectedImportedServer?.name ?? 'Unknown',
          country: _selectedImportedServer?.address ?? 'Unknown',
          protocol: _selectedImportedServer?.protocol.name ?? 'v2ray',
        );
        break;
      case V2RayVpnStage.connecting:
        _status = VPNStatus.connecting;
        _startConnectingTimeout();
        break;
      case V2RayVpnStage.disconnecting:
        _status = VPNStatus.disconnecting;
        break;
      case V2RayVpnStage.disconnected:
        _handleDisconnect(false);
        break;
      case V2RayVpnStage.error:
        _handleDisconnect(false);
        break;
    }
    notifyListeners();
  }

  void _handleDisconnect(bool userInitiated) {
    final wasConnected = _status == VPNStatus.connected;
    _status = VPNStatus.disconnected;
    _connectingTimeout?.cancel();
    _stopTimers();
    _resetSpeed();

    if (_killSwitch && wasConnected) {
      _killSwitchActive = true;
    }

    if (wasConnected) {
      _recordConnectionEnd();
      AnalyticsService().logDisconnected(
        durationSeconds: _connectedAt != null ? DateTime.now().difference(_connectedAt!).inSeconds : 0,
        dataUsedMB: (_totalDownload + _totalUpload) / 1024,
      );
    }

    if (!userInitiated && wasConnected && _autoReconnect && !_killSwitchActive) {
      _startAutoReconnect();
    } else {
      _autoReconnectAttempts = 0;
    }
  }

  Future<void> connect() async {
    if (_selectedImportedServer == null) {
      if (_importedServers.isNotEmpty) {
        _selectedImportedServer = _importedServers.first;
      } else {
        _tierBlockReason = 'No servers imported. Add a server first.';
        notifyListeners();
        return;
      }
    }

    _status = VPNStatus.connecting;
    notifyListeners();

    try {
      await _v2rayService!.initialize();
      await _v2rayService!.connect(
        _selectedImportedServer!.configJson,
        _selectedImportedServer!.name,
        subProtocol: _v2raySubProtocolFor(_selectedImportedServer!.protocol),
        bypassPackages: _bypassPackages,
      );
      _storageService.setLastServerId(_selectedImportedServer!.id);
    } catch (e) {
      print('[BULB_VPN] connect FAILED: $e');
      _status = VPNStatus.disconnected;
      _selectedImportedServer = null;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _userInitiatedDisconnect = true;
    _killSwitchActive = false;
    _autoReconnectTimer?.cancel();
    _autoReconnectAttempts = 0;
    _status = VPNStatus.disconnecting;
    _connectingTimeout?.cancel();
    notifyListeners();

    _stopTimers();

    if (!_isSubscriber) {
      await _tierService.recordSessionEnd();
    }

    try {
      await _v2rayService?.disconnect();
    } catch (e) {
      print('[BULB_VPN] disconnect error: $e');
      _status = VPNStatus.disconnected;
      notifyListeners();
    }
  }

  Future<void> toggleConnection() async {
    if (isDisconnected) {
      await connect();
    } else {
      await disconnect();
    }
  }

  axe_v2ray.V2RaySubProtocol _v2raySubProtocolFor(V2RayProtocol p) {
    switch (p) {
      case V2RayProtocol.vmess: return axe_v2ray.V2RaySubProtocol.vmess;
      case V2RayProtocol.vless: return axe_v2ray.V2RaySubProtocol.vless;
      case V2RayProtocol.trojan: return axe_v2ray.V2RaySubProtocol.trojan;
      case V2RayProtocol.shadowsocks: return axe_v2ray.V2RaySubProtocol.shadowsocks;
      case V2RayProtocol.unknown: return axe_v2ray.V2RaySubProtocol.unknown;
    }
  }

  Future<bool> importConfig(String rawInput) async {
    final parsed = V2RayConfigParser.parse(rawInput);
    if (parsed == null) return false;

    final server = ImportedServer(
      id: 'v2ray_${DateTime.now().millisecondsSinceEpoch}',
      name: parsed.name,
      address: parsed.address,
      port: parsed.port,
      protocol: parsed.protocol,
      configJson: parsed.jsonConfig,
      importedAt: DateTime.now(),
    );

    _importedServers.add(server);
    await _serverStorage.saveServers(_importedServers);
    notifyListeners();
    return true;
  }

  Future<bool> importSubscription(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return false;

      final configs = V2RayConfigParser.parseSubscription(response.body);
      if (configs.isEmpty) return false;

      for (final config in configs) {
        final server = ImportedServer(
          id: 'v2ray_${DateTime.now().millisecondsSinceEpoch}_${config.address}',
          name: config.name,
          address: config.address,
          port: config.port,
          protocol: config.protocol,
          configJson: config.jsonConfig,
          importedAt: DateTime.now(),
        );
        _importedServers.add(server);
      }
      await _serverStorage.saveServers(_importedServers);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> removeImportedServer(String id) async {
    _importedServers.removeWhere((s) => s.id == id);
    if (_selectedImportedServer?.id == id) {
      _selectedImportedServer = null;
    }
    await _serverStorage.saveServers(_importedServers);
    notifyListeners();
  }

  void selectImportedServer(ImportedServer server) {
    _selectedImportedServer = server;
    notifyListeners();
  }

  void toggleFavoriteServer(String id) {
    if (_favoriteIds.contains(id)) {
      _favoriteIds.remove(id);
    } else {
      _favoriteIds.add(id);
    }
    _storageService.setFavorites(_favoriteIds);
    notifyListeners();
  }

  bool isFavoriteServer(String id) => _favoriteIds.contains(id);

  void setBypassPackages(List<String> packages) {
    _bypassPackages = List.from(packages);
    _storageService.setStringList('bypass_packages', packages);
    notifyListeners();
  }

  void _startConnectingTimeout() {
    _connectingTimeout?.cancel();
    _connectingTimeout = Timer(const Duration(seconds: 30), () {
      if (_status == VPNStatus.connecting) {
        disconnect();
      }
    });
  }

  void _startAutoReconnect() {
    if (_autoReconnectAttempts >= _maxAutoReconnectAttempts) {
      _autoReconnectAttempts = 0;
      notifyListeners();
      return;
    }
    _autoReconnectAttempts++;
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = Timer(const Duration(seconds: 3), () async {
      if (_status == VPNStatus.disconnected && _selectedImportedServer != null) {
        await connect();
      }
    });
    notifyListeners();
  }

  void _startConnectionReminderTimer() {
    _connectionReminderTimer?.cancel();
    _connectionReminderTimer = Timer.periodic(const Duration(hours: 6), (_) {
      if (_status == VPNStatus.disconnected) {
        NotificationTriggers().checkConnectionReminder(isConnected: false, autoConnect: _autoConnect);
      }
    });
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isConnected) notifyListeners();
    });
    _speedTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (isConnected) {
        final random = 15 + (DateTime.now().millisecond % 185);
        _downloadSpeed = random.toDouble();
        _uploadSpeed = (random * 0.3).toDouble();
        _totalDownload += _downloadSpeed * 2 / 8;
        _totalUpload += _uploadSpeed * 2 / 8;
        notifyListeners();
      }
    });
  }

  void _stopTimers() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _speedTimer?.cancel();
    _speedTimer = null;
  }

  void _resetSpeed() {
    _downloadSpeed = 0;
    _uploadSpeed = 0;
    _connectedAt = null;
  }

  String get formattedDuration {
    if (_connectedAt == null) return '00:00:00';
    final diff = DateTime.now().difference(_connectedAt!);
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get dataUsed {
    if (!isConnected) return '0 MB';
    final total = _totalDownload + _totalUpload;
    if (total > 1024 * 1024) return '${(total / (1024 * 1024)).toStringAsFixed(1)} GB';
    if (total > 1024) return '${(total / 1024).toStringAsFixed(1)} MB';
    return '${total.toStringAsFixed(0)} KB';
  }

  void setAutoConnect(bool value) {
    _autoConnect = value;
    _storageService.setAutoConnect(value);
    notifyListeners();
  }

  void setKillSwitch(bool value) {
    _killSwitch = value;
    _storageService.setKillSwitch(value);
    notifyListeners();
  }

  void setAutoReconnect(bool value) {
    _autoReconnect = value;
    _storageService.setAutoReconnect(value);
    notifyListeners();
  }

  void setDarkMode(bool value) {
    _darkMode = value;
    _storageService.setDarkMode(value);
    notifyListeners();
  }

  void disableKillSwitch() {
    _killSwitchActive = false;
    notifyListeners();
  }

  void setSubscriber(bool value) {
    _isSubscriber = value;
    _tierBlockReason = null;
    notifyListeners();
  }

  DateTime? _pendingConnectionStart;

  void _recordConnectionStart() {
    _pendingConnectionStart = DateTime.now();
  }

  void _recordConnectionEnd() {
    final start = _pendingConnectionStart ?? _connectedAt;
    if (start == null) return;

    final duration = DateTime.now().difference(start).inSeconds;
    final dataMB = (_totalDownload + _totalUpload) / 1024;
    final record = ConnectionRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serverName: _selectedImportedServer?.name ?? 'Unknown',
      country: _selectedImportedServer?.address ?? '',
      countryCode: '',
      flag: '',
      protocol: _selectedImportedServer?.protocol.name ?? 'v2ray',
      connectedAt: start,
      disconnectedAt: DateTime.now(),
      durationSeconds: duration,
      dataUsedMB: dataMB,
      wasSuccessful: duration > 0,
    );
    _historyService.addRecord(record);
    _pendingConnectionStart = null;
  }

  void clearHistory() {
    _historyService.clearRecords();
    notifyListeners();
  }

  Future<bool> showPaywall() async {
    final ctx = _navigatorContext;
    if (ctx == null) return false;
    final result = await Navigator.of(ctx).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PaywallScreen()),
    );
    return result == true;
  }

  BuildContext? _navigatorContext;
  void setNavigatorContext(BuildContext context) {
    _navigatorContext = context;
  }

  @override
  void dispose() {
    _stopTimers();
    _connectingTimeout?.cancel();
    _autoReconnectTimer?.cancel();
    _connectionReminderTimer?.cancel();
    _v2rayService?.dispose();
    super.dispose();
  }
}
