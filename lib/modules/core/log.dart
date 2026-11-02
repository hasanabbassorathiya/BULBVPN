import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class Log {
  Log._internal();
  static final Log _instance = Log._internal();
  factory Log() => _instance;

  static const int _maxChars = 200000;
  static const int _maxFileBytes = 512 * 1024;
  static const int _previousSessionLines = 200;

  final List<String> _lines = <String>[];
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  File? _file;
  final List<String> _pending = <String>[];
  bool _persistenceStarted = false;
  bool _writing = false;

  List<String> get lines => List<String>.unmodifiable(_lines);

  String getLogs() => _lines.join('\n');

  List<String> recent([int count = 200]) {
    if (_lines.length <= count) return List<String>.from(_lines.reversed);
    return _lines.sublist(_lines.length - count).reversed.toList();
  }

  /// Opens the durable log and loads the previous session into the in-memory
  /// buffer.
  ///
  /// Failure evidence on a phone is usually produced right before the app is
  /// killed by the OS or the user. Keeping only an in-memory ring buffer means
  /// the log that explains a dead tunnel is gone exactly when it is needed.
  /// The file is capped and rotated once; it lives in the app support
  /// directory, which no other app can read.
  Future<void> initializePersistence() async {
    if (_persistenceStarted) return;
    _persistenceStarted = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/bulb.log');
      final restored = await _seedPrevious(file);
      if (await file.exists() && await file.length() > _maxFileBytes) {
        await _rotate(file);
      }
      await file.create(recursive: true);
      _file = file;
      if (restored > 0) {
        addLog('[Log] restored $restored lines from the previous session');
      }
    } catch (e) {
      _file = null;
      debugPrint('[Log] persistence unavailable: $e');
    }
    if (_pending.isNotEmpty) unawaited(_flush());
  }

  Future<int> _seedPrevious(File file) async {
    if (!await file.exists()) return 0;
    try {
      final raw = await file.readAsString();
      if (raw.isEmpty) return 0;
      final all = const LineSplitter().convert(raw);
      final tail = all.length <= _previousSessionLines
          ? all
          : all.sublist(all.length - _previousSessionLines);
      if (tail.isEmpty) return 0;
      _lines.add(
        '[${DateTime.now().toIso8601String()}] --- previous session ---',
      );
      _lines.addAll(tail);
      version.value++;
      return tail.length;
    } catch (_) {
      return 0;
    }
  }

  void clearLogs() {
    _lines.clear();
    version.value++;
    _pending.clear();
    final file = _file;
    if (file != null) {
      unawaited(() async {
        try {
          await file.writeAsString('', flush: true);
        } catch (_) {}
      }());
    }
    try {
      FirebaseCrashlytics.instance.log('[Log] cleared');
    } catch (_) {}
  }

  String addLog(String log) {
    final safe = _sanitizeForStorage(log);
    final line = '[${DateTime.now().toIso8601String()}] $safe';
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
    debugPrint(safe);
    try {
      FirebaseCrashlytics.instance.log(line);
    } catch (_) {}
    _appendFile(line);
    return line;
  }

  /// Strip fetch URLs and catalog hostnames from anything that could surface
  /// in a debug sheet or Crashlytics breadcrumb.
  static String _sanitizeForStorage(String log) {
    return log
        .replaceAll(RegExp(r'https?://\S+'), '[url]')
        .replaceAll(RegExp(r'[\w.-]*opengw\.net'), 'relay')
        .replaceAll(RegExp(r'vpngate\.net', caseSensitive: false), 'catalog')
        .replaceAll(RegExp(r'vpngate', caseSensitive: false), 'catalog')
        .replaceAll(RegExp(r'public-vpn-\d+'), 'relay');
  }

  void _appendFile(String line) {
    if (!kReleaseMode) {
      try {
        // HOME is empty inside iOS/macOS sandboxes; tmp always works.
        final file = File('${Directory.systemTemp.path}/bulb.log');
        file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      } catch (_) {}
    }
    if (!_persistenceStarted) {
      // Keep early boot lines in memory; initializePersistence flushes them.
      _pending.add(line);
      return;
    }
    _pending.add(line);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_writing) return;
    _writing = true;
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      _writing = false;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final file = _file;
    if (file == null) {
      _pending.clear();
      return;
    }
    if (_writing) return;
    _writing = true;
    final text = '${_pending.join('\n')}\n';
    _pending.clear();
    try {
      await file.writeAsString(text, mode: FileMode.append, flush: true);
      if (await file.length() > _maxFileBytes) await _rotate(file);
    } catch (_) {
      // A full disk or a revoked sandbox must not break logging itself.
    } finally {
      _writing = false;
      if (_pending.isNotEmpty) _scheduleFlush();
    }
  }

  Future<void> _rotate(File file) async {
    try {
      final previous = File('${file.parent.path}/bulb.prev.log');
      if (await previous.exists()) await previous.delete();
      await file.rename(previous.path);
      await file.create(recursive: true);
    } catch (_) {}
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
