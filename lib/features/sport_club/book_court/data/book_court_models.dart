/// Typed models for the Book Court domain.
///
/// Mirrors the `sports_venue_*` schema and the public discovery views.
/// Snapshot fields on [VenueBooking] are immutable: edits to venue terms,
/// prices or unit labels never rewrite an existing booking.
library;

enum VenueStatus { draft, pending, approved, rejected, suspended }

enum VenueOwnerStatus { pending, approved, rejected, suspended }

enum BookingApprovalMode { instant, ownerApproval }

enum VenueBookingStatus {
  pending,
  confirmed,
  completed,
  cancelled,
  rejected,
  expired,
}

VenueStatus venueStatusFrom(String? raw) => switch (raw) {
  'draft' => VenueStatus.draft,
  'approved' => VenueStatus.approved,
  'rejected' => VenueStatus.rejected,
  'suspended' => VenueStatus.suspended,
  'pending' => VenueStatus.pending,
  _ => VenueStatus.draft,
};

VenueOwnerStatus venueOwnerStatusFrom(String? raw) => switch (raw) {
  'approved' => VenueOwnerStatus.approved,
  'rejected' => VenueOwnerStatus.rejected,
  'suspended' => VenueOwnerStatus.suspended,
  _ => VenueOwnerStatus.pending,
};

BookingApprovalMode bookingApprovalModeFrom(String? raw) =>
    raw == 'owner_approval'
    ? BookingApprovalMode.ownerApproval
    : BookingApprovalMode.instant;

VenueBookingStatus venueBookingStatusFrom(String? raw) => switch (raw) {
  'confirmed' => VenueBookingStatus.confirmed,
  'completed' => VenueBookingStatus.completed,
  'cancelled' => VenueBookingStatus.cancelled,
  'rejected' => VenueBookingStatus.rejected,
  'expired' => VenueBookingStatus.expired,
  _ => VenueBookingStatus.pending,
};

class VenueOwnerProfile {
  final String id;
  final String userId;
  final String businessName;
  final String contactName;
  final String contactPhone;
  final String? contactEmail;
  final VenueOwnerStatus status;
  final String? rejectionReason;
  final DateTime? createdAt;

  /// Timestamp of the latest application submission — unlike [createdAt],
  /// this refreshes when a rejected application is resubmitted.
  final DateTime? submittedAt;

  /// When an admin last decided on the application (approve/reject/suspend).
  final DateTime? reviewedAt;

  const VenueOwnerProfile({
    required this.id,
    required this.userId,
    required this.businessName,
    required this.contactName,
    required this.contactPhone,
    this.contactEmail,
    required this.status,
    this.rejectionReason,
    this.createdAt,
    this.submittedAt,
    this.reviewedAt,
  });

  factory VenueOwnerProfile.fromJson(Map<String, dynamic> j) =>
      VenueOwnerProfile(
        id: j['id']?.toString() ?? '',
        userId: j['user_id']?.toString() ?? '',
        businessName: j['business_name']?.toString() ?? '',
        contactName: j['contact_name']?.toString() ?? '',
        contactPhone: j['contact_phone']?.toString() ?? '',
        contactEmail: j['contact_email']?.toString(),
        status: venueOwnerStatusFrom(j['status']?.toString()),
        rejectionReason: j['rejection_reason']?.toString(),
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
        submittedAt: DateTime.tryParse(j['submitted_at']?.toString() ?? ''),
        reviewedAt: DateTime.tryParse(j['reviewed_at']?.toString() ?? ''),
      );
}

class VenueOwnerPublicProfile {
  final String? displayName;
  final String? avatarUrl;

  const VenueOwnerPublicProfile({this.displayName, this.avatarUrl});

  factory VenueOwnerPublicProfile.fromJson(Map<String, dynamic> json) =>
      VenueOwnerPublicProfile(
        displayName: json['display_name']?.toString(),
        avatarUrl: json['avatar_url']?.toString(),
      );

  bool get hasPublicInfo =>
      (displayName?.trim().isNotEmpty ?? false) ||
      (avatarUrl?.trim().isNotEmpty ?? false);
}

/// A venue as shown on public discovery surfaces (no owner contact data).
class VenueSummary {
  final String id;
  final String name;
  final String? description;
  final String? province;
  final String? district;
  final String? address;
  final double? lat;
  final double? lng;
  final String timezone;
  final VenueStatus? status;
  final int courtCount;
  final String? rejectionReason;
  final double? averageRating;
  final int reviewCount;
  final double? startingPriceAmount;
  final Set<String> amenityIds;
  final List<String> photoUrls;
  final Set<String> sportIds;

