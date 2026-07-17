enum VPNStage {
  disconnected,
  waitingConnection,
  authenticating,
  connecting,
  connected,
  reconnect,
  disconnecting,
  denied,
}

abstract class VPNService {
  Future<void> initialize();
  Future<void> connect({required String config, required String serverAddress});
  Future<void> disconnect();
  Stream<VPNStage> get stageStream;
  Stream<Map<String, dynamic>> get trafficStream;
  VPNStage get currentStage;
  Future<bool> requestPermission();
  void dispose();
}

class VPNServiceException implements Exception {
  final String message;
  final dynamic originalError;
  VPNServiceException(this.message, [this.originalError]);
  @override
  String toString() => 'VPNServiceException: $message';
}
