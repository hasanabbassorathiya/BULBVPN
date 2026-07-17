import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as dev;

class TierService {
  static const int _freeServerLimit = 3;
  static const int _freeDataLimitMB = 500;
  static const Duration _freeSessionLimit = Duration(hours: 1);

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool canConnectToServer(String serverId, bool isPremiumServer, bool isSubscriber) {
    if (isSubscriber) return true;

    if (isPremiumServer) return false;

    final connectedServers = _prefs?.getStringList('connected_servers') ?? [];
    if (connectedServers.length >= _freeServerLimit) {
      if (!connectedServers.contains(serverId)) return false;
    }

    return true;
  }

  bool hasDataRemaining(bool isSubscriber) {
    if (isSubscriber) return true;

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastReset = _prefs?.getString('data_reset_date') ?? '';

    if (lastReset != today) {
      _prefs?.setString('data_reset_date', today);
      _prefs?.setInt('daily_data_used_mb', 0);
      return true;
    }

    final used = _prefs?.getInt('daily_data_used_mb') ?? 0;
    return used < _freeDataLimitMB;
  }

  bool hasSessionRemaining(bool isSubscriber) {
    if (isSubscriber) return true;

    final sessionStart = _prefs?.getString('session_start');
    if (sessionStart == null) return true;

    final start = DateTime.parse(sessionStart);
    final elapsed = DateTime.now().difference(start);
    return elapsed < _freeSessionLimit;
  }

  Future<void> recordDataUsage(double mb) async {
    final current = _prefs?.getInt('daily_data_used_mb') ?? 0;
    await _prefs?.setInt('daily_data_used_mb', current + mb.toInt());
  }

  Future<void> recordSessionStart() async {
    dev.log('TierService: recording session start', name: 'BULB_VPN');
    await _prefs?.setString('session_start', DateTime.now().toIso8601String());
  }

  Future<void> recordSessionEnd() async {
    dev.log('TierService: recording session end', name: 'BULB_VPN');
    await _prefs?.remove('session_start');
  }

  Future<void> addConnectedServer(String serverId) async {
    final servers = _prefs?.getStringList('connected_servers') ?? [];
    if (!servers.contains(serverId)) {
      servers.add(serverId);
      await _prefs?.setStringList('connected_servers', servers);
    }
  }

  int getConnectedServerCount(bool isSubscriber) {
    if (isSubscriber) return 0;
    return (_prefs?.getStringList('connected_servers') ?? []).length;
  }

  int get dailyDataUsedMB => _prefs?.getInt('daily_data_used_mb') ?? 0;

  Map<String, dynamic> getLimits(bool isSubscriber) {
    if (isSubscriber) {
      return {
        'servers': 'Unlimited',
        'data': 'Unlimited',
        'session': 'Unlimited',
      };
    }
    return {
      'servers': '$_freeServerLimit servers',
      'data': '$_freeDataLimitMB MB/day',
      'session': '1 hour/session',
    };
  }
}
