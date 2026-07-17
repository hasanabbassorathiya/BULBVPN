class ServerConfig {
  final String id;
  final String name;
  final String country;
  final String countryCode;
  final String flag;
  final String endpoint;
  final int port;
  final String publicKey;
  final String? presharedKey;
  final String internalAddress;
  final String dns;
  final List<String> allowedIps;
  final int persistentKeepalive;
  final bool isPremium;

  const ServerConfig({
    required this.id,
    required this.name,
    required this.country,
    required this.countryCode,
    required this.flag,
    required this.endpoint,
    this.port = 51820,
    required this.publicKey,
    this.presharedKey,
    required this.internalAddress,
    this.dns = '1.1.1.1, 8.8.8.8',
    this.allowedIps = const ['0.0.0.0/0', '::/0'],
    this.persistentKeepalive = 25,
    this.isPremium = false,
  });

  String buildConfig(String privateKey, {String? clientAddress}) {
    final address = clientAddress ?? '$internalAddress/32';
    final config = StringBuffer();
    config.writeln('[Interface]');
    config.writeln('PrivateKey = $privateKey');
    config.writeln('Address = $address');
    config.writeln('DNS = $dns');
    config.writeln('');
    config.writeln('[Peer]');
    config.writeln('PublicKey = $publicKey');
    if (presharedKey != null) {
      config.writeln('PresharedKey = $presharedKey');
    }
    config.writeln('Endpoint = $endpoint:$port');
    config.writeln('AllowedIPs = ${allowedIps.join(', ')}');
    config.writeln('PersistentKeepalive = $persistentKeepalive');
    return config.toString();
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      country: json['country'] as String,
      countryCode: json['countryCode'] as String,
      flag: json['flag'] as String,
      endpoint: json['endpoint'] as String,
      port: json['port'] as int? ?? 51820,
      publicKey: json['publicKey'] as String,
      presharedKey: json['presharedKey'] as String?,
      internalAddress: json['internalAddress'] as String,
      dns: json['dns'] as String? ?? '1.1.1.1, 8.8.8.8',
      allowedIps: (json['allowedIps'] as List<dynamic>?)?.cast<String>() ?? ['0.0.0.0/0', '::/0'],
      persistentKeepalive: json['persistentKeepalive'] as int? ?? 25,
      isPremium: json['isPremium'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'country': country,
      'countryCode': countryCode,
      'flag': flag,
      'endpoint': endpoint,
      'port': port,
      'publicKey': publicKey,
      'presharedKey': presharedKey,
      'internalAddress': internalAddress,
      'dns': dns,
      'allowedIps': allowedIps,
      'persistentKeepalive': persistentKeepalive,
      'isPremium': isPremium,
    };
  }
}
