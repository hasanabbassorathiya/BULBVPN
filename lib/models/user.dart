import 'dart:convert';

class User {
  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final SubscriptionTier tier;
  final DateTime createdAt;
  final DateTime? subscriptionExpiry;
  final int dataUsedMB;
  final int dataLimitMB;
  final int serversConnected;

  const User({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
    this.tier = SubscriptionTier.free,
    required this.createdAt,
    this.subscriptionExpiry,
    this.dataUsedMB = 0,
    this.dataLimitMB = 500,
    this.serversConnected = 0,
  });

  bool get isPremium => tier == SubscriptionTier.pro || tier == SubscriptionTier.premium;
  bool get isFree => tier == SubscriptionTier.free;
  bool get isExpired => subscriptionExpiry != null && subscriptionExpiry!.isBefore(DateTime.now());
  bool get hasDataRemaining => dataUsedMB < dataLimitMB;

  double get dataUsagePercent => dataLimitMB > 0 ? (dataUsedMB / dataLimitMB).clamp(0.0, 1.0) : 0;

  User copyWith({
    String? displayName,
    String? avatarUrl,
    SubscriptionTier? tier,
    DateTime? subscriptionExpiry,
    int? dataUsedMB,
    int? serversConnected,
  }) {
    return User(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      tier: tier ?? this.tier,
      createdAt: createdAt,
      subscriptionExpiry: subscriptionExpiry ?? this.subscriptionExpiry,
      dataUsedMB: dataUsedMB ?? this.dataUsedMB,
      dataLimitMB: dataLimitMB,
      serversConnected: serversConnected ?? this.serversConnected,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      tier: SubscriptionTier.fromString(json['tier'] as String? ?? 'free'),
      createdAt: DateTime.parse(json['created_at'] as String),
      subscriptionExpiry: json['subscription_expiry'] != null
          ? DateTime.parse(json['subscription_expiry'] as String)
          : null,
      dataUsedMB: json['data_used_mb'] as int? ?? 0,
      dataLimitMB: json['data_limit_mb'] as int? ?? 500,
      serversConnected: json['servers_connected'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'tier': tier.value,
      'created_at': createdAt.toIso8601String(),
      'subscription_expiry': subscriptionExpiry?.toIso8601String(),
      'data_used_mb': dataUsedMB,
      'data_limit_mb': dataLimitMB,
      'servers_connected': serversConnected,
    };
  }

  String encode() => json.encode(toJson());
  factory User.decode(String source) => User.fromJson(json.decode(source));
}

enum SubscriptionTier {
  free('free'),
  pro('pro'),
  premium('premium');

  final String value;
  const SubscriptionTier(this.value);

  factory SubscriptionTier.fromString(String value) {
    return SubscriptionTier.values.firstWhere(
      (t) => t.value == value,
      orElse: () => SubscriptionTier.free,
    );
  }

  int get maxServers {
    switch (this) {
      case SubscriptionTier.free:
        return 3;
      case SubscriptionTier.pro:
        return 14;
      case SubscriptionTier.premium:
        return 14;
    }
  }

  int get dailyDataLimitMB {
    switch (this) {
      case SubscriptionTier.free:
        return 500;
      case SubscriptionTier.pro:
        return -1; // unlimited
      case SubscriptionTier.premium:
        return -1; // unlimited
    }
  }

  bool get hasDoubleVPN => this == SubscriptionTier.premium;
  bool get hasDedicatedIP => this == SubscriptionTier.premium;
  bool get hasNoAds => this != SubscriptionTier.free;
}
