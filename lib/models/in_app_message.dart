enum InAppMessageType {
  promotional,
  upgrade,
  feature,
  announcement,
  survey,
}

enum InAppMessagePosition {
  topBanner,
  bottomBanner,
  modal,
  inline,
}

class InAppMessage {
  final String id;
  final String title;
  final String body;
  final InAppMessageType type;
  final InAppMessagePosition position;
  final String? actionText;
  final String? actionRoute;
  final String? imageUrl;
  final DateTime? expiresAt;
  final int maxViews;
  final bool dismissible;

  const InAppMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.position = InAppMessagePosition.topBanner,
    this.actionText,
    this.actionRoute,
    this.imageUrl,
    this.expiresAt,
    this.maxViews = 3,
    this.dismissible = true,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  factory InAppMessage.fromJson(Map<String, dynamic> json) {
    return InAppMessage(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      type: InAppMessageType.values.firstWhere((e) => e.name == json['type']),
      position: InAppMessagePosition.values.firstWhere((e) => e.name == json['position']),
      actionText: json['actionText'] as String?,
      actionRoute: json['actionRoute'] as String?,
      imageUrl: json['imageUrl'] as String?,
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt'] as String) : null,
      maxViews: json['maxViews'] as int? ?? 3,
      dismissible: json['dismissible'] as bool? ?? true,
    );
  }
}
