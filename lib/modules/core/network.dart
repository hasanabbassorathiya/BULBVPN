import 'package:connectivity_plus/connectivity_plus.dart';

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

  static Future<bool> checkConnectivity() async {
    final List<ConnectivityResult> connectivityResult =
        await (Connectivity().checkConnectivity());

    return connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi);
  }
}