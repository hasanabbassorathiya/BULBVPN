import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/connection_history.dart';
import '../models/vpn_server.dart';
import '../models/vpn_status.dart';
import '../screens/paywall_screen.dart';
import '../services/history_service.dart';
import '../services/tier_service.dart';
import '../services/analytics_service.dart';
import '../services/vpn_gate_api.dart';
import '../services/open_vpn_service.dart';
import '../services/storage_service.dart';
import '../services/notification_triggers.dart';

export '../models/vpn_status.dart' show VPNStatus, ServerFilter;
export '../models/vpn_server.dart' show VpnServer;

class VPNProvider extends ChangeNotifier {
  VPNStatus _status = VPNStatus.disconnected;
  VpnServer? _selectedServer;
  DateTime? _connectedAt;
  double _downloadSpeed = 0;
  double _uploadSpeed = 0;
  double _totalDownload = 0;
  double _totalUpload = 0;
  ServerFilter _serverFilter = ServerFilter.all;
  String _searchQuery = '';
  Timer? _durationTimer;
  Timer? _speedTimer;
  Timer? _connectingTimeout;
  int _connectAttempts = 0;
  static const Duration _connectTimeout = Duration(seconds: 30);
  String? _pendingConfig;
  String? _pendingServerName;
  bool _connectCalled = false;

  late OpenVpnService _vpnService;
  late StorageService _storageService;
  late HistoryService _historyService;
  late TierService _tierService;
  bool _initialized = false;
  bool _isSubscriber = false;
  String? _tierBlockReason;

  StreamSubscription? _vpnStateSubscription;

  List<VpnServer> _servers = [];
  List<String> _favoriteIds = [];
  List<String> _bypassPackages = [];

  String _protocol = 'OpenVPN';
  bool _autoConnect = false;
  bool _killSwitch = false;
  bool _autoReconnect = false;
  bool _darkMode = true;
  bool _userInitiatedDisconnect = false;
  bool _killSwitchActive = false;
  int _autoReconnectAttempts = 0;
  static const int _maxAutoReconnectAttempts = 3;
  Timer? _autoReconnectTimer;
  Timer? _connectionReminderTimer;

  VPNStatus get status => _status;
  VpnServer? get selectedServer => _selectedServer;
  double get downloadSpeed => _downloadSpeed;
  double get uploadSpeed => _uploadSpeed;
  double get totalDownload => _totalDownload;
  double get totalUpload => _totalUpload;
  ServerFilter get serverFilter => _serverFilter;
  String get searchQuery => _searchQuery;
  String get protocol => _protocol;
  bool get autoConnect => _autoConnect;
  bool get killSwitch => _killSwitch;
  bool get autoReconnect => _autoReconnect;
  bool get darkMode => _darkMode;
  bool get isInitialized => _initialized;
  List<VpnServer> get servers => List.unmodifiable(_servers);
  bool get isKillSwitchActive => _killSwitchActive;
  int get autoReconnectAttempts => _autoReconnectAttempts;

  List<ConnectionRecord> get connectionHistory => _historyService.getRecords();

  bool get isConnected => _status == VPNStatus.connected;
  bool get isConnecting => _status == VPNStatus.connecting;
  bool get isDisconnected => _status == VPNStatus.disconnected;
  bool get isSubscriber => _isSubscriber;
  bool get showUpgradePrompt => !_isSubscriber;
  String? get tierBlockReason => _tierBlockReason;
  TierService get tierService => _tierService;

  VpnServer? get bestServer {
    if (_servers.isEmpty) return null;
    final scored = _servers.map((s) => MapEntry(s, _serverScore(s))).toList();
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.first.key;
  }

