import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:package_info_plus/package_info_plus.dart';

class Log {
  Log._internal();
  static final Log _instance = Log._internal();
  factory Log() => _instance;

  static const int _maxChars = 200000;
  final List<String> _lines = <String>[];
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  List<String> get lines => List<String>.unmodifiable(_lines);

  String getLogs() => _lines.join('\n');

  List<String> recent([int count = 200]) {
    if (_lines.length <= count) return List<String>.from(_lines.reversed);
    return _lines.sublist(_lines.length - count).reversed.toList();
  }

  void clearLogs() {
    _lines.clear();
    version.value++;
    try { FirebaseCrashlytics.instance.log('[Log] cleared'); } catch (_) {}
  }

  String addLog(String log) {
    final line = '[${DateTime.now().toIso8601String()}] $log';
    _lines.add(line);
    if (_lines.length > 2000) {
      _lines.removeRange(0, _lines.length - 2000);
    }
    // Character budget: drop oldest lines once the buffer exceeds _maxChars.
    var total = 0;
    for (final l in _lines) {
      total += l.length + 1;
    }
    while (total > _maxChars && _lines.length > 1) {
      total -= _lines.first.length + 1;
      _lines.removeAt(0);
    }
    version.value++;
    debugPrint(log);
    try { FirebaseCrashlytics.instance.log(line); } catch (_) {}
    return line;
  }

  String addError(String log, [Object? error, StackTrace? stackTrace]) {
    final buffer = StringBuffer(log);
    if (error != null) buffer.write(' | error: $error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    return addLog(buffer.toString());
  }

  Future<void> logAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    addLog('[INFO] App Version: ${info.version}+${info.buildNumber}');
  }
}
