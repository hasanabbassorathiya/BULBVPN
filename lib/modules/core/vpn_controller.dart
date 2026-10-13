import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bulbvpn/core/data/local/secure_storage/secure_storage.dart';
import 'package:bulbvpn/core/data/local/secure_storage/secure_storage_const.dart';
import 'package:bulbvpn/core/data/local/vpn_data/vpn_data.dart';
import 'package:bulbvpn/modules/core/vpn_service.dart';
import 'package:bulbvpn/modules/settings/providers/settings_provider.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:bulbvpn/shared/providers/flow_line_provider.dart';
import 'package:bulbvpn/shared/providers/group_provider.dart';
import 'package:bulbvpn/shared/providers/logs_provider.dart';
import 'package:bulbvpn/shared/services/firebase_analytics_service.dart';
import 'package:bulbvpn/shared/services/vibration_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bulbvpn/modules/core/network.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/main/presentation/screens/main_screen.dart';

class VpnController {
  VpnController._internal();
  static final VpnController _instance = VpnController._internal();
  factory VpnController() => _instance;

  final Log _log = Log();
  final VpnService _vpnService = VpnService();
  final VibrationService _vibrationService = VibrationService();
  final FirebaseAnalyticsService _analyticsService = FirebaseAnalyticsService();

  ProviderContainer? _container;
  bool _initialized = false;

  // Optional server picked from the console server sheet. When set, it takes
  // priority over the test config / flowLine. VPN Gate configs include client
  // certs, so certIsRequired is always true for these.
  String? _serverConfig;
  String _serverLabel = '';

  String get selectedServerLabel => _serverLabel;

  void selectServerConfig(String config, String label) {
    _serverConfig = config;
    _serverLabel = label;
    _log.addLog(
        '[VpnController] Selected server: $label (${config.length} chars)');
  }

  void clearServerConfig() {
    _serverConfig = null;
    _serverLabel = '';
    _log.addLog('[VpnController] Server selection cleared (auto)');
  }

  // Test mode configuration
  static const bool _useTestConfig = true;

  VpnService get vpnService => _vpnService;

  Future<void> initialize(ProviderContainer container) async {
    if (_initialized) return;
    _container = container;
    _vibrationService.init();
    
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final offsetInHours = offset.inMinutes / 60.0;
    _log.addLog('[VpnController] Timezone offset: $offsetInHours hours');
    
    try {
      await _vpnService.initialize();
      _initialized = true;
      _log.addLog('[VpnController] VpnController initialized successfully');
      if (_useTestConfig) {
        _log.addLog('[VpnController] TEST MODE ENABLED - Will fetch fresh VPN Gate config');
      }
    } catch (e, stackTrace) {
      _log.addLog('[VpnController] ERROR initializing: $e');
      _log.addLog('[VpnController] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Fetch a fresh OpenVPN config from VPN Gate API
  Future<String?> _fetchFreshVpnGateConfig() async {
    const apiUrl = 'https://raw.githubusercontent.com/alihusains/apigate/main/response.json';
    _log.addLog('[VpnController] Fetching fresh VPN Gate config from $apiUrl');
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          _log.addLog('[VpnController] ERROR: Failed to fetch VPN Gate list: ${response.statusCode} (attempt $attempt)');
          continue;
        }
        final List<dynamic> servers = json.decode(response.body);
        _log.addLog('[VpnController] Parsed ${servers.length} servers from VPN Gate');

        // Find first server with valid OpenVPN config
        for (final server in servers) {
          final configB64 = server['OpenVPN_ConfigData_Base64'] as String?;
          if (configB64 != null && configB64.isNotEmpty) {
            // Decode base64 - keep all cert/key blocks (VPN Gate includes real client certs)
            final config = utf8.decode(base64.decode(configB64));
            _log.addLog('[VpnController] Selected server: ${server['IP'] ?? 'unknown'} (${server['CountryShort'] ?? '??'})');
            return config;
          }
        }
        _log.addLog('[VpnController] ERROR: No valid OpenVPN config found in server list');
        return null;
      } catch (e, stackTrace) {
        _log.addLog('[VpnController] ERROR fetching VPN Gate config (attempt $attempt): $e');
        _log.addLog('[VpnController] Stack trace: $stackTrace');
      }
    }
    return null;
  }