  List<VpnServer> get filteredServers {
    List<VpnServer> filtered = List.from(_servers);

    switch (_serverFilter) {
      case ServerFilter.favorites:
        filtered = filtered.where((s) => _favoriteIds.contains(s.id)).toList();
        break;
      case ServerFilter.americas:
        filtered = filtered.where((s) => ['US', 'CA', 'BR'].contains(s.countryCode)).toList();
        break;
      case ServerFilter.europe:
        filtered = filtered.where((s) => ['GB', 'DE', 'FR', 'NL', 'RO', 'UA', 'RU'].contains(s.countryCode)).toList();
        break;
      case ServerFilter.asia:
        filtered = filtered.where((s) => ['JP', 'SG', 'KR', 'IN', 'TH', 'VN'].contains(s.countryCode)).toList();
        break;
      case ServerFilter.lowPing:
        filtered.sort((a, b) => a.ping.compareTo(b.ping));
        break;
      case ServerFilter.all:
        break;
      case ServerFilter.streaming:
      case ServerFilter.gaming:
        break;
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((s) =>
        s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        s.country.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }

    return filtered;
  }

  List<VpnServer> get favoriteServers =>
      _servers.where((s) => _favoriteIds.contains(s.id)).toList();

  List<String> get bypassPackages => List.unmodifiable(_bypassPackages);
  String get vpnStageLabel => _vpnService.stageLabel;

  void setBypassPackages(List<String> packages) {
    _bypassPackages = List.from(packages);
    _storageService.setStringList('bypass_packages', packages);
    notifyListeners();
  }

  /// Calculate a server score (0-100) based on multiple factors.
  /// Higher is better.
  double _serverScore(VpnServer server) {
    double score = 100.0;
    score -= (server.ping / 4.0).clamp(0.0, 50.0);
    score -= (server.load * 30.0);
    if (server.isPremium) score += 10.0;
    return score.clamp(0.0, 100.0);
  }

  /// Get recommended servers sorted by score (best first).
  List<VpnServer> get recommendedServers {
    final scored = _servers.map((s) => MapEntry(s, _serverScore(s))).toList();
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(10).map((e) => e.key).toList();
  }

  /// Get top 3 recommended servers.
  List<VpnServer> get topRecommended {
    final scored = _servers.map((s) => MapEntry(s, _serverScore(s))).toList();
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(3).map((e) => e.key).toList();
  }

  /// Get streaming-optimized servers (top 10 by score in popular countries).
  List<VpnServer> get streamingServers {
    const streamingCountries = ['US', 'GB', 'DE', 'JP', 'KR', 'NL'];
    final candidates = _servers.where((s) => streamingCountries.contains(s.countryCode)).toList();
    final scored = candidates.map((s) => MapEntry(s, _serverScore(s))).toList();
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(10).map((e) => e.key).toList();
  }

  /// Get gaming-optimized servers (lowest latency).
  List<VpnServer> get gamingServers {
    final candidates = _servers.where((s) => s.ping < 80).toList();
    candidates.sort((a, b) => a.ping.compareTo(b.ping));
    return candidates.take(10).toList();
  }

  /// Score for a specific server (0-100).
  double scoreFor(VpnServer server) => _serverScore(server);

  /// Whether server is in top 3 by score.
  bool isRecommended(VpnServer server) => topRecommended.any((s) => s.id == server.id);

  /// Whether server is in streamingServers list.
  bool isStreamingOptimized(VpnServer server) => streamingServers.any((s) => s.id == server.id);

  /// Whether server is in gamingServers list.
  bool isGamingOptimized(VpnServer server) => gamingServers.any((s) => s.id == server.id);

  Future<void> initialize() async {
    if (_initialized) return;

    _vpnService = OpenVpnService();
    _storageService = StorageService();
    await _storageService.initialize();
    _historyService = HistoryService();
    _tierService = TierService();
    await _tierService.initialize();

    _protocol = _storageService.protocol;
    _autoConnect = _storageService.autoConnect;
    _killSwitch = _storageService.killSwitch;
    _autoReconnect = _storageService.autoReconnect;
    _darkMode = _storageService.darkMode;
    _favoriteIds = List.from(_storageService.favorites);
    _bypassPackages = List.from(_storageService.getStringList('bypass_packages') ?? []);

    _vpnStateSubscription = _vpnService.stageStream.listen(_onVpnStateChanged);

    await _fetchServers();

    final lastServerId = _storageService.lastServerId;
    if (lastServerId != null) {
      _selectedServer = _servers.where((s) => s.id == lastServerId).firstOrNull;
    }
    _selectedServer ??= bestServer;

    _initialized = true;
    notifyListeners();

    // Initialize notification triggers
    NotificationTriggers().recordActiveDate();
    NotificationTriggers().checkWelcomeBack();
    _startConnectionReminderTimer();

    // Auto-connect on app start if enabled
    if (_autoConnect && _selectedServer != null) {
      Future.delayed(const Duration(seconds: 2), () {
        if (isDisconnected) connect();
      });
    }
  }

  Future<void> _fetchServers() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final gateServers = await VpnGateApi.fetchServers();
        if (gateServers.isNotEmpty) {
          _servers = gateServers.map((gs) => VpnServer(
            id: gs.hostName,
            name: gs.countryLong,
            country: gs.countryLong,
            countryCode: gs.countryShort,
            flag: gs.flag,
            ping: gs.ping,
            load: (gs.sessions / 100).clamp(0.0, 1.0),
            openVpnConfig: gs.openVpnConfig,
          )).toList();
          return;
        }
      } catch (e) {
        dev.log('Fetch servers attempt $attempt failed: $e', name: 'BULB_VPN');
        if (attempt < 2) await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> refreshServers() async {
    await _fetchServers();
    notifyListeners();
  }

  void _onVpnStateChanged(OpenVpnStage state) {
    dev.log('Stage changed to: $state (attempt=$_connectAttempts, connectCalled=$_connectCalled)', name: 'BULB_VPN');

    if (!_connectCalled && state == OpenVpnStage.disconnected) {
      dev.log('Ignoring disconnected during init', name: 'BULB_VPN');
      return;
    }

    switch (state) {
      case OpenVpnStage.connected:
        _status = VPNStatus.connected;
        _connectedAt = DateTime.now();
        _connectAttempts = 0;
        _connectCalled = false;
        _pendingConfig = null;
        _pendingServerName = null;
        _connectingTimeout?.cancel();
        _startDurationTimer();
        _recordConnectionStart();
        dev.log('VPN CONNECTED', name: 'BULB_VPN');
        AnalyticsService().logConnected(
          server: _selectedServer?.name ?? 'Unknown',
          country: _selectedServer?.country ?? 'Unknown',
          protocol: _protocol,
        );
        break;
      case OpenVpnStage.connecting:
      case OpenVpnStage.authenticating:
        if (_status != VPNStatus.connecting) {
        }
        _status = VPNStatus.connecting;
        _startConnectingTimeout();
        dev.log('Connecting...', name: 'BULB_VPN');
        break;
      case OpenVpnStage.disconnecting:
        _status = VPNStatus.disconnecting;
        dev.log('Disconnecting...', name: 'BULB_VPN');
        break;
      case OpenVpnStage.disconnected:
        if (_status == VPNStatus.connecting && _connectAttempts < _maxAutoReconnectAttempts) {
          _connectAttempts++;
          dev.log('Process died, retrying... (attempt $_connectAttempts/$_maxAutoReconnectAttempts)', name: 'BULB_VPN');
          _retryConnect();
          notifyListeners();
          return;
        }
        final wasConnected = _status == VPNStatus.connected;
        _status = VPNStatus.disconnected;
        _connectAttempts = 0;
        _connectCalled = false;
        _pendingConfig = null;
        _pendingServerName = null;
        _connectingTimeout?.cancel();
        _stopTimers();
        _resetSpeed();
        dev.log('Disconnected (userInitiated=$_userInitiatedDisconnect, killSwitch=$_killSwitch, autoReconnect=$_autoReconnect)', name: 'BULB_VPN');

        if (_killSwitch && wasConnected) {
          _killSwitchActive = true;
          dev.log('Kill switch activated — internet blocked', name: 'BULB_VPN');
        }

        if (wasConnected) {
          _recordConnectionEnd();
          AnalyticsService().logDisconnected(
            durationSeconds: _connectedAt != null ? DateTime.now().difference(_connectedAt!).inSeconds : 0,
            dataUsedMB: (_totalDownload + _totalUpload) / 1024,
          );
        }

        if (!_userInitiatedDisconnect && wasConnected && _autoReconnect && !_killSwitchActive) {
          _startAutoReconnect();
        } else {
          _autoReconnectAttempts = 0;
        }

        // Check connection reminder after non-user-initiated disconnect
        if (!_userInitiatedDisconnect && wasConnected) {
          NotificationTriggers().checkConnectionReminder(
            isConnected: false,
            autoConnect: _autoConnect,
          );
        }

        _userInitiatedDisconnect = false;
        break;
    }
    notifyListeners();
  }

  void _startConnectingTimeout() {
    _connectingTimeout?.cancel();
    _connectingTimeout = Timer(_connectTimeout, () {
      if (_status == VPNStatus.connecting) {
        dev.log('Connecting timeout after ${_connectTimeout.inSeconds}s', name: 'BULB_VPN');
        disconnect();
      }
    });
  }

  Future<void> _retryConnect() async {
    if (_pendingConfig == null || _pendingServerName == null) return;

    await Future.delayed(const Duration(seconds: 3));

    if (_status != VPNStatus.connecting) return;

    if (_vpnService.processStarted) {
      dev.log('Process started but died, retrying...', name: 'BULB_VPN');
    } else {
      dev.log('Process never started, aborting retries', name: 'BULB_VPN');
      _status = VPNStatus.disconnected;
      _connectAttempts = _maxAutoReconnectAttempts;
      _connectCalled = false;
      notifyListeners();
      return;
    }

    _vpnService.resetState();
    try {
      await _vpnService.connect(_pendingConfig!, _pendingServerName!, bypassPackages: _bypassPackages, username: 'vpn', password: 'vpn');
    } catch (e) {
      dev.log('Retry failed: $e', name: 'BULB_VPN');
      _status = VPNStatus.disconnected;
      _connectCalled = false;
      notifyListeners();
    }
  }

  void setServerFilter(ServerFilter filter) {
    _serverFilter = filter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void selectServer(VpnServer server) {
    _selectedServer = server;
    _storageService.setLastServerId(server.id);
    AnalyticsService().logServerSelected(server: server.name, country: server.country);
    notifyListeners();
  }

  void toggleFavorite(String serverId) {
    if (_favoriteIds.contains(serverId)) {
      _favoriteIds.remove(serverId);
    } else {
      _favoriteIds.add(serverId);
    }
    _storageService.setFavorites(_favoriteIds);
    notifyListeners();
  }

  bool isFavorite(String serverId) => _favoriteIds.contains(serverId);

  Future<void> toggleConnection() async {
    if (isDisconnected) {
      await connect();
    } else {
      await disconnect();
    }
  }

  Future<void> connect() async {
    _selectedServer ??= bestServer;
    if (_selectedServer == null) {
      dev.log('No server selected, aborting', name: 'BULB_VPN');
      return;
    }

    if (!_isSubscriber) {
      if (_selectedServer!.isPremium) {
        _tierBlockReason = 'Premium server requires subscription';
        notifyListeners();
        return;
      }
      if (!_tierService.hasDataRemaining(false)) {
        _tierBlockReason = 'Daily data limit reached (500 MB/day)';
        notifyListeners();
        return;
      }
      if (!_tierService.hasSessionRemaining(false)) {
        _tierBlockReason = 'Session limit reached (1 hour/session)';
        notifyListeners();
        return;
      }
      if (!_tierService.canConnectToServer(_selectedServer!.id, _selectedServer!.isPremium, false)) {
        _tierBlockReason = 'Free tier limited to 3 servers';
        notifyListeners();
        return;
      }
    }

    _tierBlockReason = null;

    var config = _selectedServer!.openVpnConfig;
    if (config == null || config.isEmpty) {
      print('[BULB_VPN] ERROR: No OpenVPN config for server ${_selectedServer!.name}, aborting');
      _tierBlockReason = 'No VPN config available for this server';
      notifyListeners();
      return;
    }

    // Clean up SoftEther/PacketiX config headers — keep only standard OpenVPN directives
    config = _cleanConfig(config);

    // Validate config has required directives
    if (!config.contains('remote ')) {
      print('[BULB_VPN] ERROR: Config missing remote directive after cleaning');
      _tierBlockReason = 'Invalid VPN configuration';
      notifyListeners();
      return;
    }

    final serverName = _selectedServer!.name;
    print('[BULB_VPN] Connecting to: $serverName (${_selectedServer!.country}) configLen=${config.length}');
    print('[BULB_VPN] Config first 500 chars: ${config.substring(0, config.length > 500 ? 500 : config.length)}');
    print('[BULB_VPN] Server IP: ${_selectedServer!.openVpnConfig?.contains("remote") ?? false}');

    _status = VPNStatus.connecting;
    _connectAttempts = 0;
    _pendingConfig = config;
    _pendingServerName = serverName;
    notifyListeners();

    try {
      // Initialize VPN service (idempotent — only runs once)
      await _vpnService.initialize();

      // Wait for service to fully bind — critical for plugin stability
      await Future.delayed(const Duration(milliseconds: 2000));

      // Reset state
      _vpnService.resetState();
      _connectCalled = true;

      // Connect with VPN Gate credentials (username: vpn, password: vpn)
      await _vpnService.connect(config, serverName, bypassPackages: _bypassPackages, username: 'vpn', password: 'vpn');

      // Save last server
      _storageService.setLastServerId(_selectedServer!.id);

      // Record session for free tier
      if (!_isSubscriber) {
        await _tierService.recordSessionStart();
        await _tierService.addConnectedServer(_selectedServer!.id);
      }
    } catch (e) {
      dev.log('Connect FAILED: $e', name: 'BULB_VPN');
      AnalyticsService().logConnectionFailed(reason: e.toString());
      _status = VPNStatus.disconnected;
      _connectingTimeout?.cancel();
      _connectCalled = false;
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
    _connectAttempts = 0;
    _pendingConfig = null;
    _pendingServerName = null;
    notifyListeners();

    _stopTimers();

    if (!_isSubscriber) {
      await _tierService.recordSessionEnd();
    }

    try {
      await _vpnService.disconnect();
    } catch (e) {
      dev.log('Disconnect error: $e', name: 'BULB_VPN');
      _status = VPNStatus.disconnected;
      notifyListeners();
    }
  }

  void _startAutoReconnect() {
    if (_autoReconnectAttempts >= _maxAutoReconnectAttempts) {
      dev.log('Auto-reconnect max attempts reached', name: 'BULB_VPN');
      _autoReconnectAttempts = 0;
      notifyListeners();
      return;
    }
    _autoReconnectAttempts++;
    dev.log('Auto-reconnect attempt $_autoReconnectAttempts/$_maxAutoReconnectAttempts in 3s', name: 'BULB_VPN');
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = Timer(const Duration(seconds: 3), () async {
      if (_status == VPNStatus.disconnected && _selectedServer != null) {
        dev.log('Auto-reconnecting...', name: 'BULB_VPN');
        await connect();
      }
    });
    notifyListeners();
  }

  void _startConnectionReminderTimer() {
    _connectionReminderTimer?.cancel();
    _connectionReminderTimer = Timer.periodic(const Duration(hours: 6), (_) {
      if (_status == VPNStatus.disconnected) {
        NotificationTriggers().checkConnectionReminder(
          isConnected: false,
          autoConnect: _autoConnect,
        );
      }
    });
  }

  void disableKillSwitch() {
    _killSwitchActive = false;
    notifyListeners();
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

  /// Clean OpenVPN config — remove SoftEther/PacketiX boilerplate headers
  /// and extract only standard OpenVPN directives
  String _cleanConfig(String rawConfig) {
    final lines = rawConfig.split('\n');
    final cleaned = <String>[];
    bool inCommentBlock = false;

    for (final line in lines) {
      final trimmed = line.trim();

      // Skip the massive SoftEther header block
      if (trimmed.startsWith('###')) {
        inCommentBlock = true;
        continue;
      }
      if (inCommentBlock && trimmed.isEmpty) {
        inCommentBlock = false;
        continue;
      }
      if (inCommentBlock) continue;

      // Skip SoftEther-specific comments
      if (trimmed.startsWith('#') && (trimmed.contains('PacketiX') || trimmed.contains('SoftEther') || trimmed.contains('SOFTETHER'))) {
        continue;
      }

      // Keep standard OpenVPN directives
      cleaned.add(line);
    }

    final result = cleaned.join('\n');
    print('[BULB_VPN] Config cleaned: ${rawConfig.length} -> ${result.length} chars');
    return result;
  }

  String get dataUsed {
    if (!isConnected) return '0 MB';
    final total = _totalDownload + _totalUpload;
    if (total > 1024 * 1024) {
      return '${(total / (1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (total > 1024) {
      return '${(total / 1024).toStringAsFixed(1)} MB';
    }
    return '${total.toStringAsFixed(0)} KB';
  }

  void setProtocol(String value) {
    _protocol = value;
    _storageService.setProtocol(value);
    notifyListeners();
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

  void _recordConnectionStart() {
    final server = _selectedServer;
    if (server == null) return;
    _pendingConnectionStart = DateTime.now();
  }

  DateTime? _pendingConnectionStart;

  void _recordConnectionEnd() {
    final server = _selectedServer;
    final start = _pendingConnectionStart ?? _connectedAt;
    if (server == null) return;

    final duration = start != null ? DateTime.now().difference(start).inSeconds : 0;
    final dataMB = (_totalDownload + _totalUpload) / 1024;
    final record = ConnectionRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serverName: server.name,
      country: server.country,
      countryCode: server.countryCode,
      flag: server.flag,
      protocol: _protocol,
      connectedAt: start ?? DateTime.now(),
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

  void setSubscriber(bool value) {
    _isSubscriber = value;
    _tierBlockReason = null;
    notifyListeners();
  }

  Future<bool> showPaywall() async {
    final ctx = _navigatorContext;
    if (ctx == null) return false;
    final result = await Navigator.of(ctx).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PaywallScreen(),
      ),
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
    _vpnStateSubscription?.cancel();
    _vpnService.dispose();
    super.dispose();
  }
}
