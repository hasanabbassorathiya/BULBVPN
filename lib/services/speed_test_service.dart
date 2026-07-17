import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class SpeedTestResult {
  final double downloadMbps;
  final double uploadMbps;
  final int pingMs;
  final int jitterMs;
  final String serverName;
  final DateTime testedAt;

  const SpeedTestResult({
    required this.downloadMbps,
    required this.uploadMbps,
    required this.pingMs,
    required this.jitterMs,
    required this.serverName,
    required this.testedAt,
  });

  Map<String, dynamic> toJson() => {
        'downloadMbps': downloadMbps,
        'uploadMbps': uploadMbps,
        'pingMs': pingMs,
        'jitterMs': jitterMs,
        'serverName': serverName,
        'testedAt': testedAt.toIso8601String(),
      };

  factory SpeedTestResult.fromJson(Map<String, dynamic> json) => SpeedTestResult(
        downloadMbps: (json['downloadMbps'] as num).toDouble(),
        uploadMbps: (json['uploadMbps'] as num).toDouble(),
        pingMs: json['pingMs'] as int,
        jitterMs: json['jitterMs'] as int,
        serverName: json['serverName'] as String,
        testedAt: DateTime.parse(json['testedAt'] as String),
      );
}

class SpeedTestService {
  static const int _maxHistory = 5;

  static const List<String> _testUrls = [
    'http://proof.ovh.net/files/10Mb.dat',
    'http://speedtest.tele2.net/10MB.zip',
    'http://speedtest.tele2.net/1MB.zip',
  ];

  static const List<String> _pingUrls = [
    'http://google.com',
    'http://cloudflare.com',
    'http://1.1.1.1',
  ];

  Future<SpeedTestResult> runTest({
    void Function(String phase, double progress)? onProgress,
  }) async {
    onProgress?.call('ping', 0.0);
    final ping = await _measurePing();
    final jitter = await _measureJitter();
    onProgress?.call('ping', 1.0);

    onProgress?.call('download', 0.0);
    final downloadSpeed = await _measureDownload(
      onProgress: (p) => onProgress?.call('download', p),
    );
    onProgress?.call('download', 1.0);

    onProgress?.call('upload', 0.0);
    final uploadSpeed = await _measureUpload(
      onProgress: (p) => onProgress?.call('upload', p),
    );
    onProgress?.call('upload', 1.0);

    final result = SpeedTestResult(
      downloadMbps: downloadSpeed,
      uploadMbps: uploadSpeed,
      pingMs: ping,
      jitterMs: jitter,
      serverName: 'BULB VPN Server',
      testedAt: DateTime.now(),
    );

    await _saveToHistory(result);
    return result;
  }

  Future<int> _measurePing() async {
    int totalPing = 0;
    int count = 0;

    for (final url in _pingUrls) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5);
        final request = await client.getUrl(Uri.parse(url));
        final stopwatch = Stopwatch()..start();
        final response = await request.close();
        stopwatch.stop();
        await response.drain();
        client.close();

