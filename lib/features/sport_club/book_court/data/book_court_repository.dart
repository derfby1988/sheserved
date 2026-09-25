import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sheserved/services/auth_service.dart';
import 'book_court_models.dart';

/// Supabase data access for the Book Court domain.
///
/// Public reads go through the `*_public` views (approved venues only).
/// Every mutation goes through a SECURITY DEFINER RPC with an explicit
/// actor id, matching the repository's custom-auth convention — the client
/// never writes booking or supply tables directly.
class BookCourtRepository {
  final SupabaseClient _client;
  BookCourtRepository(this._client);

  void _assertCurrentUser(String actorUserId) {
    final currentUserId = AuthService.instance.currentUser?.id;
    if (currentUserId == null || currentUserId != actorUserId) {
      throw StateError('UNAUTHORIZED');
    }
  }

  // =============== Public discovery ===============

  /// Approved venues visible publicly. Filtering that needs personal data
  /// (bookedByMe/ownerOnly) is applied by the caller with the user's own
  /// authorized lists.
  Future<List<VenueSummary>> listPublicVenues({
    String? sportId,
    String? province,
    String? district,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    var q = _client.from('sports_venues_public').select();
    if (province != null && province.isNotEmpty) {
      q = q.eq('province', province);
    }
    if (district != null && district.isNotEmpty) {
      q = q.eq('district', district);
    }
    if (query != null && query.trim().isNotEmpty) {
      q = q.ilike('name', '%${query.trim()}%');
    }
    final res = await q
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    var venues = (res as List)
        .map((e) => VenueSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    if (sportId != null && sportId.isNotEmpty) {
      final venueIds = venues.map((v) => v.id).toList();
      if (venueIds.isEmpty) return venues;
      final sportRows = await _client
          .from('sports_venue_sports_public')
          .select('venue_id, sport_id')
          .inFilter('venue_id', venueIds);
      final sportVenueIds = <String>{};
      final sportIdsByVenue = <String, Set<String>>{};
      for (final row in (sportRows as List)) {
        final m = Map<String, dynamic>.from(row);
        final vid = m['venue_id']?.toString() ?? '';
        final sid = m['sport_id']?.toString() ?? '';
        if (sid == sportId) sportVenueIds.add(vid);
        sportIdsByVenue.putIfAbsent(vid, () => {}).add(sid);
      }
      venues = venues
          .where((v) => sportVenueIds.contains(v.id))
          .map((v) => v.copyWith(sportIds: sportIdsByVenue[v.id] ?? const {}))
          .toList();
    }
    return venues;
  }

  /// Hydrates ratings/amenities/photos/court counts for venue cards.
  Future<List<VenueSummary>> hydrateVenueCards(
    List<VenueSummary> venues,
  ) async {
    final ids = venues.map((v) => v.id).toList();
    if (ids.isEmpty) return venues;

    final results = await Future.wait([
      _client
          .from('sports_venue_review_summary')
          .select()
          .inFilter('venue_id', ids),
      _client
          .from('sports_venue_amenities_public')
          .select('venue_id, amenity_key')
          .inFilter('venue_id', ids),
      _client
          .from('sports_venue_photos_public')
          .select('venue_id, url')
          .inFilter('venue_id', ids)
          .order('sort_order'),
      _client
          .from('sports_venue_courts_public')
          .select('venue_id')
          .inFilter('venue_id', ids),
      _client
          .from('sports_venue_sports_public')
          .select('venue_id, sport_id')
          .inFilter('venue_id', ids),
    ]);

    final ratingByVenue = <String, (double, int)>{};
    for (final row in (results[0] as List)) {
      final m = Map<String, dynamic>.from(row);
      ratingByVenue[m['venue_id']?.toString() ?? ''] = (
        (m['average_rating'] as num?)?.toDouble() ?? 0,
        (m['review_count'] as num?)?.toInt() ?? 0,
      );
    }
    final amenitiesByVenue = <String, Set<String>>{};
    for (final row in (results[1] as List)) {
      final m = Map<String, dynamic>.from(row);
      amenitiesByVenue
          .putIfAbsent(m['venue_id']?.toString() ?? '', () => {})
          .add(m['amenity_key']?.toString() ?? '');
    }
    final photosByVenue = <String, List<String>>{};
    for (final row in (results[2] as List)) {
      final m = Map<String, dynamic>.from(row);
      photosByVenue
          .putIfAbsent(m['venue_id']?.toString() ?? '', () => [])
          .add(m['url']?.toString() ?? '');
    }
    final courtCountByVenue = <String, int>{};
    for (final row in (results[3] as List)) {
      final m = Map<String, dynamic>.from(row);
      final vid = m['venue_id']?.toString() ?? '';
      courtCountByVenue[vid] = (courtCountByVenue[vid] ?? 0) + 1;
    }
    final sportsByVenue = <String, Set<String>>{};
    for (final row in (results[4] as List)) {
      final m = Map<String, dynamic>.from(row);
      sportsByVenue
          .putIfAbsent(m['venue_id']?.toString() ?? '', () => {})
          .add(m['sport_id']?.toString() ?? '');
    }

    return venues
        .map(
          (v) => v.copyWith(
            averageRating: ratingByVenue[v.id]?.$1,
            reviewCount: ratingByVenue[v.id]?.$2 ?? 0,
            courtCount: courtCountByVenue[v.id] ?? 0,
            amenityIds: amenitiesByVenue[v.id] ?? const {},
            photoUrls: photosByVenue[v.id] ?? const [],
            sportIds: sportsByVenue[v.id] ?? v.sportIds,
          ),
        )
        .toList();
  }

  Future<List<VenueCourt>> listPublicCourts(
    String venueId, {
    String? sportId,
  }) async {
    var q = _client
        .from('sports_venue_courts_public')
        .select()
        .eq('venue_id', venueId);
    if (sportId != null && sportId.isNotEmpty) {
      q = q.eq('sport_id', sportId);
    }
    final res = await q.order('name');
    return (res as List)
        .map((e) => VenueCourt.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<VenueOperatingHours>> listPublicOperatingHours(
    String venueId,
  ) async {
    final res = await _client
        .from('sports_venue_operating_hours_public')
        .select()
        .eq('venue_id', venueId)
        .order('day_of_week');
    return (res as List)
        .map((e) => VenueOperatingHours.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<VenueTerms?> getActiveVenueTerms(String venueId) async {
    final res = await _client
        .from('sports_venue_terms_public')
        .select()
        .eq('venue_id', venueId)
        .maybeSingle();
    if (res == null) return null;
    return VenueTerms.fromJson(Map<String, dynamic>.from(res));
  }

  Future<CourtAvailability> getCourtAvailability(
    String courtId,
    DateTime from,
    DateTime to,
  ) async {
    final res = await _client.rpc(
      'get_court_availability',
      params: {
        'p_court_id': courtId,
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      },
    );
    if (res is Map) {
      return CourtAvailability.fromJson(Map<String, dynamic>.from(res));
    }
    return CourtAvailability(courtId: courtId);
  }

  Future<List<VenueReview>> listVenueReviews(
    String venueId, {
    int limit = 50,
  }) async {
    final res = await _client
        .from('sports_venue_reviews_public')
        .select()
        .eq('venue_id', venueId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (res as List)
        .map((e) => VenueReview.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<VenueReviewTag>> listReviewTagCatalog() async {
    final res = await _client.rpc('list_sports_venue_review_tags');
    return (res as List)
        .map((e) => VenueReviewTag.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Set<String>> listMyReviewedBookingIds(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_sports_venue_review_booking_ids',
      params: {'p_user_id': userId},
    );
    return (res as List).map((e) => e.toString()).toSet();
  }

  // =============== Owner onboarding / admin ===============

  Future<String> submitOwnerApplication({
    required String userId,
    required String businessName,
    required String contactName,
    String? contactPhone,
    String? contactEmail,
    List<Map<String, dynamic>> evidence = const [],
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'submit_sports_venue_owner_application',
      params: {
        'p_user_id': userId,
        'p_business_name': businessName,
        'p_contact_name': contactName,
        'p_contact_phone': contactPhone,
        'p_contact_email': contactEmail,
        'p_evidence': evidence,
      },
    );
    return res.toString();
  }

  Future<VenueOwnerProfile?> getMyOwnerProfile(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'get_my_sports_venue_owner_profile',
      params: {'p_user_id': userId},
    );
    final list = res as List;
    if (list.isEmpty) return null;
    return VenueOwnerProfile.fromJson(Map<String, dynamic>.from(list.first));
  }

  Future<List<VenueOwnerProfile>> listOwnerApplications(
    String adminId, {
    String status = 'pending',
  }) async {
    _assertCurrentUser(adminId);
    final res = await _client.rpc(
      'list_sports_venue_owner_applications',
      params: {'p_admin_id': adminId, 'p_status': status},
    );
    return (res as List)
        .map((e) => VenueOwnerProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> reviewOwnerApplication(
    String adminId,
    String ownerProfileId,
    String decision, {
    String? reason,
  }) async {
    _assertCurrentUser(adminId);
    await _client.rpc(
      'review_sports_venue_owner_application',
      params: {
        'p_admin_id': adminId,
        'p_owner_profile_id': ownerProfileId,
        'p_decision': decision,
        'p_reason': reason,
      },
    );
  }

  Future<List<VenueSummary>> listVenuesForReview(
    String adminId, {
    String status = 'pending',
  }) async {
    _assertCurrentUser(adminId);
    final res = await _client.rpc(
      'list_sports_venues_for_review',
      params: {'p_admin_id': adminId, 'p_status': status},
    );
    return (res as List)
        .map((e) => VenueSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> reviewVenue(
    String adminId,
    String venueId,
    String decision, {
    String? reason,
  }) async {
    _assertCurrentUser(adminId);
    await _client.rpc(
      'review_sports_venue',
      params: {
        'p_admin_id': adminId,
        'p_venue_id': venueId,
        'p_decision': decision,
        'p_reason': reason,
      },
    );
  }

  // =============== Owner venue management ===============

  Future<List<VenueSummary>> listMyVenues(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_sports_venues',
      params: {'p_user_id': userId},
    );
    return (res as List)
        .map((e) => VenueSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> getMyVenueDetail(
    String userId,
    String venueId,
  ) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'get_my_sports_venue_detail',
      params: {'p_user_id': userId, 'p_venue_id': venueId},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<String> upsertVenue({
    required String userId,
    String? venueId,
    required String name,
    String? description,
    String? province,
    String? district,
    String? address,
    double? lat,
    double? lng,
    String? timezone,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'upsert_sports_venue',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_name': name,
        'p_description': description,
        'p_province': province,
        'p_district': district,
        'p_address': address,
        'p_lat': lat,
        'p_lng': lng,
        'p_timezone': timezone,
      },
    );
    return res.toString();
  }

  Future<void> setVenueSports(
    String userId,
    String venueId,
    List<Map<String, dynamic>> sports,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_sports_venue_sports',
      params: {'p_user_id': userId, 'p_venue_id': venueId, 'p_sports': sports},
    );
  }

  Future<String> upsertCourt({
    required String userId,
    String? courtId,
    required String venueId,
    required String sportId,
    required String name,
    int capacity = 1,
    double? priceAmount,
    String pricingUnit = 'hour',
    String? courtType,
    bool? indoor,
    String approvalMode = 'instant',
    String? unitLabel,
    bool isActive = true,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'upsert_sports_venue_court',
      params: {
        'p_user_id': userId,
        'p_court_id': courtId,
        'p_venue_id': venueId,
        'p_sport_id': sportId,
        'p_name': name,
        'p_capacity': capacity,
        'p_price_amount': priceAmount,
        'p_pricing_unit': pricingUnit,
        'p_court_type': courtType,
        'p_indoor': indoor,
        'p_booking_approval_mode': approvalMode,
        'p_unit_label': unitLabel,
        'p_is_active': isActive,
      },
    );
    return res.toString();
  }

  Future<void> setVenueOperatingHours(
    String userId,
    String venueId,
    List<Map<String, dynamic>> hours,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_sports_venue_operating_hours',
      params: {'p_user_id': userId, 'p_venue_id': venueId, 'p_hours': hours},
    );
  }

  Future<void> setVenueAmenities(
    String userId,
    String venueId,
    List<String> amenities,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_sports_venue_amenities',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_amenities': amenities,
      },
    );
  }

  Future<int> publishVenueTerms(
    String userId,
    String venueId,
    String termsText, {
    int cancellationCutoffMinutes = 60,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'publish_sports_venue_terms',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_terms_text': termsText,
        'p_cancellation_cutoff_minutes': cancellationCutoffMinutes,
      },
    );
    return (res as num).toInt();
  }

  // =============== Booking lifecycle ===============

  Future<String> createBooking({
    required String userId,
    required String courtId,
    required DateTime startsAt,
    required DateTime endsAt,
    required int termsVersion,
    String? idempotencyKey,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'create_sports_venue_booking',
      params: {
        'p_user_id': userId,
        'p_court_id': courtId,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_terms_version': termsVersion,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return res.toString();
  }

  Future<void> cancelBooking(
    String userId,
    String bookingId, {
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'cancel_sports_venue_booking',
      params: {
        'p_user_id': userId,
        'p_booking_id': bookingId,
        'p_reason': reason,
      },
    );
  }

  /// Returns 'confirmed', 'rejected' or 'conflict'.
  Future<String> decideBooking(
    String userId,
    String bookingId,
    String decision, {
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'decide_sports_venue_booking',
      params: {
        'p_user_id': userId,
        'p_booking_id': bookingId,
        'p_decision': decision,
        'p_reason': reason,
      },
    );
    return res.toString();
  }

  Future<void> changePendingBookingSlot({
    required String userId,
    required String bookingId,
    required DateTime startsAt,
    required DateTime endsAt,
    int? termsVersion,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'change_pending_venue_booking_slot',
      params: {
        'p_user_id': userId,
        'p_booking_id': bookingId,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_terms_version': termsVersion,
      },
    );
  }

  Future<List<VenueBooking>> listMyBookings(
    String userId, {
    List<String>? statuses,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_sports_venue_bookings',
      params: {'p_user_id': userId, 'p_statuses': statuses},
    );
    return (res as List)
        .map((e) => VenueBooking.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<VenueBooking>> listVenueBookingsForManager(
    String userId,
    String venueId, {
    List<String>? statuses,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_sports_venue_bookings_for_manager',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_statuses': statuses,
      },
    );
    return (res as List)
        .map((e) => VenueBooking.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Venue ids where the user has at least one booking (เคยจองแล้ว filter).
  Future<Set<String>> listMyBookedVenueIds(String userId) async {
    final bookings = await listMyBookings(userId);
    return bookings.map((b) => b.venueId).toSet();
  }

  /// Venue ids the user manages (เป็นเจ้าของ filter).
  Future<Set<String>> listMyManagedVenueIds(String userId) async {
    final venues = await listMyVenues(userId);
    return venues.map((v) => v.id).toSet();
  }

  // =============== Reviews ===============

  Future<String> submitReview({
    required String userId,
    required String bookingId,
    required int rating,
    String? comment,
    List<String> tagIds = const [],
    List<String> customTags = const [],
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'submit_sports_venue_review',
      params: {
        'p_user_id': userId,
        'p_booking_id': bookingId,
        'p_rating': rating,
        'p_comment': comment,
        'p_tag_ids': tagIds,
        'p_custom_tags': customTags,
      },
    );
    return res.toString();
  }

  Future<void> reportReview(
    String userId,
    String reviewId, {
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'report_sports_venue_review',
      params: {
        'p_user_id': userId,
        'p_review_id': reviewId,
        'p_reason': reason,
      },
    );
  }
}
