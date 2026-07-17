class ConnectionRecord {
  final String id;
  final String serverName;
  final String country;
  final String countryCode;
  final String flag;
  final String protocol;
  final DateTime connectedAt;
  final DateTime? disconnectedAt;
  final int durationSeconds;
  final double dataUsedMB;
  final bool wasSuccessful;

  const ConnectionRecord({
    required this.id,
    required this.serverName,
    required this.country,
    required this.countryCode,
    required this.flag,
    required this.protocol,
    required this.connectedAt,
    this.disconnectedAt,
    this.durationSeconds = 0,
    this.dataUsedMB = 0,
    this.wasSuccessful = true,
  });

  factory ConnectionRecord.fromJson(Map<String, dynamic> json) {
    return ConnectionRecord(
      id: json['id'] as String? ?? '',
      serverName: json['serverName'] as String? ?? '',
      country: json['country'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '',
      flag: json['flag'] as String? ?? '',
      protocol: json['protocol'] as String? ?? '',
      connectedAt: DateTime.tryParse(json['connectedAt'] as String? ?? '') ?? DateTime.now(),
      disconnectedAt: json['disconnectedAt'] != null
          ? DateTime.tryParse(json['disconnectedAt'] as String)
          : null,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      dataUsedMB: (json['dataUsedMB'] as num?)?.toDouble() ?? 0,
      wasSuccessful: json['wasSuccessful'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serverName': serverName,
      'country': country,
      'countryCode': countryCode,
      'flag': flag,
      'protocol': protocol,
      'connectedAt': connectedAt.toIso8601String(),
      'disconnectedAt': disconnectedAt?.toIso8601String(),
      'durationSeconds': durationSeconds,
      'dataUsedMB': dataUsedMB,
      'wasSuccessful': wasSuccessful,
    };
  }

  String get formattedDuration {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(connectedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 2) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
