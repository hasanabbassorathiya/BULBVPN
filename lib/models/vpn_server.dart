class VpnServer {
  final String id;
  final String name;
  final String country;
  final String countryCode;
  final String flag;
  final int ping;
  final double load;
  final bool isPremium;
  final String? openVpnConfig;
  final String? wireGuardConfig;

  const VpnServer({
    required this.id,
    required this.name,
    required this.country,
    required this.countryCode,
    required this.flag,
    this.ping = 0,
    this.load = 0,
    this.isPremium = false,
    this.openVpnConfig,
    this.wireGuardConfig,
  });

  factory VpnServer.fromJson(Map<String, dynamic> json) {
    return VpnServer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      country: json['country'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '',
      flag: json['flag'] as String? ?? '',
      ping: json['ping'] as int? ?? 0,
      load: (json['load'] as num?)?.toDouble() ?? 0,
      isPremium: json['isPremium'] as bool? ?? false,
      openVpnConfig: json['openVpnConfig'] as String?,
      wireGuardConfig: json['wireGuardConfig'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'country': country,
      'countryCode': countryCode,
      'flag': flag,
      'ping': ping,
      'load': load,
      'isPremium': isPremium,
      'openVpnConfig': openVpnConfig,
      'wireGuardConfig': wireGuardConfig,
    };
  }

  VpnServer copyWith({
    String? id,
    String? name,
    String? country,
    String? countryCode,
    String? flag,
    int? ping,
    double? load,
    bool? isPremium,
    String? openVpnConfig,
    String? wireGuardConfig,
  }) {
    return VpnServer(
      id: id ?? this.id,
      name: name ?? this.name,
      country: country ?? this.country,
      countryCode: countryCode ?? this.countryCode,
      flag: flag ?? this.flag,
      ping: ping ?? this.ping,
      load: load ?? this.load,
      isPremium: isPremium ?? this.isPremium,
      openVpnConfig: openVpnConfig ?? this.openVpnConfig,
      wireGuardConfig: wireGuardConfig ?? this.wireGuardConfig,
    );
  }
}
