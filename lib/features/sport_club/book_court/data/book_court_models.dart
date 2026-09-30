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
      );
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
  final Set<String> amenityIds;
  final List<String> photoUrls;
  final Set<String> sportIds;

  /// Caller's management role on this venue ('owner' or 'manager'), as
  /// reported by `list_my_sports_venues`. Null on public surfaces.
  final String? memberRole;

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
    this.amenityIds = const {},
    this.photoUrls = const [],
    this.sportIds = const {},
    this.memberRole,
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
    rejectionReason: j['rejection_reason']?.toString(),
    memberRole: j['member_role']?.toString(),
  );

  VenueSummary copyWith({
    double? averageRating,
    int? reviewCount,
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
    amenityIds: amenityIds ?? this.amenityIds,
    photoUrls: photoUrls ?? this.photoUrls,
    sportIds: sportIds ?? this.sportIds,
    memberRole: memberRole,
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
  final String? courtType;
  final bool? indoor;
  final BookingApprovalMode approvalMode;
  final String? unitLabel;
  final bool isActive;

  const VenueCourt({
    required this.id,
    required this.venueId,
    required this.sportId,
    required this.name,
    this.capacity = 1,
    this.priceAmount,
    this.pricingUnit = 'hour',
    this.courtType,
    this.indoor,
    this.approvalMode = BookingApprovalMode.instant,
    this.unitLabel,
    this.isActive = true,
  });

  factory VenueCourt.fromJson(Map<String, dynamic> j) => VenueCourt(
    id: j['id']?.toString() ?? '',
    venueId: j['venue_id']?.toString() ?? '',
    sportId: j['sport_id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    capacity: (j['capacity'] as num?)?.toInt() ?? 1,
    priceAmount: (j['price_amount'] as num?)?.toDouble(),
    pricingUnit: j['pricing_unit']?.toString() ?? 'hour',
    courtType: j['court_type']?.toString(),
    indoor: j['indoor'] as bool?,
    approvalMode: bookingApprovalModeFrom(
      j['booking_approval_mode']?.toString(),
    ),
    unitLabel: j['unit_label']?.toString(),
    isActive: j['is_active'] != false,
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
  static const String baseTermsText = 'เงื่อนไขการใช้สนามมาตรฐานของแพลตฟอร์ม';

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
  final String? courtName;
  final String? unitLabel;
  final double? priceAmount;
  final String? pricingUnit;
  final BookingApprovalMode approvalMode;
  final int termsVersion;
  final int cancellationCutoffMinutes;
  final String? rejectionReason;
  final String? cancellationReason;
  final String? bookerName;
  final DateTime? createdAt;

  const VenueBooking({
    required this.id,
    required this.courtId,
    required this.venueId,
    required this.sportId,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.venueName,
    this.courtName,
    this.unitLabel,
    this.priceAmount,
    this.pricingUnit,
    this.approvalMode = BookingApprovalMode.instant,
    this.termsVersion = 0,
    this.cancellationCutoffMinutes = 60,
    this.rejectionReason,
    this.cancellationReason,
    this.bookerName,
    this.createdAt,
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
    courtName: j['courtName']?.toString() ?? j['court_name']?.toString(),
    unitLabel: j['unitLabel']?.toString() ?? j['unit_label']?.toString(),
    priceAmount:
        (j['priceAmount'] as num?)?.toDouble() ??
        (j['price_amount'] as num?)?.toDouble(),
    pricingUnit: j['pricingUnit']?.toString() ?? j['pricing_unit']?.toString(),
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
          (j['tag_labels'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      helpfulCount: (j['helpful_count'] as num?)?.toInt() ?? 0,
      viewerVoted: j['viewer_voted'] == true,
    );
  }

  VenueReview copyWith({
    int? helpfulCount,
    bool? viewerVoted,
  }) => VenueReview(
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

  factory VenueReviewTopic.fromJson(Map<String, dynamic> j) =>
      VenueReviewTopic(
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
        bands[band] =
            (rawBands[band.wireKey] as num?)?.toInt() ?? 0;
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

/// Busy ranges for the read-only availability view of one court.
class CourtAvailability {
  final String courtId;
  final List<({DateTime startsAt, DateTime endsAt})> booked;
  final List<({DateTime startsAt, DateTime endsAt})> blocked;
  final List<VenueOperatingHours> hours;

  const CourtAvailability({
    required this.courtId,
    this.booked = const [],
    this.blocked = const [],
    this.hours = const [],
  });

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
    );
  }
}