  /// Caller's management role on this venue ('owner' or 'manager'), as
  /// reported by `list_my_sports_venues`. Null on public surfaces.
  final String? memberRole;

  /// Resolved venue-level unit label (สนาม/ยิม/ฟิตเนส/ห้อง…) — Phase 21.7.19.
  /// Distinct from the resource labels of the courts inside the venue.
  /// Null when the surface does not return it.
  final String? venueUnitLabel;

  const VenueSummary({
    required this.id,
    required this.name,
    this.description,
    this.province,
    this.district,
    this.address,
    this.lat,
    this.lng,
    this.timezone = 'Asia/Bangkok',
    this.status,
    this.courtCount = 0,
    this.rejectionReason,
    this.averageRating,
    this.reviewCount = 0,
    this.startingPriceAmount,
    this.amenityIds = const {},
    this.photoUrls = const [],
    this.sportIds = const {},
    this.memberRole,
    this.venueUnitLabel,
  });

  factory VenueSummary.fromJson(Map<String, dynamic> j) => VenueSummary(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    description: j['description']?.toString(),
    province: j['province']?.toString(),
    district: j['district']?.toString(),
    address: j['address']?.toString(),
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
    timezone: j['timezone']?.toString() ?? 'Asia/Bangkok',
    status: j['status'] == null
        ? null
        : venueStatusFrom(j['status']?.toString()),
    courtCount: (j['court_count'] as num?)?.toInt() ?? 0,
    startingPriceAmount: (j['starting_price_amount'] as num?)?.toDouble(),
    rejectionReason: j['rejection_reason']?.toString(),
    memberRole: j['member_role']?.toString(),
    venueUnitLabel:
        j['venue_unit_label']?.toString() ?? j['venueUnitLabel']?.toString(),
  );

  VenueSummary copyWith({
    double? averageRating,
    int? reviewCount,
    double? startingPriceAmount,
    int? courtCount,
    Set<String>? amenityIds,
    List<String>? photoUrls,
    Set<String>? sportIds,
  }) => VenueSummary(
    id: id,
    name: name,
    description: description,
    province: province,
    district: district,
    address: address,
    lat: lat,
    lng: lng,
    timezone: timezone,
    status: status,
    courtCount: courtCount ?? this.courtCount,
    rejectionReason: rejectionReason,
    averageRating: averageRating ?? this.averageRating,
    reviewCount: reviewCount ?? this.reviewCount,
    startingPriceAmount: startingPriceAmount ?? this.startingPriceAmount,
    amenityIds: amenityIds ?? this.amenityIds,
    photoUrls: photoUrls ?? this.photoUrls,
    sportIds: sportIds ?? this.sportIds,
    memberRole: memberRole,
    venueUnitLabel: venueUnitLabel,
  );
}

/// A bookable resource inside a venue (court/field/room).
class VenueCourt {
  final String id;
  final String venueId;
  final String sportId;
  final String name;
  final int capacity;
  final double? priceAmount;
  final String pricingUnit;
  final double? startingPriceAmount;
  final bool hasTimePricing;
  final String? courtType;
  final bool? indoor;
  final BookingApprovalMode approvalMode;

  /// Effective resource-level unit label (คอร์ท/โต๊ะ/เลน…) resolved
  /// server-side — Phase 21.7.19.
  final String? unitLabel;

  /// Raw per-court override the owner typed; null means this court inherits
  /// the venue+sport resource default (then the sport catalog, then สนาม).
  final String? unitLabelOverride;
  final bool isActive;

  /// Explicit two-level name for [unitLabel] — the resource booked inside
  /// the venue (คอร์ท/โต๊ะ/เลน), never the venue-level label.
  String? get resourceUnitLabel => unitLabel;

  /// Court-level recurring booking release override (Phase 21.7.18).
  /// 'inherit' follows the venue rule, 'always_open' disables the gate
  /// for this court and 'custom' uses this court's selected days/time/window.
  final String bookingReleaseMode;
  final int? bookingReleaseDayOfWeek; // 0 = Sunday, legacy first-day alias
  final List<int> bookingReleaseDays; // 0 = Sunday
  final String? bookingReleaseTime; // 'HH:MM' venue-local
  final int? bookingReleaseWindowDays;