        totalPing += stopwatch.elapsedMilliseconds;
        count++;
      } catch (_) {
        // skip failed hosts
      }
    }

    return count > 0 ? (totalPing / count).round() : 0;
  }

  Future<int> _measureJitter() async {
    final pings = <int>[];

    for (final url in _pingUrls) {
      for (int i = 0; i < 3; i++) {
        try {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 5);
          final request = await client.getUrl(Uri.parse(url));
          final stopwatch = Stopwatch()..start();
          final response = await request.close();
          stopwatch.stop();
          await response.drain();
          client.close();
          pings.add(stopwatch.elapsedMilliseconds);
        } catch (_) {}
      }
    }

    if (pings.length < 2) return 0;

    double sumDiff = 0;
    for (int i = 1; i < pings.length; i++) {
      sumDiff += (pings[i] - pings[i - 1]).abs().toDouble();
    }
    return (sumDiff / (pings.length - 1)).round();
  }

  Future<double> _measureDownload({
    void Function(double progress)? onProgress,
  }) async {
    for (final url in _testUrls) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        final request = await client.getUrl(Uri.parse(url));
        final stopwatch = Stopwatch()..start();
        final response = await request.close();

        int totalBytes = 0;
        await for (final chunk in response) {
          totalBytes += chunk.length;
          final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
          if (elapsed > 0) {
            final speedMbps = (totalBytes * 8) / (elapsed * 1000000);
            onProgress?.call(speedMbps.clamp(0.0, 1000.0) / 1000.0);
          }
        }
        stopwatch.stop();
        client.close();

        if (totalBytes == 0) continue;

        final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
        final speedMbps = (totalBytes * 8) / (elapsed * 1000000);
        return speedMbps;
      } catch (_) {
        continue;
      }
    }
    return 0.0;
  }

  Future<double> _measureUpload({
    void Function(double progress)? onProgress,
  }) async {
    try {
      final data = List<int>.generate(5 * 1024 * 1024, (i) => i % 256);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final request = await client.putUrl(Uri.parse('http://speedtest.tele2.net/upload.php'));
      request.contentLength = data.length;

      final stopwatch = Stopwatch()..start();
      final sink = request;
      for (int i = 0; i < data.length; i += 65536) {
        final end = min(i + 65536, data.length);
        sink.add(data.sublist(i, end));
        final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
        if (elapsed > 0) {
          final speedMbps = (end * 8) / (elapsed * 1000000);
          onProgress?.call(speedMbps.clamp(0.0, 1000.0) / 1000.0);
        }
      }
      final response = await sink.close();
      await response.drain();
      stopwatch.stop();
      client.close();

      final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
      if (elapsed > 0) {
        return (data.length * 8) / (elapsed * 1000000);
      }
    } catch (_) {}
    return 0.0;
  }

  Future<void> _saveToHistory(SpeedTestResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    history.insert(0, result);
    if (history.length > _maxHistory) {
      history.removeRange(_maxHistory, history.length);
    }
    // Clear old entries
    for (int i = 0; i < _maxHistory; i++) {
      await prefs.remove('speed_test_${i}_download');
      await prefs.remove('speed_test_${i}_upload');
      await prefs.remove('speed_test_${i}_ping');
      await prefs.remove('speed_test_${i}_jitter');
      await prefs.remove('speed_test_${i}_server');
      await prefs.remove('speed_test_${i}_time');
    }
    // Write all entries
    for (int i = 0; i < history.length; i++) {
      final r = history[i];
      await prefs.setDouble('speed_test_${i}_download', r.downloadMbps);
      await prefs.setDouble('speed_test_${i}_upload', r.uploadMbps);
      await prefs.setInt('speed_test_${i}_ping', r.pingMs);
      await prefs.setInt('speed_test_${i}_jitter', r.jitterMs);
      await prefs.setString('speed_test_${i}_server', r.serverName);
      await prefs.setString('speed_test_${i}_time', r.testedAt.toIso8601String());
    }
  }

  Future<List<SpeedTestResult>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final results = <SpeedTestResult>[];
    for (int i = 0; i < _maxHistory; i++) {
      final downloadMbps = prefs.getDouble('speed_test_${i}_download');
      final uploadMbps = prefs.getDouble('speed_test_${i}_upload');
      final pingMs = prefs.getInt('speed_test_${i}_ping');
      final jitterMs = prefs.getInt('speed_test_${i}_jitter');
      final serverName = prefs.getString('speed_test_${i}_server');
      final testedAtStr = prefs.getString('speed_test_${i}_time');
      if (downloadMbps != null && uploadMbps != null && pingMs != null && testedAtStr != null) {
        results.add(SpeedTestResult(
          downloadMbps: downloadMbps,
          uploadMbps: uploadMbps,
          pingMs: pingMs,
          jitterMs: jitterMs ?? 0,
          serverName: serverName ?? 'Unknown',
          testedAt: DateTime.parse(testedAtStr),
        ));
      }
    }
    return results;
  }
}
