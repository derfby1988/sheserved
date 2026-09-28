/// Typed models for the Find Coach domain.
///
/// Mirrors the `coach_*` schema and the `*_public` discovery views.
/// Snapshot fields on [CoachBookingRequest] (rate, teaching mode, timezone,
/// requested slot) are immutable — later profile edits never rewrite a
/// request.
library;

enum CoachStatus { pending, approved, rejected, suspended }

enum CoachOfferingType { oneOnOne, groupClass, course }

enum CoachOfferingStatus { draft, published, closed, cancelled, completed }

enum CoachPricingUnit { perHour, perPerson, perGroup, perSession, package }

enum CoachSlotStatus { draft, published, booked, cancelled, expired }

enum CoachEnrollmentStatus {
  pending,
  confirmed,
  rejected,
  cancelled,
  expired,
  completed,
}

enum CoachLocationKind { venue, custom }

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
  'rejected' => CoachStatus.rejected,
  'suspended' => CoachStatus.suspended,
  _ => CoachStatus.pending,
};

CoachOfferingType coachOfferingTypeFrom(String? raw) => switch (raw) {
  'one_on_one' => CoachOfferingType.oneOnOne,
  'course' => CoachOfferingType.course,
  _ => CoachOfferingType.groupClass,
};

CoachOfferingStatus coachOfferingStatusFrom(String? raw) => switch (raw) {
  'published' => CoachOfferingStatus.published,
  'closed' => CoachOfferingStatus.closed,
  'cancelled' => CoachOfferingStatus.cancelled,
  'completed' => CoachOfferingStatus.completed,
  _ => CoachOfferingStatus.draft,
};

CoachPricingUnit coachPricingUnitFrom(String? raw) => switch (raw) {
  'per_person' => CoachPricingUnit.perPerson,
  'per_group' => CoachPricingUnit.perGroup,
  'per_session' => CoachPricingUnit.perSession,
  'package' => CoachPricingUnit.package,
  _ => CoachPricingUnit.perHour,
};

CoachSlotStatus coachSlotStatusFrom(String? raw) => switch (raw) {
  'published' => CoachSlotStatus.published,
  'booked' => CoachSlotStatus.booked,
  'cancelled' => CoachSlotStatus.cancelled,
  'expired' => CoachSlotStatus.expired,
  _ => CoachSlotStatus.draft,
};

