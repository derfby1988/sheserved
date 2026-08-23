class AppNotification {
  final String id;
  final String professionId;
  final String recipientId;
  final String category;
  final String eventType;
  final String title;
  final String? body;
  final Map<String, dynamic> payload;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? dismissedAt;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.professionId,
    required this.recipientId,
    required this.category,
    required this.eventType,
    required this.title,
    this.body,
    this.payload = const {},
    this.isRead = false,
    this.readAt,
    this.dismissedAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      recipientId: json['recipient_id'] as String,
      category: json['category'] as String? ?? 'system',
      eventType: json['event_type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String?,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
      isRead: json['is_read'] as bool? ?? false,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      dismissedAt: json['dismissed_at'] != null
          ? DateTime.parse(json['dismissed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'recipient_id': recipientId,
      'category': category,
      'event_type': eventType,
      'title': title,
      'body': body,
      'payload': payload,
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'dismissed_at': dismissedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
