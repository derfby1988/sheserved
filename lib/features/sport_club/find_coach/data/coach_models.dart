/// Typed models for the Find Coach domain.
///
/// Mirrors the `coach_*` schema and the `*_public` discovery views.
/// Snapshot fields on [CoachBookingRequest] (rate, teaching mode, timezone,
/// requested slot) are immutable — later profile edits never rewrite a
/// request.
library;

enum CoachStatus { pending, approved, suspended }

enum TeachingMode { onsite, online, both }

enum CoachRequestStatus {
  pending,
  confirmed,
  completed,
  cancelled,
  rejected,
  expired,
}

CoachStatus coachStatusFrom(String? raw) => switch (raw) {
  'approved' => CoachStatus.approved,
  'suspended' => CoachStatus.suspended,
  _ => CoachStatus.pending,
};

TeachingMode teachingModeFrom(String? raw) => switch (raw) {
  'online' => TeachingMode.online,
  'both' => TeachingMode.both,
  _ => TeachingMode.onsite,
};

CoachRequestStatus coachRequestStatusFrom(String? raw) => switch (raw) {
  'confirmed' => CoachRequestStatus.confirmed,
  'completed' => CoachRequestStatus.completed,
  'cancelled' => CoachRequestStatus.cancelled,
  'rejected' => CoachRequestStatus.rejected,
  'expired' => CoachRequestStatus.expired,
  _ => CoachRequestStatus.pending,
};

/// A coach as shown on public discovery surfaces (approved only).
class CoachSummary {
  final String id;
  final String userId;
  final String displayName;
  final String? bio;
  final String timezone;
  final double? hourlyRate;
  final TeachingMode teachingMode;
  final bool isVerified;
  final String? avatarUrl;
  final CoachStatus? status;
  final String? rejectionReason;
  final Set<String> sportIds;
  final Set<String> skillLevels;
  final List<String> specialties;
  final List<CoachServiceArea> serviceAreas;
  final double? averageRating;
  final int reviewCount;

  const CoachSummary({
    required this.id,
    required this.userId,
    required this.displayName,
    this.bio,
    this.timezone = 'Asia/Bangkok',
    this.hourlyRate,
    this.teachingMode = TeachingMode.onsite,
    this.isVerified = false,
    this.avatarUrl,
    this.status,
    this.rejectionReason,
    this.sportIds = const {},
    this.skillLevels = const {},
    this.specialties = const [],
    this.serviceAreas = const [],
    this.averageRating,
    this.reviewCount = 0,
  });

  factory CoachSummary.fromJson(Map<String, dynamic> j) => CoachSummary(
    id: j['id']?.toString() ?? '',
    userId: j['user_id']?.toString() ?? '',
    displayName: j['display_name']?.toString() ?? '',
    bio: j['bio']?.toString(),
    timezone: j['timezone']?.toString() ?? 'Asia/Bangkok',
    hourlyRate: (j['hourly_rate'] as num?)?.toDouble(),
    teachingMode: teachingModeFrom(j['teaching_mode']?.toString()),
    isVerified: j['is_verified'] == true,
    avatarUrl: j['avatar_url']?.toString(),
    status: j['status'] == null
        ? null
        : coachStatusFrom(j['status']?.toString()),
    rejectionReason: j['rejection_reason']?.toString(),
  );

  CoachSummary copyWith({
    Set<String>? sportIds,
    Set<String>? skillLevels,
    List<String>? specialties,
    List<CoachServiceArea>? serviceAreas,
    double? averageRating,
    int? reviewCount,
  }) => CoachSummary(
    id: id,
    userId: userId,
    displayName: displayName,
    bio: bio,
    timezone: timezone,
    hourlyRate: hourlyRate,
    teachingMode: teachingMode,
    isVerified: isVerified,
    avatarUrl: avatarUrl,
    status: status,
    rejectionReason: rejectionReason,
    sportIds: sportIds ?? this.sportIds,
    skillLevels: skillLevels ?? this.skillLevels,
    specialties: specialties ?? this.specialties,
    serviceAreas: serviceAreas ?? this.serviceAreas,
    averageRating: averageRating ?? this.averageRating,
    reviewCount: reviewCount ?? this.reviewCount,
  );
}

