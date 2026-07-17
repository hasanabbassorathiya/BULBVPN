class Subscription {
  final String id;
  final String name;
  final String url;
  final DateTime createdAt;
  final DateTime? lastUpdated;
  final int serverCount;

  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    required this.createdAt,
    this.lastUpdated,
    this.serverCount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated?.toIso8601String(),
      'serverCount': serverCount,
    };
  }

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'] as String)
          : null,
      serverCount: json['serverCount'] as int? ?? 0,
    );
  }

  Subscription copyWith({
    String? name,
    String? url,
    int? serverCount,
    DateTime? lastUpdated,
  }) {
    return Subscription(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      createdAt: createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      serverCount: serverCount ?? this.serverCount,
    );
  }
}
