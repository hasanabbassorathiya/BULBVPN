import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/connection_history.dart';

class HistoryService {
  static const String _key = 'connection_history';
  static const int _maxRecords = 50;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> addRecord(ConnectionRecord record) async {
    final p = await _getPrefs();
    final records = getRecords();
    records.insert(0, record);
    if (records.length > _maxRecords) {
      records.removeRange(_maxRecords, records.length);
    }
    final encoded = records.map((r) => jsonEncode(r.toJson())).toList();
    await p.setStringList(_key, encoded);
  }

  List<ConnectionRecord> getRecords() {
    final encoded = _prefs?.getStringList(_key) ?? [];
    return encoded.map((e) {
      try {
        return ConnectionRecord.fromJson(jsonDecode(e));
      } catch (_) {
        return null;
      }
    }).whereType<ConnectionRecord>().toList();
  }

  Future<void> clearRecords() async {
    final p = await _getPrefs();
    await p.remove(_key);
  }

  int get totalConnections => getRecords().length;

  int get totalMinutesConnected {
    final totalSeconds = getRecords().fold<int>(0, (sum, r) => sum + r.durationSeconds);
    return totalSeconds ~/ 60;
  }

  double get totalDataUsedMB {
    return getRecords().fold<double>(0, (sum, r) => sum + r.dataUsedMB);
  }

  String get mostUsedServer {
    final records = getRecords();
    if (records.isEmpty) return 'None';
    final counts = <String, int>{};
    for (final r in records) {
      counts[r.serverName] = (counts[r.serverName] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  Map<String, int> get connectionsByCountry {
    final records = getRecords();
    final counts = <String, int>{};
    for (final r in records) {
      counts[r.country] = (counts[r.country] ?? 0) + 1;
    }
    return counts;
  }
}
