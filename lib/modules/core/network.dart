import 'dart:io';

class NetworkStatus {
  NetworkStatus._internal();
  static final NetworkStatus _instance = NetworkStatus._internal();
  factory NetworkStatus() {
    return _instance;
  }

  Future<String> getPing() async {
    // Ping is now handled by the connection state notifier polling
    // Return a default value since openvpn_flutter doesn't expose ping directly
    return '0';
  }

  Future<String> getFlag() async {
    // Flag detection is not available in openvpn_flutter
    // Return default
    return 'xx';
  }

  /// Lightweight reachability check (no connectivity_plus — it SIGSEGVs on
  /// iOS 27 beta during native plugin registration).
  static Future<bool> checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return true; // optimistic — VPN connect will fail cleanly if offline
    }
  }
}