class CoachServiceArea {
  final String? province;
  final String? district;
  final double? lat;
  final double? lng;
  final double? radiusKm;

  const CoachServiceArea({
    this.province,
    this.district,
    this.lat,
    this.lng,
    this.radiusKm,
  });

  factory CoachServiceArea.fromJson(Map<String, dynamic> j) =>
      CoachServiceArea(
        province: j['province']?.toString(),
        district: j['district']?.toString(),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        radiusKm: (j['radius_km'] as num?)?.toDouble(),
      );
}

/// Weekly availability window in coach-local time (day 0 = Sunday).
class CoachAvailabilityWindow {
  final int dayOfWeek;
  final String startTime; // 'HH:MM'
  final String endTime;

  const CoachAvailabilityWindow({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  factory CoachAvailabilityWindow.fromJson(Map<String, dynamic> j) =>
      CoachAvailabilityWindow(
        dayOfWeek: (j['day_of_week'] as num?)?.toInt() ?? 0,
        startTime: j['start_time']?.toString() ?? '',
        endTime: j['end_time']?.toString() ?? '',
      );
}

class CoachBookingRequest {
  final String id;
  final String coachId;
  final String sportId;
  final DateTime startsAt;
  final DateTime endsAt;
  final CoachRequestStatus status;
  final TeachingMode? teachingMode;
  final double? hourlyRate;
  final String? message;
  final String? coachName;
  final String? requesterName;
  final String? rejectionReason;
  final String? cancellationReason;
  final DateTime? createdAt;

  const CoachBookingRequest({
    required this.id,
    required this.coachId,
    required this.sportId,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.teachingMode,
    this.hourlyRate,
    this.message,
    this.coachName,
    this.requesterName,
    this.rejectionReason,
    this.cancellationReason,
    this.createdAt,
  });

  bool get isPending => status == CoachRequestStatus.pending;
  bool get isConfirmed => status == CoachRequestStatus.confirmed;
  bool get isCompleted => status == CoachRequestStatus.completed;

  factory CoachBookingRequest.fromJson(Map<String, dynamic> j) =>
      CoachBookingRequest(
        id: j['id']?.toString() ?? '',
        coachId: j['coachId']?.toString() ?? j['coach_id']?.toString() ?? '',
        sportId: j['sportId']?.toString() ?? j['sport_id']?.toString() ?? '',
        startsAt:
            DateTime.tryParse(
              j['startsAt']?.toString() ?? j['starts_at']?.toString() ?? '',
            ) ??
            DateTime.now(),
        endsAt:
            DateTime.tryParse(
              j['endsAt']?.toString() ?? j['ends_at']?.toString() ?? '',
            ) ??
            DateTime.now(),
        status: coachRequestStatusFrom(j['status']?.toString()),
        teachingMode: j['teachingMode'] == null
            ? null
            : teachingModeFrom(j['teachingMode']?.toString()),
        hourlyRate: (j['hourlyRate'] as num?)?.toDouble(),
        message: j['message']?.toString(),
        coachName: j['coachName']?.toString(),
        requesterName: j['requesterName']?.toString(),
        rejectionReason: j['rejectionReason']?.toString(),
        cancellationReason: j['cancellationReason']?.toString(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? ''),
      );
}

class CoachReview {
  final String id;
  final String coachId;
  final String bookingId;
  final String userId;
  final String? userDisplayName;
  final String? userAvatarUrl;
  final int rating;
  final String? comment;
  final DateTime? createdAt;

  const CoachReview({
    required this.id,
    required this.coachId,
    required this.bookingId,
    required this.userId,
    this.userDisplayName,
    this.userAvatarUrl,
    required this.rating,
    this.comment,
    this.createdAt,
  });

  factory CoachReview.fromJson(Map<String, dynamic> j) => CoachReview(
    id: j['id']?.toString() ?? '',
    coachId: j['coach_id']?.toString() ?? '',
    bookingId: j['booking_id']?.toString() ?? '',
    userId: j['user_id']?.toString() ?? '',
    userDisplayName: j['user_display_name']?.toString(),
    userAvatarUrl: j['user_avatar_url']?.toString(),
    rating: (j['rating'] as num?)?.toInt() ?? 0,
    comment: j['comment']?.toString(),
    createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
  );
}