  Future<void> handleConnectionButton(WidgetRef ref) async {
    final connectionState = ref.read(connectionStateProvider);
    _log.addLog('[VpnController] handleConnectionButton called, current status: ${connectionState.status}');
    
    switch (connectionState.status) {
      case ConnectionStatus.connected:
        await _disconnect(ref);
        return;
      case ConnectionStatus.connecting:
      case ConnectionStatus.disconnecting:
        await _stopVpn(ref);
        return;
      case ConnectionStatus.disconnected:
      case ConnectionStatus.error:
      case ConnectionStatus.noInternet:
        await _connect(ref);
        return;
      default:
        _log.addLog('[VpnController] Unknown status: ${connectionState.status}');
        break;
    }
  }

  Future<void> _connect(WidgetRef ref) async {
    final connectionNotifier = ref.read(connectionStateProvider.notifier);
    final loggerNotifier = ref.read(loggerStateProvider.notifier);
    final settings = ref.read(settingsProvider.notifier);

    _log.addLog('[VpnController] Starting connection process...');
    
    connectionNotifier.setLoading();
    loggerNotifier.setLoading();
    _vibrationService.vibrateHeartbeat();

    final networkIsConnected = await NetworkStatus.checkConnectivity();
    if (!networkIsConnected) {
      _log.addLog('[VpnController] No internet connection');
      connectionNotifier.setNoInternet();
      _vibrationService.vibrateError();
      return;
    }

    String ovpnConfig;
    bool certIsRequired;

    if (_serverConfig != null) {
      _log.addLog('[VpnController] Using selected server: $_serverLabel');
      ovpnConfig = _serverConfig!;
      certIsRequired = true; // VPN Gate configs carry <cert>/<key>/<ca>
    } else if (_useTestConfig) {
      _log.addLog('[VpnController] TEST MODE: fetching fresh VPN Gate config');
      final fresh = await _fetchFreshVpnGateConfig();
      if (fresh != null) {
        ovpnConfig = fresh;
        certIsRequired = true; // VPN Gate configs include client certs
      } else {
        // Fresh fetch failed - fall back to the server list loaded at startup.
        _log.addLog('[VpnController] Fresh fetch failed, trying cached server list');
        List<VpnServer> cachedServers = const [];
        try {
          cachedServers = await ref.read(serversProvider.future);
        } catch (e) {
          _log.addLog('[VpnController] Cached server list unavailable: $e');
        }
        VpnServer? cached;
        for (final s in cachedServers) {
          if (s.openVpnConfigBase64.isNotEmpty) {
            cached = s;
            break;
          }
        }
        if (cached == null) {
          _log.addLog('[VpnController] ERROR: No server config available');
          connectionNotifier.setError();
          _vibrationService.vibrateError();
          return;
        }
        try {
          ovpnConfig = utf8.decode(base64.decode(cached.openVpnConfigBase64));
          certIsRequired = true;
          _log.addLog('[VpnController] Using cached server: ${cached.ip} (${cached.countryShort})');
        } catch (e) {
          _log.addLog('[VpnController] ERROR decoding cached config: $e');
          connectionNotifier.setError();
          _vibrationService.vibrateError();
          return;
        }
      }
    } else {
      final secureStorage = _container?.read(secureStorageProvider);
      final flowLineStorage = await secureStorage?.read(flowLineKey) ?? '';
      _log.addLog('[VpnController] FlowLine from storage: ${flowLineStorage.isNotEmpty ? 'present (${flowLineStorage.length} chars)' : 'empty'}');

      final pattern = settings.getPattern();
      _log.addLog('[VpnController] Pattern: $pattern');

      // Extract the actual .ovpn config from flowLine based on pattern
      final extractedConfig = _extractOvpnConfig(flowLineStorage, pattern);
      if (extractedConfig == null || extractedConfig.isEmpty) {
        _log.addLog('[VpnController] ERROR: Could not extract OpenVPN config from flowLine');
        connectionNotifier.setError();
        _vibrationService.vibrateError();
        return;
      }
      ovpnConfig = extractedConfig;
      certIsRequired = true;
      _log.addLog('[VpnController] Extracted OpenVPN config (${ovpnConfig.length} chars)');
    }

    _analyticsService.logVpnConnectAttempt(
        _serverConfig != null ? 'server_${_serverLabel.replaceAll(' ', '_')}' : 'vpn_gate_test');

    try {
      _log.addLog('[VpnController] Calling VpnService.connect()...');

      await _vpnService.connect(
        config: ovpnConfig,
        name: 'BULBVPN',
        username: 'vpn',
        password: 'vpn',
        certIsRequired: certIsRequired,
      );
      
      _log.addLog('[VpnController] VpnService.connect() completed (certIsRequired: $certIsRequired)');
    } catch (e, stackTrace) {
      _log.addLog('[VpnController] ERROR during connect: $e');
      _log.addLog('[VpnController] Stack trace: $stackTrace');
      connectionNotifier.setError();
      _vibrationService.vibrateError();
    }
  }