  /// Selected release weekdays, falling back to the legacy singleton field.
  List<int> get effectiveBookingReleaseDays {
    if (bookingReleaseDays.isNotEmpty) return bookingReleaseDays;
    final legacyDay = bookingReleaseDayOfWeek;
    return legacyDay == null ? const [] : [legacyDay];
  }

  const VenueCourt({
    required this.id,
    required this.venueId,
    required this.sportId,
    required this.name,
    this.capacity = 1,
    this.priceAmount,
    this.pricingUnit = 'hour',
    this.startingPriceAmount,
    this.hasTimePricing = false,
    this.courtType,
    this.indoor,
    this.approvalMode = BookingApprovalMode.instant,
    this.unitLabel,
    this.unitLabelOverride,
    this.isActive = true,
    this.bookingReleaseMode = 'inherit',
    this.bookingReleaseDayOfWeek,
    this.bookingReleaseDays = const [],
    this.bookingReleaseTime,
    this.bookingReleaseWindowDays,
  });

  factory VenueCourt.fromJson(Map<String, dynamic> j) {
    final legacyDay = (j['booking_release_day_of_week'] as num?)?.toInt();
    final parsedDays =
        (j['booking_release_days'] as List?)
            ?.whereType<num>()
            .map((day) => day.toInt())
            .toList() ??
        const <int>[];
    return VenueCourt(
      id: j['id']?.toString() ?? '',
      venueId: j['venue_id']?.toString() ?? '',
      sportId: j['sport_id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      capacity: (j['capacity'] as num?)?.toInt() ?? 1,
      priceAmount: (j['price_amount'] as num?)?.toDouble(),
      pricingUnit: j['pricing_unit']?.toString() ?? 'hour',
      startingPriceAmount: (j['starting_price_amount'] as num?)?.toDouble(),
      hasTimePricing: j['has_time_pricing'] == true,
      courtType: j['court_type']?.toString(),
      indoor: j['indoor'] as bool?,
      approvalMode: bookingApprovalModeFrom(
        j['booking_approval_mode']?.toString(),
      ),
      unitLabel: j['unit_label']?.toString(),
      unitLabelOverride: j['unit_label_override']?.toString(),
      isActive: j['is_active'] != false,
      bookingReleaseMode: j['booking_release_mode']?.toString() ?? 'inherit',
      bookingReleaseDayOfWeek: legacyDay,
      bookingReleaseDays: parsedDays.isNotEmpty
          ? parsedDays
          : legacyDay == null
          ? const []
          : [legacyDay],
      bookingReleaseTime: j['booking_release_time']?.toString(),
      bookingReleaseWindowDays: (j['booking_release_window_days'] as num?)
          ?.toInt(),
    );
  }
}

class VenueCourtPriceRule {
  final int? dayOfWeek;
  final String startTime;
  final String endTime;
  final double pricePerHour;

  const VenueCourtPriceRule({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.pricePerHour,
  });