CoachEnrollmentStatus coachEnrollmentStatusFrom(String? raw) =>
    switch (raw) {
      'confirmed' => CoachEnrollmentStatus.confirmed,
      'rejected' => CoachEnrollmentStatus.rejected,
      'cancelled' => CoachEnrollmentStatus.cancelled,
      'expired' => CoachEnrollmentStatus.expired,
      'completed' => CoachEnrollmentStatus.completed,
      _ => CoachEnrollmentStatus.pending,
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
  final String? experience;
  final String timezone;
  final double? hourlyRate;
  final TeachingMode teachingMode;
  final bool isVerified;
  final String? avatarUrl;
  final String? coverUrl;
  final bool acceptingStudents;
  final bool hasOpenAvailability;
  final CoachStatus? status;
  final String? rejectionReason;
  final Set<String> sportIds;
  final Set<String> skillLevels;
  final List<String> specialties;
  final List<CoachServiceArea> serviceAreas;
  final Set<String> offeringTypes;
  final double? averageRating;
  final double? averageRating10;
  final int reviewCount;

  const CoachSummary({
    required this.id,
    required this.userId,
    required this.displayName,
    this.bio,
    this.experience,
    this.timezone = 'Asia/Bangkok',
    this.hourlyRate,
    this.teachingMode = TeachingMode.onsite,
    this.isVerified = false,
    this.avatarUrl,
    this.coverUrl,
    this.acceptingStudents = true,
    this.hasOpenAvailability = false,
    this.status,
    this.rejectionReason,
    this.sportIds = const {},
    this.skillLevels = const {},
    this.specialties = const [],
    this.serviceAreas = const [],
    this.offeringTypes = const {},
    this.averageRating,
    this.averageRating10,
    this.reviewCount = 0,
  });

  factory CoachSummary.fromJson(Map<String, dynamic> j) => CoachSummary(
    id: j['id']?.toString() ?? '',
    userId: j['user_id']?.toString() ?? '',
    displayName: j['display_name']?.toString() ?? '',
    bio: j['bio']?.toString(),
    experience: j['experience']?.toString(),
    timezone: j['timezone']?.toString() ?? 'Asia/Bangkok',
    hourlyRate: (j['hourly_rate'] as num?)?.toDouble(),
    teachingMode: teachingModeFrom(j['teaching_mode']?.toString()),
    isVerified: j['is_verified'] == true,
    avatarUrl: j['avatar_url']?.toString(),
    coverUrl: j['cover_url']?.toString(),
    acceptingStudents: j['accepting_students'] != false,
    hasOpenAvailability: j['has_open_availability'] == true,
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
    Set<String>? offeringTypes,
    double? averageRating,
    double? averageRating10,
    int? reviewCount,
  }) => CoachSummary(
    id: id,
    userId: userId,
    displayName: displayName,
    bio: bio,
    experience: experience,
    timezone: timezone,
    hourlyRate: hourlyRate,
    teachingMode: teachingMode,
    isVerified: isVerified,
    avatarUrl: avatarUrl,
    coverUrl: coverUrl,
    acceptingStudents: acceptingStudents,
    hasOpenAvailability: hasOpenAvailability,
    status: status,
    rejectionReason: rejectionReason,
    sportIds: sportIds ?? this.sportIds,
    skillLevels: skillLevels ?? this.skillLevels,
    specialties: specialties ?? this.specialties,
    serviceAreas: serviceAreas ?? this.serviceAreas,
    offeringTypes: offeringTypes ?? this.offeringTypes,
    averageRating: averageRating ?? this.averageRating,
    averageRating10: averageRating10 ?? this.averageRating10,
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
  final String? enrollmentId;
  final String? sessionId;
  final String userId;
  final String? userDisplayName;
  final String? userAvatarUrl;
  final int rating;
  final double? rating10;
  final bool isLegacy;
  final String? comment;
  final List<String> tagLabels;
  final Map<String, int> categoryScores;
  final int helpfulCount;
  final bool viewerVoted;
  final DateTime? createdAt;

  const CoachReview({
    required this.id,
    required this.coachId,
    required this.bookingId,
    this.enrollmentId,
    this.sessionId,
    required this.userId,
    this.userDisplayName,
    this.userAvatarUrl,
    required this.rating,
    this.rating10,
    this.isLegacy = false,
    this.comment,
    this.tagLabels = const [],
    this.categoryScores = const {},
    this.helpfulCount = 0,
    this.viewerVoted = false,
    this.createdAt,
  });

  factory CoachReview.fromJson(Map<String, dynamic> j) => CoachReview(
    id: j['id']?.toString() ?? '',
    coachId: j['coach_id']?.toString() ?? '',
    bookingId: j['booking_id']?.toString() ?? '',
    enrollmentId: j['enrollment_id']?.toString(),
    sessionId: j['session_id']?.toString(),
    userId: j['user_id']?.toString() ?? '',
    userDisplayName: j['user_display_name']?.toString(),
    userAvatarUrl: j['user_avatar_url']?.toString(),
    rating: (j['rating'] as num?)?.toInt() ?? 0,
    rating10: (j['rating_10'] as num?)?.toDouble(),
    isLegacy: j['is_legacy'] == true,
    comment: j['comment']?.toString(),
    tagLabels: (j['tag_labels'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    categoryScores: (j['category_scores'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ) ??
        const {},
    helpfulCount: (j['helpful_count'] as num?)?.toInt() ?? 0,
    viewerVoted: j['viewer_voted'] == true,
    createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
  );
}

/// Private contact channels — only readable by the coach, an admin, or a
/// learner with a confirmed/completed relationship.
class CoachContact {
  final String? phone;
  final String? lineId;
  final String? facebookUrl;

  const CoachContact({this.phone, this.lineId, this.facebookUrl});

  bool get isEmpty =>
      (phone?.isEmpty ?? true) &&
      (lineId?.isEmpty ?? true) &&
      (facebookUrl?.isEmpty ?? true);

  factory CoachContact.fromJson(Map<String, dynamic> j) => CoachContact(
    phone: j['phone']?.toString(),
    lineId: j['line_id']?.toString(),
    facebookUrl: j['facebook_url']?.toString(),
  );
}

enum CoachCertStatus { pending, approved, rejected }

class CoachCertification {
  final String id;
  final String name;
  final String? issuer;
  final int? issuedYear;
  final String? documentUrl;
  final CoachCertStatus status;
  final String? rejectionReason;

  const CoachCertification({
    required this.id,
    required this.name,
    this.issuer,
    this.issuedYear,
    this.documentUrl,
    this.status = CoachCertStatus.pending,
    this.rejectionReason,
  });

  factory CoachCertification.fromJson(Map<String, dynamic> j) =>
      CoachCertification(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        issuer: j['issuer']?.toString(),
        issuedYear: (j['issued_year'] as num?)?.toInt(),
        documentUrl: j['document_url']?.toString(),
        status: switch (j['status']?.toString()) {
          'approved' => CoachCertStatus.approved,
          'rejected' => CoachCertStatus.rejected,
          _ => CoachCertStatus.pending,
        },
        rejectionReason: j['rejection_reason']?.toString(),
      );

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'name': name,
    if (issuer != null) 'issuer': issuer,
    if (issuedYear != null) 'issued_year': issuedYear,
    if (documentUrl != null) 'document_url': documentUrl,
  };
}

class CoachTeachingLocation {
  final String id;
  final CoachLocationKind kind;
  final String? venueId;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final String timezone;

  const CoachTeachingLocation({
    required this.id,
    this.kind = CoachLocationKind.custom,
    this.venueId,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.timezone = 'Asia/Bangkok',
  });

  factory CoachTeachingLocation.fromJson(Map<String, dynamic> j) =>
      CoachTeachingLocation(
        id: j['id']?.toString() ?? '',
        kind: j['kind']?.toString() == 'venue'
            ? CoachLocationKind.venue
            : CoachLocationKind.custom,
        venueId: j['venue_id']?.toString(),
        name: j['name']?.toString() ?? '',
        address: j['address']?.toString(),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        timezone: j['timezone']?.toString() ?? 'Asia/Bangkok',
      );

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'kind': kind == CoachLocationKind.venue ? 'venue' : 'custom',
    if (venueId != null) 'venue_id': venueId,
    'name': name,
    if (address != null) 'address': address,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    'timezone': timezone,
  };
}

/// One session inside a class/course offering.
class CoachOfferingSession {
  final String id;
  final int seq;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timezone;
  final String? locationLabel;
  final int? capacity;
  final double? price;
  final String status; // scheduled | cancelled | completed
  final int confirmedCount;
  final int pendingCount;
  final String? myEnrollmentStatus;

  const CoachOfferingSession({
    required this.id,
    this.seq = 0,
    required this.startsAt,
    required this.endsAt,
    this.timezone = 'Asia/Bangkok',
    this.locationLabel,
    this.capacity,
    this.price,
    this.status = 'scheduled',
    this.confirmedCount = 0,
    this.pendingCount = 0,
    this.myEnrollmentStatus,
  });

  bool get isScheduled => status == 'scheduled';
  bool get isFull =>
      capacity != null && confirmedCount >= capacity!;
  bool get isFuture => startsAt.isAfter(DateTime.now());

  factory CoachOfferingSession.fromJson(Map<String, dynamic> j) =>
      CoachOfferingSession(
        id: j['id']?.toString() ?? '',
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        startsAt: DateTime.tryParse(j['startsAt']?.toString() ?? '') ??
            DateTime.now(),
        endsAt: DateTime.tryParse(j['endsAt']?.toString() ?? '') ??
            DateTime.now(),
        timezone: j['timezone']?.toString() ?? 'Asia/Bangkok',
        locationLabel: j['locationLabel']?.toString(),
        capacity: (j['capacity'] as num?)?.toInt(),
        price: (j['price'] as num?)?.toDouble(),
        status: j['status']?.toString() ?? 'scheduled',
        confirmedCount: (j['confirmedCount'] as num?)?.toInt() ?? 0,
        pendingCount: (j['pendingCount'] as num?)?.toInt() ?? 0,
        myEnrollmentStatus: j['myEnrollmentStatus']?.toString(),
      );
}

/// A sellable coach product: 1:1 product, single-session class, or
/// multi-session course.
class CoachOffering {
  final String id;
  final CoachOfferingType type;
  final String title;
  final String? description;
  final String? sportId;
  final List<String> learnerLevels;
  final TeachingMode teachingMode;
  final String? locationId;
  final String? locationLabel;
  final String timezone;
  final double? price;
  final CoachPricingUnit pricingUnit;
  final int? capacity;
  final int minEnrollment;
  final int enrollmentCutoffHours;
  final int cancellationCutoffHours;
  final String cancellationPolicyVersion;
  final String scheduleNoResponse; // 'cancel' | 'keep'
  final bool autoConfirm;
  final bool allowPartialEnrollment;
  final CoachOfferingStatus status;
  final String? minDecision;
  final DateTime? reopenUntil;
  final DateTime? createdAt;
  final DateTime? firstSessionStart;
  final int confirmedCount;
  final int pendingCount;
  final List<CoachOfferingSession> sessions;
  final String? myEnrollmentId;

  const CoachOffering({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.sportId,
    this.learnerLevels = const [],
    this.teachingMode = TeachingMode.onsite,
    this.locationId,
    this.locationLabel,
    this.timezone = 'Asia/Bangkok',
    this.price,
    this.pricingUnit = CoachPricingUnit.perHour,
    this.capacity,
    this.minEnrollment = 0,
    this.enrollmentCutoffHours = 24,
    this.cancellationCutoffHours = 24,
    this.cancellationPolicyVersion = 'platform-v1',
    this.scheduleNoResponse = 'cancel',
    this.autoConfirm = false,
    this.allowPartialEnrollment = true,
    this.status = CoachOfferingStatus.draft,
    this.minDecision,
    this.reopenUntil,
    this.createdAt,
    this.firstSessionStart,
    this.confirmedCount = 0,
    this.pendingCount = 0,
    this.sessions = const [],
    this.myEnrollmentId,
  });

  bool get isOneOnOne => type == CoachOfferingType.oneOnOne;
  bool get isOpen => status == CoachOfferingStatus.published;
  bool get isClosed => status == CoachOfferingStatus.closed;
  bool get isDone =>
      status == CoachOfferingStatus.cancelled ||
      status == CoachOfferingStatus.completed;

  List<CoachOfferingSession> get activeSessions => sessions
      .where((s) => s.isScheduled && s.isFuture)
      .toList();

  List<CoachOfferingSession> get pastSessions => sessions
      .where((s) => !s.isScheduled || !s.isFuture)
      .toList();

  /// Whether the minimum-enrollment decision is due: intake cut off,
  /// below minimum, still undecided, and before the first session.
  bool get isMinimumDecisionDue {
    if (minEnrollment <= 0 || minDecision != null || isDone) {
      return false;
    }
    final first = firstSessionStart;
    if (first == null || !DateTime.now().isBefore(first)) return false;
    if (confirmedCount >= minEnrollment) return false;
    final cutoff = first.subtract(Duration(hours: enrollmentCutoffHours));
    final now = DateTime.now();
    return !now.isBefore(cutoff) ||
        (reopenUntil != null && now.isBefore(reopenUntil!));
  }

  factory CoachOffering.fromJson(Map<String, dynamic> j) => CoachOffering(
    id: j['id']?.toString() ?? '',
    type: coachOfferingTypeFrom(j['offeringType']?.toString()),
    title: j['title']?.toString() ?? '',
    description: j['description']?.toString(),
    sportId: j['sportId']?.toString(),
    learnerLevels: (j['learnerLevels'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    teachingMode: teachingModeFrom(j['teachingMode']?.toString()),
    locationId: j['locationId']?.toString(),
    locationLabel: j['locationLabel']?.toString(),
    timezone: j['timezone']?.toString() ?? 'Asia/Bangkok',
    price: (j['price'] as num?)?.toDouble(),
    pricingUnit: coachPricingUnitFrom(j['pricingUnit']?.toString()),
    capacity: (j['capacity'] as num?)?.toInt(),
    minEnrollment: (j['minEnrollment'] as num?)?.toInt() ?? 0,
    enrollmentCutoffHours:
        (j['enrollmentCutoffHours'] as num?)?.toInt() ?? 24,
    cancellationCutoffHours:
        (j['cancellationCutoffHours'] as num?)?.toInt() ?? 24,
    cancellationPolicyVersion:
        j['cancellationPolicyVersion']?.toString() ?? 'platform-v1',
    scheduleNoResponse: j['scheduleNoResponse']?.toString() ?? 'cancel',
    autoConfirm: j['autoConfirm'] == true,
    allowPartialEnrollment: j['allowPartialEnrollment'] != false,
    status: coachOfferingStatusFrom(j['status']?.toString()),
    minDecision: j['minDecision']?.toString(),
    reopenUntil: DateTime.tryParse(j['reopenUntil']?.toString() ?? ''),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? ''),
    firstSessionStart:
        DateTime.tryParse(j['firstSessionStart']?.toString() ?? ''),
    confirmedCount: (j['confirmedCount'] as num?)?.toInt() ?? 0,
    pendingCount: (j['pendingCount'] as num?)?.toInt() ?? 0,
    sessions: (j['sessions'] as List?)
            ?.map(
              (e) => CoachOfferingSession.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList() ??
        const [],
    myEnrollmentId: j['myEnrollmentId']?.toString(),
  );
}

/// A coach-published 1:1 slot.
class CoachSlot {
  final String id;
  final String offeringId;
  final String? offeringTitle;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timezone;
  final double? price;
  final CoachSlotStatus status;
  final int pendingRequests;

  const CoachSlot({
    required this.id,
    required this.offeringId,
    this.offeringTitle,
    required this.startsAt,
    required this.endsAt,
    this.timezone = 'Asia/Bangkok',
    this.price,
    this.status = CoachSlotStatus.draft,
    this.pendingRequests = 0,
  });

  bool get isBookable =>
      status == CoachSlotStatus.published &&
      startsAt.isAfter(DateTime.now());

  factory CoachSlot.fromJson(Map<String, dynamic> j) => CoachSlot(
    id: j['id']?.toString() ?? '',
    offeringId: j['offeringId']?.toString() ?? '',
    offeringTitle: j['offeringTitle']?.toString(),
    startsAt: DateTime.tryParse(j['startsAt']?.toString() ??
            j['starts_at']?.toString() ??
            '') ??
        DateTime.now(),
    endsAt: DateTime.tryParse(j['endsAt']?.toString() ??
            j['ends_at']?.toString() ??
            '') ??
        DateTime.now(),
    timezone: j['timezone']?.toString() ?? 'Asia/Bangkok',
    price: (j['price'] as num?)?.toDouble() ??
        (j['price_snapshot'] as num?)?.toDouble(),
    status: coachSlotStatusFrom(j['status']?.toString()),
    pendingRequests: (j['pendingRequests'] as num?)?.toInt() ?? 0,
  );
}

/// An open schedule-change proposal attached to a learner's
/// enrollment-session.
class CoachScheduleProposal {
  final String id;
  final DateTime newStartsAt;
  final DateTime newEndsAt;
  final String? newLocation;
  final String? reason;
  final String? myResponse; // 'accepted' | 'declined' | null

  const CoachScheduleProposal({
    required this.id,
    required this.newStartsAt,
    required this.newEndsAt,
    this.newLocation,
    this.reason,
    this.myResponse,
  });

  bool get needsResponse => myResponse == null;

  factory CoachScheduleProposal.fromJson(Map<String, dynamic> j) =>
      CoachScheduleProposal(
        id: j['id']?.toString() ?? '',
        newStartsAt:
            DateTime.tryParse(j['newStartsAt']?.toString() ?? '') ??
                DateTime.now(),
        newEndsAt:
            DateTime.tryParse(j['newEndsAt']?.toString() ?? '') ??
                DateTime.now(),
        newLocation: j['newLocation']?.toString(),
        reason: j['reason']?.toString(),
        myResponse: j['myResponse']?.toString(),
      );
}

/// One session inside a learner's enrollment, including the effective
/// (overridden) time and the original snapshot.
class CoachEnrollmentSession {
  final String sessionId;
  final int seq;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime? originalStartsAt;
  final DateTime? originalEndsAt;
  final String timezone;
  final String? locationLabel;
  final String status;
  final double? price;
  final int? capacity;
  final int confirmedCount;
  final bool hasReview;
  final CoachScheduleProposal? proposal;

  const CoachEnrollmentSession({
    required this.sessionId,
    this.seq = 0,
    required this.startsAt,
    required this.endsAt,
    this.originalStartsAt,
    this.originalEndsAt,
    this.timezone = 'Asia/Bangkok',
    this.locationLabel,
    this.status = 'pending',
    this.price,
    this.capacity,
    this.confirmedCount = 0,
    this.hasReview = false,
    this.proposal,
  });

  bool get isCompleted => status == 'completed';
  bool get isLive => status == 'pending' || status == 'confirmed';
  bool get wasRescheduled =>
      originalStartsAt != null && originalStartsAt != startsAt;

  factory CoachEnrollmentSession.fromJson(Map<String, dynamic> j) =>
      CoachEnrollmentSession(
        sessionId: j['sessionId']?.toString() ?? '',
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        startsAt:
            DateTime.tryParse(j['startsAt']?.toString() ?? '') ??
                DateTime.now(),
        endsAt:
            DateTime.tryParse(j['endsAt']?.toString() ?? '') ??
                DateTime.now(),
        originalStartsAt:
            DateTime.tryParse(j['originalStartsAt']?.toString() ?? ''),
        originalEndsAt:
            DateTime.tryParse(j['originalEndsAt']?.toString() ?? ''),
        timezone: j['timezone']?.toString() ?? 'Asia/Bangkok',
        locationLabel: j['locationLabel']?.toString(),
        status: j['status']?.toString() ?? 'pending',
        price: (j['price'] as num?)?.toDouble(),
        capacity: (j['capacity'] as num?)?.toInt(),
        confirmedCount: (j['confirmedCount'] as num?)?.toInt() ?? 0,
        hasReview: j['hasReview'] == true,
        proposal: j['proposal'] == null
            ? null
            : CoachScheduleProposal.fromJson(
                Map<String, dynamic>.from(j['proposal'] as Map),
              ),
      );
}

/// A learner's enrollment in a class/course offering.
class CoachEnrollment {
  final String id;
  final String offeringId;
  final String offeringTitle;
  final CoachOfferingType offeringType;
  final String coachId;
  final String coachName;
  final String? learnerName;
  final String? userId;
  final String scope; // 'course' | 'sessions'
  final CoachEnrollmentStatus status;
  final double? priceTotal;
  final CoachPricingUnit? pricingUnit;
  final int cancellationCutoffHours;
  final String? cancellationPolicyVersion;
  final String? cancellationPolicyText;
  final DateTime? consentAt;
  final String? rejectionReason;
  final String? cancellationReason;
  final int minEnrollment;
  final int confirmedCount;
  final bool autoConfirm;
  final CoachOfferingStatus? offeringStatus;
  final List<CoachEnrollmentSession> sessions;
  final DateTime? createdAt;

  const CoachEnrollment({
    required this.id,
    required this.offeringId,
    required this.offeringTitle,
    required this.offeringType,
    required this.coachId,
    this.coachName = '',
    this.learnerName,
    this.userId,
    this.scope = 'sessions',
    this.status = CoachEnrollmentStatus.pending,
    this.priceTotal,
    this.pricingUnit,
    this.cancellationCutoffHours = 24,
    this.cancellationPolicyVersion,
    this.cancellationPolicyText,
    this.consentAt,
    this.rejectionReason,
    this.cancellationReason,
    this.minEnrollment = 0,
    this.confirmedCount = 0,
    this.autoConfirm = false,
    this.offeringStatus,
    this.sessions = const [],
    this.createdAt,
  });

  bool get isPending => status == CoachEnrollmentStatus.pending;
  bool get isConfirmed => status == CoachEnrollmentStatus.confirmed;
  bool get isCompleted => status == CoachEnrollmentStatus.completed;
  bool get isLive =>
      status == CoachEnrollmentStatus.pending ||
      status == CoachEnrollmentStatus.confirmed;

  /// Effective earliest start across live sessions — drives the
  /// learner-side cancellation cutoff check.
  DateTime? get firstLiveSessionStart {
    final live = sessions.where((s) => s.isLive);
    if (live.isEmpty) return null;
    return live
        .map((s) => s.startsAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// True when the learner may still cancel under the accepted policy.
  bool get canLearnerCancel {
    if (!isLive) return false;
    final first = firstLiveSessionStart;
    if (first == null) return true;
    return DateTime.now().isBefore(
      first.subtract(Duration(hours: cancellationCutoffHours)),
    );
  }

  factory CoachEnrollment.fromJson(Map<String, dynamic> j) =>
      CoachEnrollment(
        id: j['id']?.toString() ?? '',
        offeringId: j['offeringId']?.toString() ?? '',
        offeringTitle: j['offeringTitle']?.toString() ?? '',
        offeringType:
            coachOfferingTypeFrom(j['offeringType']?.toString()),
        coachId: j['coachId']?.toString() ?? '',
        coachName: j['coachName']?.toString() ?? '',
        learnerName: j['learnerName']?.toString(),
        userId: j['userId']?.toString(),
        scope: j['scope']?.toString() ?? 'sessions',
        status: coachEnrollmentStatusFrom(j['status']?.toString()),
        priceTotal: (j['priceTotal'] as num?)?.toDouble(),
        pricingUnit: j['pricingUnit'] == null
            ? null
            : coachPricingUnitFrom(j['pricingUnit']?.toString()),
        cancellationCutoffHours:
            (j['cancellationCutoffHours'] as num?)?.toInt() ?? 24,
        cancellationPolicyVersion:
            j['cancellationPolicyVersion']?.toString(),
        cancellationPolicyText:
            j['cancellationPolicyText']?.toString(),
        consentAt: DateTime.tryParse(j['consentAt']?.toString() ?? ''),
        rejectionReason: j['rejectionReason']?.toString(),
        cancellationReason: j['cancellationReason']?.toString(),
        minEnrollment: (j['minEnrollment'] as num?)?.toInt() ?? 0,
        confirmedCount: (j['confirmedCount'] as num?)?.toInt() ?? 0,
        autoConfirm: j['autoConfirm'] == true,
        offeringStatus: j['offeringStatus'] == null
            ? null
            : coachOfferingStatusFrom(
                j['offeringStatus']?.toString()),
        sessions: (j['sessions'] as List?)
                ?.map(
                  (e) => CoachEnrollmentSession.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList() ??
            const [],
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? ''),
      );
}

/// Coach review category catalog entry (1–10 anchored scale).
class CoachReviewCategory {
  final String id;
  final String key;
  final String labelTh;
  final String? labelEn;
  final Map<String, String> anchors;
  final int displayOrder;

  const CoachReviewCategory({
    required this.id,
    required this.key,
    required this.labelTh,
    this.labelEn,
    this.anchors = const {},
    this.displayOrder = 0,
  });

  /// Anchor text for a numeric score, e.g. "7-8" for score 7.
  String anchorFor(int score) {
    final band = switch (score) {
      <= 2 => '1-2',
      <= 4 => '3-4',
      <= 6 => '5-6',
      <= 8 => '7-8',
      _ => '9-10',
    };
    return anchors[band] ?? '';
  }

  factory CoachReviewCategory.fromJson(Map<String, dynamic> j) =>
      CoachReviewCategory(
        id: j['id']?.toString() ?? '',
        key: j['key']?.toString() ?? '',
        labelTh: j['label_th']?.toString() ?? '',
        labelEn: j['label_en']?.toString(),
        anchors: (j['anchors'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            const {},
        displayOrder: (j['display_order'] as num?)?.toInt() ?? 0,
      );
}

class CoachReviewTag {
  final String id;
  final String key;
  final String labelTh;
  final String? labelEn;

  const CoachReviewTag({
    required this.id,
    required this.key,
    required this.labelTh,
    this.labelEn,
  });

  factory CoachReviewTag.fromJson(Map<String, dynamic> j) =>
      CoachReviewTag(
        id: j['id']?.toString() ?? '',
        key: j['key']?.toString() ?? '',
        labelTh: j['label_th']?.toString() ?? '',
        labelEn: j['label_en']?.toString(),
      );
}

/// Review summary over the 1–10 model: band distribution, category
/// averages and topic (standard tag) counts.
class CoachReviewSummaryV2 {
  final double? averageRating;
  final int reviewCount;
  final Map<String, int> bandCounts;
  final List<CoachReviewCategoryStat> categories;
  final List<CoachReviewTopicStat> topics;

  const CoachReviewSummaryV2({
    this.averageRating,
    this.reviewCount = 0,
    this.bandCounts = const {},
    this.categories = const [],
    this.topics = const [],
  });

  factory CoachReviewSummaryV2.fromJson(Map<String, dynamic> j) =>
      CoachReviewSummaryV2(
        averageRating: (j['average_rating'] as num?)?.toDouble(),
        reviewCount: (j['review_count'] as num?)?.toInt() ?? 0,
        bandCounts: (j['band_counts'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            const {},
        categories: (j['categories'] as List?)
                ?.map(
                  (e) => CoachReviewCategoryStat.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList() ??
            const [],
        topics: (j['topics'] as List?)
                ?.map(
                  (e) => CoachReviewTopicStat.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList() ??
            const [],
      );
}

class CoachReviewCategoryStat {
  final String categoryId;
  final String key;
  final String labelTh;
  final double? average;
  final int sampleCount;

  const CoachReviewCategoryStat({
    required this.categoryId,
    required this.key,
    required this.labelTh,
    this.average,
    this.sampleCount = 0,
  });

  factory CoachReviewCategoryStat.fromJson(Map<String, dynamic> j) =>
      CoachReviewCategoryStat(
        categoryId: j['category_id']?.toString() ?? '',
        key: j['key']?.toString() ?? '',
        labelTh: j['label_th']?.toString() ?? '',
        average: (j['average'] as num?)?.toDouble(),
        sampleCount: (j['sample_count'] as num?)?.toInt() ?? 0,
      );
}

class CoachReviewTopicStat {
  final String tagId;
  final String labelTh;
  final int reviewCount;

  const CoachReviewTopicStat({
    required this.tagId,
    required this.labelTh,
    this.reviewCount = 0,
  });

  factory CoachReviewTopicStat.fromJson(Map<String, dynamic> j) =>
      CoachReviewTopicStat(
        tagId: j['tag_id']?.toString() ?? '',
        labelTh: j['label_th']?.toString() ?? '',
        reviewCount: (j['review_count'] as num?)?.toInt() ?? 0,
      );
}

/// One row of `coach_sports` — sport + skill levels + specialties.
class CoachSportRow {
  final String sportId;
  final List<String> skillLevels;
  final List<String> specialties;

  const CoachSportRow({
    required this.sportId,
    this.skillLevels = const [],
    this.specialties = const [],
  });

  factory CoachSportRow.fromJson(Map<String, dynamic> j) => CoachSportRow(
    sportId: j['sport_id']?.toString() ?? '',
    skillLevels:
        (j['skill_levels'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    specialties:
        (j['specialties'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
  );

  Map<String, dynamic> toJson() => {
    'sport_id': sportId,
    'skill_levels': skillLevels,
    'specialties': specialties,
  };
}

/// Completeness checklist for the submit-for-review gate.
class CoachProfileCompleteness {
  final String coachId;
  final CoachStatus status;
  final bool hasName;
  final bool hasBio;
  final bool hasExperience;
  final bool hasSport;
  final bool hasLocation;
  final bool hasPricing;
  final bool hasCredential;
  final bool hasContact;

  const CoachProfileCompleteness({
    required this.coachId,
    required this.status,
    this.hasName = false,
    this.hasBio = false,
    this.hasExperience = false,
    this.hasSport = false,
    this.hasLocation = false,
    this.hasPricing = false,
    this.hasCredential = false,
    this.hasContact = false,
  });

  bool get isComplete =>
      hasName &&
      hasBio &&
      hasExperience &&
      hasSport &&
      hasLocation &&
      hasPricing &&
      hasCredential &&
      hasContact;

  List<({String key, bool done})> get checks => [
    (key: 'ชื่อที่แสดง', done: hasName),
    (key: 'แนะนำตัว', done: hasBio),
    (key: 'ประสบการณ์', done: hasExperience),
    (key: 'กีฬาและระดับผู้เรียน', done: hasSport),
    (key: 'สถานที่สอน', done: hasLocation),
    (key: 'ราคา', done: hasPricing),
    (key: 'ใบรับรอง', done: hasCredential),
    (key: 'ช่องทางติดต่อ', done: hasContact),
  ];

  factory CoachProfileCompleteness.fromJson(Map<String, dynamic> j) =>
      CoachProfileCompleteness(
        coachId: j['coach_id']?.toString() ?? '',
        status: coachStatusFrom(j['status']?.toString()),
        hasName: j['has_name'] == true,
        hasBio: j['has_bio'] == true,
        hasExperience: j['has_experience'] == true,
        hasSport: j['has_sport'] == true,
        hasLocation: j['has_location'] == true,
        hasPricing: j['has_pricing'] == true,
        hasCredential: j['has_credential'] == true,
        hasContact: j['has_contact'] == true,
      );
}
