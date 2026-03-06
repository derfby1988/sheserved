/// Video Models สำหรับระบบวิดีโอ

enum VideoType { normal, emergency }

enum VideoStatus { processing, uploading, ready, error }

/// Model สำหรับวิดีโอ
class Video {
  final String id;
  final String userId;
  final VideoType type;
  final String? donationRequestId;
  final String title;
  final String? description;
  final String? bunnyVideoId;
  final String? bunnyUrl;
  final String? thumbnailUrl;
  final int? duration;
  final int? fileSize;
  final VideoStatus status;
  final int progress;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Joined data
  final String? userName;
  final String? userAvatar;
  final String? userRole;
  final int viewerCount;
  final int likeCount;
  final double donationTotal;

  const Video({
    required this.id,
    required this.userId,
    this.type = VideoType.normal,
    this.donationRequestId,
    required this.title,
    this.description,
    this.bunnyVideoId,
    this.bunnyUrl,
    this.thumbnailUrl,
    this.duration,
    this.fileSize,
    this.status = VideoStatus.processing,
    this.progress = 0,
    required this.createdAt,
    this.updatedAt,
    this.userName,
    this.userAvatar,
    this.userRole,
    this.viewerCount = 0,
    this.likeCount = 0,
    this.donationTotal = 0,
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    return Video(
      id: json['id'],
      userId: json['user_id'],
      type: json['type'] == 'emergency' ? VideoType.emergency : VideoType.normal,
      donationRequestId: json['donation_request_id'],
      title: json['title'] ?? '',
      description: json['description'],
      bunnyVideoId: json['bunny_video_id'],
      bunnyUrl: json['bunny_url'],
      thumbnailUrl: json['thumbnail_url'],
      duration: json['duration'],
      fileSize: json['file_size'],
      status: VideoStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => VideoStatus.processing,
      ),
      progress: json['progress'] ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  bool get isEmergency => type == VideoType.emergency;
  bool get isReady => status == VideoStatus.ready;
  bool get isProcessing => status == VideoStatus.processing;
}

/// Model สำหรับ GPS Track ที่สัมพันธ์กับเวลาในวิดีโอ
class VideoGpsTrack {
  final String id;
  final String videoId;
  final double latitude;
  final double longitude;
  final int timestampOffset; // วินาทีจากจุดเริ่มต้นวิดีโอ

  const VideoGpsTrack({
    required this.id,
    required this.videoId,
    required this.latitude,
    required this.longitude,
    required this.timestampOffset,
  });

  factory VideoGpsTrack.fromJson(Map<String, dynamic> json) {
    return VideoGpsTrack(
      id: json['id'],
      videoId: json['video_id'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestampOffset: json['timestamp_offset'] ?? 0,
    );
  }
}

/// Model สำหรับ Interaction (Like, Gift, View)
class VideoInteraction {
  final String id;
  final String videoId;
  final String userId;
  final String type; // like, gift, view
  final int value;
  final DateTime createdAt;

  const VideoInteraction({
    required this.id,
    required this.videoId,
    required this.userId,
    required this.type,
    this.value = 0,
    required this.createdAt,
  });

  factory VideoInteraction.fromJson(Map<String, dynamic> json) {
    return VideoInteraction(
      id: json['id'],
      videoId: json['video_id'],
      userId: json['user_id'],
      type: json['type'] ?? 'view',
      value: json['value'] ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'video_id': videoId,
    'user_id': userId,
    'type': type,
    'value': value,
  };
}