  String? _extractOvpnConfig(String flowLineStorage, String pattern) {
    if (flowLineStorage.isEmpty) {
      _log.addLog('[VpnController] FlowLine storage is empty');
      return null;
    }

    try {
      final decoded = jsonDecode(flowLineStorage);
      _log.addLog('[VpnController] FlowLine JSON keys: ${decoded.keys.toList()}');
      
      // The flowLine is a list of connection methods
      // Each method has a label, config, etc.
      final flowLineList = decoded['flowLine'] as List<dynamic>?;
      if (flowLineList == null || flowLineList.isEmpty) {
        _log.addLog('[VpnController] No flowLine array in decoded JSON');
        return null;
      }

      _log.addLog('[VpnController] FlowLine has ${flowLineList.length} methods');
      
      // If pattern is specified, find the matching method
      // Pattern is comma-separated labels like "method1,method2"
      final patternLabels = pattern.isEmpty ? [] : pattern.split(',');
      
      Map<String, dynamic>? selectedMethod;
      
      if (patternLabels.isNotEmpty) {
        // Find the first method that matches any label in pattern
        for (final label in patternLabels) {
          final method = flowLineList.firstWhere(
            (item) => item['label'] == label.trim(),
            orElse: () => null,
          );
          if (method != null) {
            selectedMethod = method;
            _log.addLog('[VpnController] Selected method by pattern: ${method['label']}');
            break;
          }
        }
      }
      
      // If no pattern match, use the first enabled method
      if (selectedMethod == null) {
        selectedMethod = flowLineList.firstWhere(
          (item) => item['enabled'] == true,
          orElse: () => flowLineList.firstOrNull,
        );
        if (selectedMethod != null) {
          _log.addLog('[VpnController] Using first enabled/available method: ${selectedMethod['label']}');
        }
      }

      if (selectedMethod == null) {
        _log.addLog('[VpnController] No suitable method found in flowLine');
        return null;
      }

      // Extract the OpenVPN config from the selected method
      final config = selectedMethod['config'] as String?;
      if (config == null || config.isEmpty) {
        _log.addLog('[VpnController] Selected method has no config');
        return null;
      }

      _log.addLog('[VpnController] Successfully extracted config for: ${selectedMethod['label']}');
      return config;
    } catch (e, stackTrace) {
      _log.addLog('[VpnController] ERROR extracting config: $e');
      _log.addLog('[VpnController] Stack trace: $stackTrace');
      return null;
    }
  }

  Future<void> _stopVpn(WidgetRef ref) async {
    final connectionNotifier = ref.read(connectionStateProvider.notifier);
    _log.addLog('[VpnController] Stopping VPN...');
    connectionNotifier.setDisconnecting();
    await _vpnService.disconnect();
    _clearData(ref);
    connectionNotifier.setDisconnected();
  }

  Future<void> _disconnect(WidgetRef ref) async {
    final connectionNotifier = ref.read(connectionStateProvider.notifier);
    final vpnData = await _container?.read(vpnDataProvider.future);
    _log.addLog('[VpnController] Disconnecting VPN...');
    connectionNotifier.setDisconnecting();
    await _vpnService.disconnect();
    _clearData(ref);
    vpnData?.disableVPN();
    connectionNotifier.setDisconnected();
    _analyticsService.logVpnDisconnected();
  }

  void _clearData(WidgetRef ref) {
    final groupNotifier = ref.read(groupStateProvider.notifier);
    groupNotifier.setGroupName('');
    ref.read(flowLineStepProvider.notifier).setTotalSteps(0);
    ref.read(flowLineStepProvider.notifier).setStep(0);
  }

  void dispose() {
    _log.addLog('[VpnController] Disposing...');
    _vpnService.dispose();
    _initialized = false;
  }
}