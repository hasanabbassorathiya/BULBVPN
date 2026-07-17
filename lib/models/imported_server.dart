import '../services/v2ray_config_parser.dart';

class ImportedServer {
  final String id;
  final String name;
  final String address;
  final int port;
  final V2RayProtocol protocol;
  final String configJson;
  final DateTime importedAt;
  final bool isFavorite;
  final int ping;

  ImportedServer({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.protocol,
    required this.configJson,
    required this.importedAt,
    this.isFavorite = false,
    this.ping = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'port': port,
      'protocol': protocol.name,
      'configJson': configJson,
      'importedAt': importedAt.toIso8601String(),
      'isFavorite': isFavorite,
      'ping': ping,
    };
  }

  factory ImportedServer.fromJson(Map<String, dynamic> json) {
    return ImportedServer(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      port: json['port'] as int,
      protocol: V2RayProtocol.values.firstWhere(
        (e) => e.name == json['protocol'],
        orElse: () => V2RayProtocol.vless,
      ),
      configJson: json['configJson'] as String,
      importedAt: DateTime.parse(json['importedAt'] as String),
      isFavorite: json['isFavorite'] as bool? ?? false,
      ping: json['ping'] as int? ?? 0,
    );
  }

  ImportedServer copyWith({
    String? id,
    String? name,
    String? address,
    int? port,
    V2RayProtocol? protocol,
    String? configJson,
    DateTime? importedAt,
    bool? isFavorite,
    int? ping,
  }) {
    return ImportedServer(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
      configJson: configJson ?? this.configJson,
      importedAt: importedAt ?? this.importedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      ping: ping ?? this.ping,
    );
  }
}
