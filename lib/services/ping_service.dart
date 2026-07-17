import 'dart:io';

class PingService {
  static Future<int> ping(String host, int port, {int timeoutMs = 3000}) async {
    final sw = Stopwatch()..start();
    try {
      final socket =
          await Socket.connect(host, port, timeout: Duration(milliseconds: timeoutMs));
      socket.destroy();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      sw.stop();
      return -1;
    }
  }
}
