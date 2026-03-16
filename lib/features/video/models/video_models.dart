/// Video Models สำหรับระบบวิดีโอ

enum VideoType { normal, emergency }

enum VideoStatus { processing, uploading, ready, error }

/// Model สำหรับวิดีโอ
class Video {
  final String id;
  final String userId;
  final VideoType type;
  final String? donationRequestId;
  final String? categoryId;
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
  final double latitude;
  final double longitude;
  final String? address;
  final String? road;
  final String? soi;
  final String? alley;
  final String? village;
  final bool isThaiMhungEnabled;

  // Joined data
  final String? userName;
  final String? userAvatar;
  final String? userRole;
  final int viewerCount;
  final int likeCount;
  final double donationTotal;
  final String? categoryName;

  /// path ไปยังไฟล์วิดีโอในเครื่อง สำหรับ Immediate Preview ก่อน HLS พร้อม
  /// null = ไม่มี local cache (ดูจาก bunnyUrl แทน)
  final String? localFilePath;

  const Video({
    required this.id,
    required this.userId,
    this.type = VideoType.normal,
    this.donationRequestId,
    this.categoryId,
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
    this.categoryName,
    this.viewerCount = 0,
    this.likeCount = 0,
    this.donationTotal = 0,
    this.latitude = 0,
    this.longitude = 0,
    this.address,
    this.road,
    this.soi,
    this.alley,
    this.village,
    this.isThaiMhungEnabled = false,
    this.localFilePath,
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    // Helper function for safe int parsing
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return Video(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      type: json['type'] == 'emergency' ? VideoType.emergency : VideoType.normal,
      donationRequestId: json['donation_request_id']?.toString(),
      categoryId: json['category_id']?.toString(),
      title: json['title'] ?? '',
      description: json['description']?.toString(),
      bunnyVideoId: json['bunny_video_id']?.toString(),
      bunnyUrl: json['bunny_url']?.toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      duration: parseInt(json['duration']),
      fileSize: parseInt(json['file_size']),
      status: VideoStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => VideoStatus.processing,
      ),
      progress: parseInt(json['progress']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      userName: json['user_name']?.toString(),
      userAvatar: json['user_avatar']?.toString(),
      userRole: json['user_role']?.toString(),
      categoryName: json['category_name']?.toString() ?? 
                    (json['donation_categories'] != null ? json['donation_categories']['name']?.toString() : null),
      viewerCount: parseInt(json['viewer_count']),
      likeCount: parseInt(json['like_count']),
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      address: json['address']?.toString(),
      road: json['road']?.toString(),
      soi: json['soi']?.toString(),
      alley: json['alley']?.toString(),
      village: json['village']?.toString(),
      isThaiMhungEnabled: json['is_thai_mhung_enabled'] == true || json['isThaiMhungEnabled'] == true,
      localFilePath: json['local_file_path']?.toString(),
    );
  }

  Video copyWith({
    String? id,
    String? userId,
    VideoType? type,
    String? donationRequestId,
    String? categoryId,
    String? title,
    String? description,
    String? bunnyVideoId,
    String? bunnyUrl,
    String? thumbnailUrl,
    int? duration,
    int? fileSize,
    VideoStatus? status,
    int? progress,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? userName,
    String? userAvatar,
    String? userRole,
    String? categoryName,
    int? viewerCount,
    int? likeCount,
    double? donationTotal,
    double? latitude,
    double? longitude,
    String? address,
    String? road,
    String? soi,
    String? alley,
    String? village,
    bool? isThaiMhungEnabled,
    String? localFilePath,
  }) {
    return Video(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      donationRequestId: donationRequestId ?? this.donationRequestId,
      categoryId: categoryId ?? this.categoryId,
      title: title ?? this.title,
      description: description ?? this.description,
      bunnyVideoId: bunnyVideoId ?? this.bunnyVideoId,
      bunnyUrl: bunnyUrl ?? this.bunnyUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      userRole: userRole ?? this.userRole,
      categoryName: categoryName ?? this.categoryName,
      viewerCount: viewerCount ?? this.viewerCount,
      likeCount: likeCount ?? this.likeCount,
      donationTotal: donationTotal ?? this.donationTotal,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      road: road ?? this.road,
      soi: soi ?? this.soi,
      alley: alley ?? this.alley,
      village: village ?? this.village,
      isThaiMhungEnabled: isThaiMhungEnabled ?? this.isThaiMhungEnabled,
      localFilePath: localFilePath ?? this.localFilePath,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'type': type.name,
    'donation_request_id': donationRequestId,
    'category_id': categoryId,
    'title': title,
    'description': description,
    'bunny_video_id': bunnyVideoId,
    'bunny_url': bunnyUrl,
    'thumbnail_url': thumbnailUrl,
    'duration': duration,
    'file_size': fileSize,
    'status': status.name,
    'progress': progress,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
    'is_thai_mhung_enabled': isThaiMhungEnabled,
    'local_file_path': localFilePath,
  };

  bool get isEmergency => type == VideoType.emergency;
  bool get isReady => status == VideoStatus.ready;
  bool get isProcessing => status == VideoStatus.processing;

  /// ใช้ Local file สำหรับ preview ถ้ามี ไม่เช่นนั้นใช้ bunnyUrl
  String? get previewUrl => localFilePath ?? bunnyUrl;
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
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return VideoGpsTrack(
      id: json['id']?.toString() ?? '',
      videoId: json['video_id']?.toString() ?? '',
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      timestampOffset: parseInt(json['timestamp_offset']),
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
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return VideoInteraction(
      id: json['id']?.toString() ?? '',
      videoId: json['video_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'view',
      value: parseInt(json['value']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
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
