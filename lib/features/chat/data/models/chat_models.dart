import 'package:hive/hive.dart';

part 'chat_models.g.dart';

@HiveType(typeId: 0)
class ChatRoom {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final List<String> participantIds;
  @HiveField(2)
  final String? lastMessage;
  @HiveField(3)
  final DateTime updatedAt;
  @HiveField(4)
  final Map<dynamic, dynamic>? metadata;
  @HiveField(5)
  final String? roomType;
  @HiveField(6)
  final String? consultationId;
  @HiveField(7)
  final String? packageId;
  @HiveField(8)
  final String? title;
  @HiveField(9)
  final bool isActive;
  @HiveField(10)
  final DateTime? expiresAt;
  @HiveField(11)
  final int? sessionMinutes;
  @HiveField(12)
  final DateTime? startedAt;
  @HiveField(13)
  final DateTime? endedAt;

  ChatRoom({
    required this.id,
    required this.participantIds,
    this.lastMessage,
    required this.updatedAt,
    this.metadata,
    this.roomType,
    this.consultationId,
    this.packageId,
    this.title,
    this.isActive = true,
    this.expiresAt,
    this.sessionMinutes,
    this.startedAt,
    this.endedAt,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'],
      participantIds: List<String>.from(json['participant_ids'] ?? []),
      lastMessage: json['last_message'],
      updatedAt: DateTime.parse(json['updated_at']),
      metadata: json['metadata'],
      roomType: json['room_type'] ?? json['roomType'],
      consultationId: json['consultation_id'] ?? json['consultationId'],
      packageId: json['package_id'] ?? json['packageId'],
      title: json['title'],
      isActive: json['is_active'] ?? json['isActive'] ?? true,
      expiresAt: (json['expires_at'] ?? json['expiresAt']) != null ? DateTime.parse(json['expires_at'] ?? json['expiresAt']) : null,
      sessionMinutes: json['session_minutes'] ?? json['sessionMinutes'],
      startedAt: (json['started_at'] ?? json['startedAt']) != null ? DateTime.parse(json['started_at'] ?? json['startedAt']) : null,
      endedAt: (json['ended_at'] ?? json['endedAt']) != null ? DateTime.parse(json['ended_at'] ?? json['endedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participant_ids': participantIds,
      'last_message': lastMessage,
      'updated_at': updatedAt.toIso8601String(),
      'metadata': metadata,
      'room_type': roomType,
      'consultation_id': consultationId,
      'package_id': packageId,
      'title': title,
      'is_active': isActive,
      'expires_at': expiresAt?.toIso8601String(),
      'session_minutes': sessionMinutes,
      'started_at': startedAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
    };
  }
}

@HiveType(typeId: 1)
enum MessageStatus { 
  @HiveField(0)
  sent, 
  @HiveField(1)
  delivered, 
  @HiveField(2)
  read 
}

@HiveType(typeId: 2)
class ChatMessage {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String roomId;
  @HiveField(2)
  final String senderId;
  @HiveField(3)
  final String content;
  @HiveField(4)
  final DateTime createdAt;
  @HiveField(5)
  final MessageStatus status;
  @HiveField(6)
  final String type; // 'text', 'image', 'file'
  @HiveField(7)
  final String? attachmentUrl;
  @HiveField(8)
  final String? attachmentType;
  @HiveField(9)
  final Map<String, DateTime> readBy; // userId -> timestamp
  @HiveField(10)
  final String? bodyPart;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.sent,
    this.type = 'text',
    this.attachmentUrl,
    this.attachmentType,
    this.readBy = const {},
    this.bodyPart,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      roomId: json['room_id'],
      senderId: json['sender_id'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == (json['status'] ?? 'sent'),
        orElse: () => MessageStatus.sent,
      ),
      type: json['type'] ?? 'text',
      attachmentUrl: json['attachment_url'],
      attachmentType: json['attachment_type'],
      readBy: (json['read_by'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, DateTime.parse(v)),
          ) ??
          {},
      bodyPart: json['body_part'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'status': status.name,
      'type': type,
      'attachment_url': attachmentUrl,
      'attachment_type': attachmentType,
      'read_by': readBy.map((k, v) => MapEntry(k, v.toIso8601String())),
      'body_part': bodyPart,
    };
  }

  ChatMessage copyWith({
    String? id,
    String? roomId,
    String? senderId,
    String? content,
    DateTime? createdAt,
    MessageStatus? status,
    String? type,
    String? attachmentUrl,
    String? attachmentType,
    Map<String, DateTime>? readBy,
    String? bodyPart,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      type: type ?? this.type,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      attachmentType: attachmentType ?? this.attachmentType,
      readBy: readBy ?? this.readBy,
      bodyPart: bodyPart ?? this.bodyPart,
    );
  }
}

@HiveType(typeId: 3)
class ChatParticipant {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String firstName;
  @HiveField(2)
  final String lastName;
  @HiveField(3)
  final String? profileImageUrl;
  @HiveField(4)
  final DateTime? lastSeenAt;
  @HiveField(5)
  final String availabilityStatus;

  ChatParticipant({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.profileImageUrl,
    this.lastSeenAt,
    this.availabilityStatus = 'online',
  });

  /// ถือว่า online ถ้า last_seen_at อัปเดตภายใน 2 นาทีที่ผ่านมา และไม่อยู่ในสถานะ busy/offline
  bool get isOnline {
    if (lastSeenAt == null) return false;
    if (availabilityStatus == 'busy' || availabilityStatus == 'offline') return false;
    return DateTime.now().toUtc().difference(lastSeenAt!).inMinutes < 2;
  }

  bool get isBusy => availabilityStatus == 'busy';

  String get fullName => '$firstName $lastName';

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id'],
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      profileImageUrl: json['profile_image_url'],
      lastSeenAt: json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at']) : null,
      availabilityStatus: json['availability_status'] ?? 'online',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'profile_image_url': profileImageUrl,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'availability_status': availabilityStatus,
    };
  }
}
