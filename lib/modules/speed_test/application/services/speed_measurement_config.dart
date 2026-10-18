class SpeedMeasurementConfig {
  /// One latency sample, one download, one upload. A second pass only
  /// starts when the user taps the test again.
  static const List<Map<String, dynamic>> measurements = [
    {'type': 'latency', 'numPackets': 6},
    {'type': 'download', 'bytes': 2000000, 'count': 1, 'bypassMinDuration': true},
    {'type': 'upload', 'bytes': 1000000, 'count': 1},
  ];

  static const int totalMeasurements = 3;
  static const int maxConsecutiveFailures = 3;
  static const int chunkSize = 65536;
  static const Duration measurementDelay = Duration(milliseconds: 50);
  static const Duration latencyDelay = Duration(milliseconds: 10);
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration sendTimeout = Duration(seconds: 60);

  static String formatBytes(int bytes) {
    if (bytes < 1000) return '${bytes}B';
    if (bytes < 1000000) return '${(bytes / 1000).toStringAsFixed(0)}KB';
    if (bytes < 1000000000) return '${(bytes / 1000000).toStringAsFixed(0)}MB';
    return '${(bytes / 1000000000).toStringAsFixed(0)}GB';
  }

  static double roundSpeed(double speed) {
    if (speed < 10) {
      return (speed / 0.1).round() * 0.1;
    } else if (speed < 50) {
      return (speed / 0.25).round() * 0.25;
    } else {
      return (speed / 0.5).round() * 0.5;
    }
  }
}