  factory VenueCourtPriceRule.fromJson(Map<String, dynamic> json) =>
      VenueCourtPriceRule(
        dayOfWeek: (json['day_of_week'] as num?)?.toInt(),
        startTime: json['start_time']?.toString() ?? '00:00',
        endTime: json['end_time']?.toString() ?? '00:00',
        pricePerHour: (json['price_per_hour'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'day_of_week': dayOfWeek,
    'start_time': startTime,
    'end_time': endTime,
    'price_per_hour': pricePerHour,
  };
}

class VenueCourtPriceQuote {
  final double? totalAmount;
  final double? priceAmount;
  final String? pricingUnit;
  final int? priceScheduleVersion;
  final bool hasTimePricing;
  final String? errorCode;
  final List<Map<String, dynamic>> breakdown;

  const VenueCourtPriceQuote({
    this.totalAmount,
    this.priceAmount,
    this.pricingUnit,
    this.priceScheduleVersion,
    this.hasTimePricing = false,
    this.errorCode,
    this.breakdown = const [],
  });

  factory VenueCourtPriceQuote.fromJson(Map<String, dynamic> json) =>
      VenueCourtPriceQuote(
        totalAmount: (json['total_amount'] as num?)?.toDouble(),
        priceAmount: (json['price_amount'] as num?)?.toDouble(),
        pricingUnit: json['pricing_unit']?.toString(),
        priceScheduleVersion: (json['price_schedule_version'] as num?)?.toInt(),
        hasTimePricing: json['has_time_pricing'] == true,
        errorCode: json['price_error']?.toString(),
        breakdown:
            (json['breakdown'] as List?)
                ?.map((row) => Map<String, dynamic>.from(row as Map))
                .toList() ??
            const [],
      );
}

/// Venue operating window for one weekday, in venue-local time.
class VenueOperatingHours {
  final int dayOfWeek; // 0 = Sunday
  final String? openTime; // 'HH:MM'
  final String? closeTime;
  final bool isClosed;

  const VenueOperatingHours({
    required this.dayOfWeek,
    this.openTime,
    this.closeTime,
    this.isClosed = false,
  });

  factory VenueOperatingHours.fromJson(Map<String, dynamic> j) =>
      VenueOperatingHours(
        dayOfWeek: (j['day_of_week'] as num?)?.toInt() ?? 0,
        openTime: j['open_time']?.toString(),
        closeTime: j['close_time']?.toString(),
        isClosed: j['is_closed'] == true,
      );
}

class VenueTerms {
  final String id;
  final String venueId;
  final int version;
  final String termsText;
  final int cancellationCutoffMinutes;

  const VenueTerms({
    required this.id,
    required this.venueId,
    required this.version,
    required this.termsText,
    required this.cancellationCutoffMinutes,
  });

  /// Legacy defaults mirrored by the unconfigured platform-terms seed.
  static const int baseVersion = 0;
  static const int baseCutoffMinutes = 60;
  static const String baseTermsText = 'เงื่อนไขการใช้งานมาตรฐานของแพลตฟอร์ม';

  factory VenueTerms.fromJson(Map<String, dynamic> j) => VenueTerms(
    id: j['id']?.toString() ?? '',
    venueId: j['venue_id']?.toString() ?? '',
    version: (j['version'] as num?)?.toInt() ?? 0,
    termsText: j['terms_text']?.toString() ?? '',
    cancellationCutoffMinutes:
        (j['cancellation_cutoff_minutes'] as num?)?.toInt() ?? 60,
  );
}

class PlatformVenueTerms {
  final int version;
  final String termsText;
  final int cancellationCutoffMinutes;
  final bool isConfigured;
  final DateTime? updatedAt;

  const PlatformVenueTerms({
    required this.version,
    required this.termsText,
    required this.cancellationCutoffMinutes,
    required this.isConfigured,
    this.updatedAt,
  });

  factory PlatformVenueTerms.fromJson(Map<String, dynamic> json) =>
      PlatformVenueTerms(
        version: (json['version'] as num?)?.toInt() ?? 0,
        termsText: json['terms_text']?.toString() ?? '',
        cancellationCutoffMinutes:
            (json['cancellation_cutoff_minutes'] as num?)?.toInt() ?? 60,
        isConfigured: json['is_configured'] == true,
        updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      );
}

class VenueBooking {
  final String id;
  final String courtId;
  final String venueId;
  final String sportId;
  final DateTime startsAt;
  final DateTime endsAt;
  final VenueBookingStatus status;
  final String? venueName;
  final String timezone;
  final String? courtName;
  final String? unitLabel;

  /// Venue-level unit label snapshotted at booking creation — Phase 21.7.19.
  /// Null for bookings created before the migration; render the neutral
  /// term สถานที่ for those rows.
  final String? venueUnitLabel;

  /// Explicit two-level name for [unitLabel] — the resource-level snapshot
  /// (คอร์ท/โต๊ะ/เลน) kept immutable on this booking.
  String? get resourceUnitLabel => unitLabel;
  final double? priceAmount;
  final String? pricingUnit;
  final double? priceTotal;
  final List<Map<String, dynamic>> priceBreakdown;
  final int? priceScheduleVersion;
  final BookingApprovalMode approvalMode;
  final int termsVersion;
  final int cancellationCutoffMinutes;
  final String? rejectionReason;
  final String? cancellationReason;
  final String? bookerName;
  final DateTime? createdAt;

  /// When the owner approved/rejected — drives "ถูกปฏิเสธล่าสุดก่อน" ordering
  /// on the booker's my-bookings page. Null for undecided or legacy rows.
  final DateTime? decidedAt;

  const VenueBooking({
    required this.id,
    required this.courtId,
    required this.venueId,
    required this.sportId,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.venueName,
    this.timezone = 'Asia/Bangkok',
    this.courtName,
    this.unitLabel,
    this.venueUnitLabel,
    this.priceAmount,
    this.pricingUnit,
    this.priceTotal,
    this.priceBreakdown = const [],
    this.priceScheduleVersion,
    this.approvalMode = BookingApprovalMode.instant,
    this.termsVersion = 0,
    this.cancellationCutoffMinutes = 60,
    this.rejectionReason,
    this.cancellationReason,
    this.bookerName,
    this.createdAt,
    this.decidedAt,
  });

  bool get isPending => status == VenueBookingStatus.pending;
  bool get isConfirmed => status == VenueBookingStatus.confirmed;
  bool get isCompleted => status == VenueBookingStatus.completed;

  /// Booker cancellation deadline from the snapshot in this booking.
  DateTime get cancellationCutoffAt =>
      startsAt.subtract(Duration(minutes: cancellationCutoffMinutes));

  bool get cancellableByBooker =>
      (isPending || isConfirmed) &&
      DateTime.now().isBefore(cancellationCutoffAt);

  factory VenueBooking.fromJson(Map<String, dynamic> j) => VenueBooking(
    id: j['id']?.toString() ?? '',
    courtId: j['courtId']?.toString() ?? j['court_id']?.toString() ?? '',
    venueId: j['venueId']?.toString() ?? j['venue_id']?.toString() ?? '',
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
    status: venueBookingStatusFrom(j['status']?.toString()),
    venueName: j['venueName']?.toString() ?? j['venue_name']?.toString(),
    timezone:
        j['timezone']?.toString() ??
        j['venue_timezone']?.toString() ??
        'Asia/Bangkok',
    courtName: j['courtName']?.toString() ?? j['court_name']?.toString(),
    unitLabel: j['unitLabel']?.toString() ?? j['unit_label']?.toString(),
    venueUnitLabel:
        j['venueUnitLabel']?.toString() ??
        j['venue_unit_label_snapshot']?.toString(),
    priceAmount:
        (j['priceAmount'] as num?)?.toDouble() ??
        (j['price_amount'] as num?)?.toDouble(),
    pricingUnit: j['pricingUnit']?.toString() ?? j['pricing_unit']?.toString(),
    priceTotal:
        (j['priceTotal'] as num?)?.toDouble() ??
        (j['price_total_snapshot'] as num?)?.toDouble(),
    priceBreakdown:
        ((j['priceBreakdown'] ?? j['price_breakdown_snapshot']) as List?)
            ?.map((row) => Map<String, dynamic>.from(row as Map))
            .toList() ??
        const [],
    priceScheduleVersion:
        (j['priceScheduleVersion'] as num?)?.toInt() ??
        (j['price_schedule_version_snapshot'] as num?)?.toInt(),
    approvalMode: bookingApprovalModeFrom(
      j['approvalMode']?.toString() ?? j['booking_approval_mode']?.toString(),
    ),
    termsVersion:
        (j['termsVersion'] as num?)?.toInt() ??
        (j['accepted_terms_version'] as num?)?.toInt() ??
        0,
    cancellationCutoffMinutes:
        (j['cancellationCutoffMinutes'] as num?)?.toInt() ??
        (j['cancellation_cutoff_minutes_snapshot'] as num?)?.toInt() ??
        60,
    rejectionReason: j['rejectionReason']?.toString(),
    cancellationReason: j['cancellationReason']?.toString(),
    bookerName: j['bookerName']?.toString(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? ''),
    decidedAt: DateTime.tryParse(
      j['decidedAt']?.toString() ?? j['decided_at']?.toString() ?? '',
    ),
  );
}

class VenueReview {
  final String id;
  final String venueId;
  final String? courtId;
  final String bookingId;
  final String userId;
  final String? userDisplayName;
  final String? userAvatarUrl;
  final int rating;
  final int rating10;
  final String? comment;
  final DateTime? createdAt;
  final String? courtName;
  final String? sportName;
  final List<String> tagLabels;
  final int helpfulCount;
  final bool viewerVoted;

  const VenueReview({
    required this.id,
    required this.venueId,
    this.courtId,
    required this.bookingId,
    required this.userId,
    this.userDisplayName,
    this.userAvatarUrl,
    required this.rating,
    int? rating10,
    this.comment,
    this.createdAt,
    this.courtName,
    this.sportName,
    this.tagLabels = const [],
    this.helpfulCount = 0,
    this.viewerVoted = false,
  }) : rating10 = rating10 ?? rating * 2;

  factory VenueReview.fromJson(Map<String, dynamic> j) {
    final rating = (j['rating'] as num?)?.toInt() ?? 0;
    return VenueReview(
      id: j['id']?.toString() ?? '',
      venueId: j['venue_id']?.toString() ?? '',
      courtId: j['court_id']?.toString(),
      bookingId: j['booking_id']?.toString() ?? '',
      userId: j['user_id']?.toString() ?? '',
      userDisplayName: j['user_display_name']?.toString(),
      userAvatarUrl: j['user_avatar_url']?.toString(),
      rating: rating,
      rating10: (j['rating_10'] as num?)?.toInt(),
      comment: j['comment']?.toString(),
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
      courtName: j['court_name']?.toString(),
      sportName: j['sport_name']?.toString(),
      tagLabels:
          (j['tag_labels'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      helpfulCount: (j['helpful_count'] as num?)?.toInt() ?? 0,
      viewerVoted: j['viewer_voted'] == true,
    );
  }

  VenueReview copyWith({int? helpfulCount, bool? viewerVoted}) => VenueReview(
    id: id,
    venueId: venueId,
    courtId: courtId,
    bookingId: bookingId,
    userId: userId,
    userDisplayName: userDisplayName,
    userAvatarUrl: userAvatarUrl,
    rating: rating,
    rating10: rating10,
    comment: comment,
    createdAt: createdAt,
    courtName: courtName,
    sportName: sportName,
    tagLabels: tagLabels,
    helpfulCount: helpfulCount ?? this.helpfulCount,
    viewerVoted: viewerVoted ?? this.viewerVoted,
  );
}

class VenueReviewTag {
  final String id;
  final String labelTh;
  final String? labelEn;
  final int displayOrder;

  const VenueReviewTag({
    required this.id,
    required this.labelTh,
    this.labelEn,
    this.displayOrder = 0,
  });

  factory VenueReviewTag.fromJson(Map<String, dynamic> j) => VenueReviewTag(
    id: j['id']?.toString() ?? '',
    labelTh: j['label_th']?.toString() ?? '',
    labelEn: j['label_en']?.toString(),
    displayOrder: (j['display_order'] as num?)?.toInt() ?? 0,
  );
}

/// A review category the reviewer must score (1–10 each), from the
/// `sports_venue_review_category_catalog` table.
class VenueReviewCategory {
  final String id;
  final String key;
  final String labelTh;
  final String? labelEn;
  final int displayOrder;

  const VenueReviewCategory({
    required this.id,
    required this.key,
    required this.labelTh,
    this.labelEn,
    this.displayOrder = 0,
  });

  factory VenueReviewCategory.fromJson(Map<String, dynamic> j) =>
      VenueReviewCategory(
        id: j['id']?.toString() ?? '',
        key: j['key']?.toString() ?? '',
        labelTh: j['label_th']?.toString() ?? '',
        labelEn: j['label_en']?.toString(),
        displayOrder: (j['display_order'] as num?)?.toInt() ?? 0,
      );
}

/// Per-category aggregate shown on the reviews page. [average] is null
/// until at least one published review carries real category scores —
/// legacy reviews never get synthetic category values.
class VenueReviewCategoryScore {
  final String categoryId;
  final String key;
  final String labelTh;
  final double? average;
  final int sampleCount;

  const VenueReviewCategoryScore({
    required this.categoryId,
    required this.key,
    required this.labelTh,
    this.average,
    this.sampleCount = 0,
  });

  factory VenueReviewCategoryScore.fromJson(Map<String, dynamic> j) =>
      VenueReviewCategoryScore(
        categoryId: j['category_id']?.toString() ?? '',
        key: j['key']?.toString() ?? '',
        labelTh: j['label_th']?.toString() ?? '',
        average: (j['average'] as num?)?.toDouble(),
        sampleCount: (j['sample_count'] as num?)?.toInt() ?? 0,
      );
}

/// Popular standard-tag topic with its published review count.
class VenueReviewTopic {
  final String tagId;
  final String labelTh;
  final String? labelEn;
  final int reviewCount;

  const VenueReviewTopic({
    required this.tagId,
    required this.labelTh,
    this.labelEn,
    required this.reviewCount,
  });

  factory VenueReviewTopic.fromJson(Map<String, dynamic> j) => VenueReviewTopic(
    tagId: j['tag_id']?.toString() ?? '',
    labelTh: j['label_th']?.toString() ?? '',
    labelEn: j['label_en']?.toString(),
    reviewCount: (j['review_count'] as num?)?.toInt() ?? 0,
  );
}

/// Deterministic 10-point rating bands used by the review page's score
/// bars and rating filter. Boundaries are shared by display, filter and
/// aggregates — they must never diverge.
enum VenueReviewBand {
  excellent('excellent', 9, 10, 'ดีเลิศ'),
  good('good', 7, 8, 'ดี'),
  fair('fair', 5, 6, 'พอใช้ได้'),
  poor('poor', 3, 4, 'แย่'),
  veryPoor('very_poor', 1, 2, 'แย่มาก');

  const VenueReviewBand(this.wireKey, this.min, this.max, this.labelTh);

  final String wireKey;
  final int min;
  final int max;
  final String labelTh;

  /// e.g. `ดีเลิศ: 9.0–10`, `ดี: 7.0–8.9`
  String get label {
    final hi = max >= 10 ? '10' : '$max.9';
    return '$labelTh: $min.0–$hi';
  }
}

/// Aggregated review summary for one venue (or one court) — published
/// reviews only.
class VenueReviewSummary {
  final double? averageRating;
  final int reviewCount;
  final Map<VenueReviewBand, int> bandCounts;
  final List<VenueReviewCategoryScore> categories;
  final List<VenueReviewTopic> topics;

  const VenueReviewSummary({
    this.averageRating,
    this.reviewCount = 0,
    this.bandCounts = const {},
    this.categories = const [],
    this.topics = const [],
  });

  int bandCount(VenueReviewBand band) => bandCounts[band] ?? 0;

  factory VenueReviewSummary.fromJson(Map<String, dynamic> j) {
    final bands = <VenueReviewBand, int>{};
    final rawBands = j['band_counts'];
    if (rawBands is Map) {
      for (final band in VenueReviewBand.values) {
        bands[band] = (rawBands[band.wireKey] as num?)?.toInt() ?? 0;
      }
    }
    return VenueReviewSummary(
      averageRating: (j['average_rating'] as num?)?.toDouble(),
      reviewCount: (j['review_count'] as num?)?.toInt() ?? 0,
      bandCounts: bands,
      categories:
          (j['categories'] as List?)
              ?.map(
                (e) => VenueReviewCategoryScore.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          const [],
      topics:
          (j['topics'] as List?)
              ?.map(
                (e) => VenueReviewTopic.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          const [],
    );
  }
}

/// Sort order for the full review list (server-side).
enum VenueReviewSort {
  helpful('helpful', 'มีประโยชน์ที่สุดก่อน'),
  newest('newest', 'ใหม่ล่าสุด'),
  highest('highest', 'คะแนนสูงสุด'),
  lowest('lowest', 'คะแนนต่ำสุด');

  const VenueReviewSort(this.wireValue, this.labelTh);

  final String wireValue;
  final String labelTh;
}

/// One page of the filtered review list plus the server-side total.
class VenueReviewListPage {
  final List<VenueReview> reviews;
  final int totalCount;
  final int nextOffset;
  final bool hasMore;

  const VenueReviewListPage({
    required this.reviews,
    required this.totalCount,
    required this.nextOffset,
    required this.hasMore,
  });
}

/// Effective recurring booking release rule echoed by
/// `get_court_availability` (Phase 21.7.18). Null when the court has no
/// effective rule, i.e. advance booking is unlimited.
class CourtBookingRelease {
  /// 'inherit' (venue rule applies) or 'custom' (court override).
  final String mode;
  final int dayOfWeek; // 0 = Sunday, legacy first-day alias
  final List<int> daysOfWeek;
  final String releaseTime; // 'HH:MM' venue-local
  final int windowDays;
  final String? selectedDayReleaseTime;

  const CourtBookingRelease({
    required this.mode,
    required this.dayOfWeek,
    this.daysOfWeek = const [],
    required this.releaseTime,
    required this.windowDays,
    this.selectedDayReleaseTime,
  });

  /// Selected weekdays, falling back to the legacy one-day response alias.
  List<int> get effectiveDaysOfWeek =>
      daysOfWeek.isNotEmpty ? daysOfWeek : [dayOfWeek];

  factory CourtBookingRelease.fromJson(Map<String, dynamic> j) {
    final legacyDay = (j['dayOfWeek'] as num?)?.toInt() ?? 0;
    final parsedDays =
        (j['daysOfWeek'] as List?)
            ?.whereType<num>()
            .map((day) => day.toInt())
            .toList() ??
        const <int>[];
    return CourtBookingRelease(
      mode: j['mode']?.toString() ?? 'inherit',
      dayOfWeek: legacyDay,
      daysOfWeek: parsedDays.isNotEmpty ? parsedDays : [legacyDay],
      releaseTime: j['releaseTime']?.toString() ?? '00:00',
      windowDays: (j['windowDays'] as num?)?.toInt() ?? 7,
      selectedDayReleaseTime: j['selectedDayReleaseTime']?.toString(),
    );
  }
}

/// Busy ranges for the read-only availability view of one court.
class CourtAvailability {
  final String courtId;
  final List<({DateTime startsAt, DateTime endsAt})> booked;
  final List<({DateTime startsAt, DateTime endsAt})> blocked;
  final List<VenueOperatingHours> hours;

  /// Server clock at response time — slot state decisions use this
  /// instead of the device clock so a skewed client cannot book early
  /// or hide released slots.
  final DateTime? serverNow;

  final DateTime? nextReleaseAt;

  /// Slots whose recurring release has not happened yet. Each entry
  /// carries the exact `opensAt` instant the slot becomes bookable.
  final List<({DateTime slotStart, DateTime opensAt})> notOpen;

  /// The effective release rule for this court, when one exists.
  final CourtBookingRelease? release;

  const CourtAvailability({
    required this.courtId,
    this.booked = const [],
    this.blocked = const [],
    this.hours = const [],
    this.serverNow,
    this.nextReleaseAt,
    this.notOpen = const [],
    this.release,
  });

  /// opensAt lookup keyed by the slot-start instant; microseconds avoid
  /// DateTime identity issues between TZDateTime and parsed DateTimes.
  Map<int, DateTime> get opensAtBySlotStart => {
    for (final e in notOpen)
      e.slotStart.toUtc().microsecondsSinceEpoch: e.opensAt,
  };

  DateTime? opensAtFor(DateTime slotStart) =>
      opensAtBySlotStart[slotStart.toUtc().microsecondsSinceEpoch];

  factory CourtAvailability.fromJson(Map<String, dynamic> j) {
    List<({DateTime startsAt, DateTime endsAt})> ranges(Object? raw) =>
        (raw as List?)
            ?.map(
              (e) => (
                startsAt:
                    DateTime.tryParse(
                      (e as Map)['startsAt']?.toString() ?? '',
                    ) ??
                    DateTime.fromMillisecondsSinceEpoch(0),
                endsAt:
                    DateTime.tryParse(e['endsAt']?.toString() ?? '') ??
                    DateTime.fromMillisecondsSinceEpoch(0),
              ),
            )
            .toList() ??
        const [];
    return CourtAvailability(
      courtId: j['courtId']?.toString() ?? '',
      booked: ranges(j['booked']),
      blocked: ranges(j['blocked']),
      hours:
          (j['hours'] as List?)
              ?.map(
                (e) => VenueOperatingHours(
                  dayOfWeek: ((e as Map)['day'] as num?)?.toInt() ?? 0,
                  openTime: e['open']?.toString(),
                  closeTime: e['close']?.toString(),
                  isClosed: e['closed'] == true,
                ),
              )
              .toList() ??
          const [],
      serverNow: DateTime.tryParse(j['serverNow']?.toString() ?? ''),
      nextReleaseAt: DateTime.tryParse(j['nextReleaseAt']?.toString() ?? ''),
      notOpen:
          (j['notOpen'] as List?)
              ?.map(
                (e) => (
                  slotStart:
                      DateTime.tryParse(
                        (e as Map)['slotStart']?.toString() ?? '',
                      ) ??
                      DateTime.fromMillisecondsSinceEpoch(0),
                  opensAt:
                      DateTime.tryParse(e['opensAt']?.toString() ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0),
                ),
              )
              .toList() ??
          const [],
      release: j['release'] is Map
          ? CourtBookingRelease.fromJson(
              Map<String, dynamic>.from(j['release'] as Map),
            )
          : null,
    );
  }
}
