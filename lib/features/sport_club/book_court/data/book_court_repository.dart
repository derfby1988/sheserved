import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sheserved/config/app_config.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/services/websocket_service.dart';
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

  /// One public venue by id, hydrated for the detail sheet. Returns null
  /// when the venue is gone or no longer publicly visible.
  Future<VenueSummary?> getPublicVenue(String venueId) async {
    final res = await _client
        .from('sports_venues_public')
        .select()
        .eq('id', venueId)
        .maybeSingle();
    if (res == null) return null;
    final hydrated = await hydrateVenueCards([
      VenueSummary.fromJson(Map<String, dynamic>.from(res)),
    ]);
    return hydrated.isEmpty ? null : hydrated.first;
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

    final startingPriceByVenue = <String, double>{};
    try {
      final priceRows = await _client
          .from('sports_venue_price_summary_public')
          .select('venue_id, starting_price_amount')
          .inFilter('venue_id', ids);
      for (final row in (priceRows as List)) {
        final m = Map<String, dynamic>.from(row);
        final amount = (m['starting_price_amount'] as num?)?.toDouble();
        if (amount != null) {
          startingPriceByVenue[m['venue_id']?.toString() ?? ''] = amount;
        }
      }
    } catch (_) {}

    final ratingByVenue = <String, (double, int)>{};
    for (final row in (results[0] as List)) {
      final m = Map<String, dynamic>.from(row);
      ratingByVenue[m['venue_id']?.toString() ?? ''] = (
        // 10-point scale is authoritative; fall back to the folded
        // legacy 1–5 average only while the pre-21.7.14 view is live.
        (m['average_rating_10'] as num?)?.toDouble() ??
            ((m['average_rating'] as num?)?.toDouble() ?? 0) * 2,
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
            startingPriceAmount: startingPriceByVenue[v.id],
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

  Future<VenueCourtPriceQuote> quoteCourtPrice(
    VenueCourt court,
    DateTime startsAt,
    DateTime endsAt,
  ) async {
    try {
      final result = await _client.rpc(
        'quote_sports_venue_court_price',
        params: {
          'p_court_id': court.id,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_ends_at': endsAt.toUtc().toIso8601String(),
        },
      );
      if (result is! Map) {
        throw const FormatException('Invalid court price quote response');
      }
      return VenueCourtPriceQuote.fromJson(Map<String, dynamic>.from(result));
    } catch (error) {
      if (!error.toString().contains('PGRST202')) rethrow;
      final hours = endsAt.difference(startsAt).inSeconds / 3600;
      final total = court.pricingUnit == 'hour' && court.priceAmount != null
          ? ((court.priceAmount! * hours * 100).roundToDouble() / 100)
          : null;
      return VenueCourtPriceQuote(
        totalAmount: total,
        priceAmount: court.priceAmount,
        pricingUnit: court.pricingUnit,
      );
    }
  }

  Future<Map<String, List<double>>> quoteVenuePricesForLocalSlot({
    required List<String> venueIds,
    required String? sportId,
    required DateTime localDate,
    required int startTimeMinutes,
    required int durationMinutes,
  }) async {
    if (venueIds.isEmpty) return {};
    final result = await _client.rpc(
      'quote_sports_venue_prices_for_local_slot',
      params: {
        'p_venue_ids': venueIds,
        'p_sport_id': sportId,
        'p_local_date':
            '${localDate.year.toString().padLeft(4, '0')}-'
            '${localDate.month.toString().padLeft(2, '0')}-'
            '${localDate.day.toString().padLeft(2, '0')}',
        'p_start_time':
            '${(startTimeMinutes ~/ 60).toString().padLeft(2, '0')}:'
            '${(startTimeMinutes % 60).toString().padLeft(2, '0')}:00',
        'p_duration_minutes': durationMinutes,
      },
    );
    final prices = <String, List<double>>{};
    for (final row in result as List) {
      final value = Map<String, dynamic>.from(row);
      final venueId = value['venue_id']?.toString() ?? '';
      final amount = (value['total_amount'] as num?)?.toDouble();
      if (venueId.isNotEmpty && amount != null) {
        prices.putIfAbsent(venueId, () => []).add(amount);
      }
    }
    return prices;
  }

  Future<List<VenueCourtPriceRule>> listMyCourtPriceRules(
    String userId,
    String courtId,
  ) async {
    _assertCurrentUser(userId);
    final result = await _client.rpc(
      'list_my_sports_venue_court_price_rules',
      params: {'p_user_id': userId, 'p_court_id': courtId},
    );
    return (result as List)
        .map(
          (row) => VenueCourtPriceRule.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<List<VenueOperatingHours>> listPublicOperatingHours(
    String venueId,
  ) async {
    final res = await _client
        .from('sports_venue_operating_hours_public')
        .select()
        .eq('venue_id', venueId)
        .order('day_of_week', ascending: true);
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
    if (res is! Map) {
      throw const FormatException('Invalid court availability response');
    }
    return CourtAvailability.fromJson(Map<String, dynamic>.from(res));
  }

  Future<void> manageCourtAvailability({
    required String userId,
    required String courtId,
    required bool suspend,
    required List<({DateTime start, DateTime end})> ranges,
  }) async {
    _assertCurrentUser(userId);
    if (ranges.isEmpty) throw ArgumentError.value(ranges, 'ranges');
    await _client.rpc(
      'manage_sports_venue_availability',
      params: {
        'p_user_id': userId,
        'p_court_id': courtId,
        'p_action': suspend ? 'suspend' : 'unsuspend',
        'p_ranges': [
          for (final range in ranges)
            {
              'starts_at': range.start.toUtc().toIso8601String(),
              'ends_at': range.end.toUtc().toIso8601String(),
            },
        ],
      },
    );
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

  Future<VenueOwnerPublicProfile?> getPublicVenueOwnerProfile(
    String venueId,
  ) async {
    final result = await _client.rpc(
      'get_public_sports_venue_owner_profile',
      params: {'p_venue_id': venueId},
    );
    if (result is! Map) return null;
    final profile = VenueOwnerPublicProfile.fromJson(
      Map<String, dynamic>.from(result),
    );
    return profile.hasPublicInfo ? profile : null;
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
    // 21.7.19: NULL/omitted means keep on update — the venue label is
    // managed explicitly through setVenueUnitLabel.
    String? venueUnitLabelOverride,
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
        'p_venue_unit_label_override': venueUnitLabelOverride,
      },
    );
    return res.toString();
  }

  /// Explicit two-level venue label setter (Phase 21.7.19). A null
  /// [override] means the venue follows the reference sport's catalog
  /// suggestion; a null [referenceSportId] leaves the generic 'สนาม'
  /// fallback. A non-null reference must be one of the venue's sports.
  Future<void> setVenueUnitLabel(
    String userId,
    String venueId, {
    String? override,
    String? referenceSportId,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_sports_venue_unit_label',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_venue_unit_label_override': override,
        'p_reference_sport_id': referenceSportId,
      },
    );
  }

  /// Thai venue-label catalog suggestions per sport (approved sports only,
  /// per table RLS) — used to preview the sport-derived venue label.
  Future<Map<String, String>> listVenueUnitDefaults(
    List<String> sportIds,
  ) async {
    if (sportIds.isEmpty) return const {};
    final res = await _client
        .from('sports_venue_unit_defaults')
        .select('sport_id, singular')
        .eq('locale', 'th')
        .inFilter('sport_id', sportIds);
    return {
      for (final row in (res as List))
        row['sport_id'].toString(): row['singular'].toString(),
    };
  }

  Future<void> setVenueSports(
    String userId,
    String venueId,
    List<Map<String, dynamic>> sports, {
    String? referenceSportId,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_sports_venue_sports',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_sports': sports,
        'p_reference_sport_id': referenceSportId,
      },
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
    List<VenueCourtPriceRule>? priceRules,
    // 21.7.18: release params use NULL-means-keep — omit them entirely
    // (bookingReleaseMode == null) to preserve the court's override.
    // 'inherit'/'always_open' clear the custom schedule server-side;
    // 'custom' uses bookingReleaseDays with one shared time/window.
    String? bookingReleaseMode,
    int? bookingReleaseDayOfWeek,
    List<int>? bookingReleaseDays,
    String? bookingReleaseTime,
    int? bookingReleaseWindowDays,
    // 21.7.19 resource label contract: null mode keeps the legacy
    // p_unit_label semantics; 'inherit' clears the per-court override;
    // 'custom' stores unitLabelOverride (falling back to unitLabel).
    String? unitLabelMode,
    String? unitLabelOverride,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'upsert_sports_venue_court_with_release_days',
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
        ...?(priceRules == null
            ? null
            : {
                'p_price_rules': priceRules
                    .map((rule) => rule.toJson())
                    .toList(),
              }),
        ...?(bookingReleaseMode == null
            ? null
            : {
                'p_booking_release_mode': bookingReleaseMode,
                'p_booking_release_day_of_week': bookingReleaseDayOfWeek,
                'p_booking_release_days': bookingReleaseDays,
                'p_booking_release_time': bookingReleaseTime,
                'p_booking_release_window_days': bookingReleaseWindowDays,
              }),
        ...?(unitLabelMode == null
            ? null
            : {
                'p_unit_label_mode': unitLabelMode,
                'p_unit_label_override': unitLabelOverride,
              }),
      },
    );
    return res.toString();
  }

  /// Venue-level recurring booking release (Phase 21.7.18). Passing all
  /// nulls clears the rule — advance booking becomes unlimited again.
  Future<void> setVenueBookingRelease(
    String userId,
    String venueId, {
    int? dayOfWeek,
    String? releaseTime,
    int? windowDays,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_sports_venue_booking_release',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_day_of_week': dayOfWeek,
        'p_time': releaseTime,
        'p_window_days': windowDays,
      },
    );
  }

  /// Sets selected weekly release days at one venue-local time. Passing null
  /// for all fields removes the advance-booking release limit.
  Future<void> setVenueBookingReleaseDays(
    String userId,
    String venueId, {
    List<int>? daysOfWeek,
    String? releaseTime,
    int? windowDays,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_sports_venue_booking_release_days',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_days_of_week': daysOfWeek,
        'p_time': releaseTime,
        'p_window_days': windowDays,
      },
    );
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

  /// Submit a draft (or rejected) venue for admin review. The server
  /// refuses with VENUE_NOT_READY while mandatory setup items are missing.
  Future<void> submitVenueForReview(String userId, String venueId) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'submit_sports_venue_for_review',
      params: {'p_user_id': userId, 'p_venue_id': venueId},
    );
  }

  Future<PlatformVenueTerms> getPlatformVenueTerms(String adminId) async {
    _assertCurrentUser(adminId);
    final result = await _client.rpc(
      'get_sports_venue_platform_terms',
      params: {'p_admin_id': adminId},
    );
    return PlatformVenueTerms.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<PlatformVenueTerms> setPlatformVenueTerms({
    required String adminId,
    required String termsText,
    required int cancellationCutoffMinutes,
  }) async {
    _assertCurrentUser(adminId);
    final result = await _client.rpc(
      'set_sports_venue_platform_terms',
      params: {
        'p_admin_id': adminId,
        'p_terms_text': termsText,
        'p_cancellation_cutoff_minutes': cancellationCutoffMinutes,
      },
    );
    return PlatformVenueTerms.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  /// Confirm that the venue uses the active platform-managed terms instead
  /// of publishing venue-specific terms.
  Future<void> confirmPlatformTerms(String userId, String venueId) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'confirm_sports_venue_platform_terms',
      params: {'p_user_id': userId, 'p_venue_id': venueId},
    );
  }

  /// Admin-side readiness snapshot for one venue under review: the venue
  /// row, missing setup items, counts and status history.
  Future<Map<String, dynamic>> getVenueAdminReviewDetail(
    String adminId,
    String venueId,
  ) async {
    _assertCurrentUser(adminId);
    final res = await _client.rpc(
      'get_sports_venue_admin_review_detail',
      params: {'p_admin_id': adminId, 'p_venue_id': venueId},
    );
    return Map<String, dynamic>.from(res as Map);
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

  /// Mirrors the Fitness Buddies approval flow: once the RPC has persisted
  /// its `app_notifications` rows we nudge the websocket server to
  /// re-publish them to each recipient's room. Fire-and-forget — delivery
  /// must never fail the booking mutation, matching sports_hub_notify's
  /// guarded semantics.
  void _notifyVenueBooking(String bookingId) {
    try {
      WebSocketService().sendVenueBookingNotification(bookingId: bookingId);
    } catch (_) {}
  }

  Future<String> createBooking({
    required String userId,
    required String courtId,
    required DateTime startsAt,
    required DateTime endsAt,
    required int termsVersion,
    String? idempotencyKey,
    int? priceScheduleVersion,
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
        ...?(priceScheduleVersion == null
            ? null
            : {'p_expected_price_schedule_version': priceScheduleVersion}),
      },
    );
    final bookingId = res.toString();
    _notifyVenueBooking(bookingId);
    return bookingId;
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
    _notifyVenueBooking(bookingId);
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
    _notifyVenueBooking(bookingId);
    return res.toString();
  }

  Future<void> changePendingBookingSlot({
    required String userId,
    required String bookingId,
    required DateTime startsAt,
    required DateTime endsAt,
    int? termsVersion,
    int? priceScheduleVersion,
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
        ...?(priceScheduleVersion == null
            ? null
            : {'p_expected_price_schedule_version': priceScheduleVersion}),
      },
    );
    _notifyVenueBooking(bookingId);
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

  /// Venue ids the user owns or was invited to manage (เป็นเจ้าของ filter).
  /// Venues reachable only through the Sheserved-admin override
  /// (member_role='admin') are excluded — oversight is not ownership.
  Future<Set<String>> listMyManagedVenueIds(String userId) async {
    final venues = await listMyVenues(userId);
    return venues
        .where((v) => v.memberRole != 'admin')
        .map((v) => v.id)
        .toSet();
  }

  // =============== Evidence-gated booking groups (Phase 21.7.21) ========

  /// Sanitized policy surface for the booking dialog — NULL when the court
  /// has no effective evidence policy (legacy flow applies).
  Future<CourtEvidenceSurface?> getCourtEvidenceSurface(
    String courtId,
  ) async {
    final res = await _client.rpc(
      'get_sports_venue_court_evidence_surface',
      params: {'p_court_id': courtId},
    );
    if (res == null) return null;
    return CourtEvidenceSurface.fromJson(
      Map<String, dynamic>.from(res as Map),
    );
  }

  /// Creates an atomic booking group. Every item must carry the same venue
  /// and approval mode; the server computes prices and deadlines.
  /// [items] entries: {courtId, startsAt, endsAt, priceScheduleVersion?}.
  Future<String> createBookingGroup({
    required String userId,
    required List<
      ({
        String courtId,
        DateTime startsAt,
        DateTime endsAt,
        int? priceScheduleVersion,
      })
    >
    items,
    required int termsVersion,
    String? idempotencyKey,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'create_sports_venue_booking_group',
      params: {
        'p_user_id': userId,
        'p_items': [
          for (final item in items)
            {
              'court_id': item.courtId,
              'starts_at': item.startsAt.toUtc().toIso8601String(),
              'ends_at': item.endsAt.toUtc().toIso8601String(),
              ...?(item.priceScheduleVersion == null
                  ? null
                  : {
                      'expected_price_schedule_version':
                          item.priceScheduleVersion,
                    }),
            },
        ],
        'p_terms_version': termsVersion,
        'p_idempotency_key': idempotencyKey,
      },
    );
    final groupId = res.toString();
    _notifyVenueBooking(groupId);
    return groupId;
  }

  /// Submits evidence files already uploaded to the private bucket.
  /// [items] entries: {requirementKey, storagePath, mime?, sizeBytes?}.
  /// Returns per-item results (evidenceId, revision, verificationStatus).
  Future<List<Map<String, dynamic>>> submitGroupEvidence({
    required String userId,
    required String groupId,
    required List<
      ({
        String requirementKey,
        String storagePath,
        String? mime,
        int? sizeBytes,
      })
    >
    items,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'submit_sports_venue_booking_evidence',
      params: {
        'p_user_id': userId,
        'p_booking_group_id': groupId,
        'p_items': [
          for (final item in items)
            {
              'requirement_key': item.requirementKey,
              'storage_path': item.storagePath,
              if (item.mime != null) 'mime': item.mime,
              if (item.sizeBytes != null) 'size_bytes': item.sizeBytes,
            },
        ],
      },
    );
    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Booker or manager cancels the whole open group; held slots release.
  Future<void> cancelBookingGroup(
    String userId,
    String groupId, {
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'cancel_sports_venue_booking_group',
      params: {
        'p_user_id': userId,
        'p_booking_group_id': groupId,
        'p_reason': reason,
      },
    );
    _notifyVenueBooking(groupId);
  }

  /// Manager/owner decision. Group-level (requirementKey null): approve a
  /// pending group (pre-approval → hold, or confirm) or reject it.
  /// Evidence-level: approve/reject the current revision of one
  /// requirement — payment slips are owner-only server-side.
  /// Returns 'confirmed' | 'rejected' | 'conflict' | 'awaiting_evidence' |
  /// 'evidence_approved' | 'evidence_rejected'.
  Future<String> decideBookingGroup({
    required String userId,
    required String groupId,
    required String decision,
    String? reason,
    String? requirementKey,
    String? reasonCode,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'decide_sports_venue_booking_group',
      params: {
        'p_user_id': userId,
        'p_booking_group_id': groupId,
        'p_decision': decision,
        'p_reason': reason,
        'p_requirement_key': requirementKey,
        'p_reason_code': reasonCode,
      },
    );
    _notifyVenueBooking(groupId);
    return res.toString();
  }

  /// Bulk reject open groups in one venue. Each group is decided in its
  /// own savepoint server-side, so the result list always has one entry
  /// per requested id — `error` carries the failure code for groups that
  /// could not be rejected. Reject-only by design.
  Future<List<OwnerQueueBulkResult>> bulkRejectBookingGroups({
    required String userId,
    required String venueId,
    required List<String> groupIds,
    String? reason,
    String? reasonCode,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'decide_sports_venue_booking_groups_bulk',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_group_ids': groupIds,
        'p_reason': reason,
        'p_reason_code': reasonCode,
      },
    );
    for (final id in groupIds) {
      _notifyVenueBooking(id);
    }
    return (res as List? ?? const [])
        .map(
          (e) =>
              OwnerQueueBulkResult.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  /// Personal queue snooze for this manager — never touches the booking
  /// status or deadlines. Pass `minutes: null` to return the group to the
  /// queue immediately. Returns the effective `deferred_until`.
  Future<DateTime?> deferQueueItem({
    required String userId,
    required String groupId,
    int? minutes,
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'defer_sports_venue_queue_item',
      params: {
        'p_user_id': userId,
        'p_booking_group_id': groupId,
        'p_minutes': minutes,
        'p_reason': reason,
      },
    );
    return DateTime.tryParse(res?.toString() ?? '');
  }

  /// Booker moves pending (pre-hold) group children to new slots.
  /// [items] must cover every pending child exactly once.
  Future<void> changeBookingGroupSlots({
    required String userId,
    required String groupId,
    required List<({String bookingId, DateTime startsAt, DateTime endsAt})>
    items,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'change_sports_venue_booking_group_slots',
      params: {
        'p_user_id': userId,
        'p_booking_group_id': groupId,
        'p_items': [
          for (final item in items)
            {
              'booking_id': item.bookingId,
              'starts_at': item.startsAt.toUtc().toIso8601String(),
              'ends_at': item.endsAt.toUtc().toIso8601String(),
            },
        ],
      },
    );
    _notifyVenueBooking(groupId);
  }

  /// Booker reports an actual transfer the provider could not confirm
  /// (or after forfeit) — the owner decides whether money arrived.
  Future<String> reportGroupPaymentClaim({
    required String userId,
    required String groupId,
    double? reportedAmount,
    String? transferReference,
    String? evidencePath,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'report_sports_venue_booking_payment_claim',
      params: {
        'p_user_id': userId,
        'p_booking_group_id': groupId,
        'p_reported_amount': reportedAmount,
        'p_transfer_reference': transferReference,
        'p_evidence_path': evidencePath,
      },
    );
    return res.toString();
  }

  /// Booker view: own groups with countdowns, evidence, claims, refunds.
  Future<({DateTime? serverNow, List<VenueBookingGroup> groups})>
  listMyBookingGroups(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_sports_venue_booking_groups',
      params: {'p_user_id': userId},
    );
    final map = Map<String, dynamic>.from(res as Map);
    return (
      serverNow: DateTime.tryParse(map['serverNow']?.toString() ?? ''),
      groups: (map['groups'] as List? ?? const [])
          .map(
            (e) =>
                VenueBookingGroup.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
  }

  /// Owner/manager queue: attention groups, open payment claims, active
  /// refund cases. [filter] is one of all|due_soon|overdue|payment|
  /// document|deferred; [cursor] pages deterministically by due time.
  Future<OwnerEvidenceQueue> listEvidenceQueue(
    String userId,
    String venueId, {
    String filter = 'all',
    int limit = 50,
    OwnerQueueCursor? cursor,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_sports_venue_evidence_queue',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_filter': filter,
        'p_limit': limit,
        'p_cursor_due': cursor?.due,
        'p_cursor_created': cursor?.created,
        'p_cursor_id': cursor?.id,
      },
    );
    return OwnerEvidenceQueue.fromJson(
      Map<String, dynamic>.from(res as Map),
    );
  }

  /// Owner-only claim decision. [decision] is 'received' (requires
  /// [receivedAmount]) or 'not_received'.
  Future<void> decidePaymentClaim({
    required String userId,
    required String claimId,
    required String decision,
    double? receivedAmount,
    String? note,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'decide_sports_venue_booking_payment_claim',
      params: {
        'p_user_id': userId,
        'p_claim_id': claimId,
        'p_decision': decision,
        'p_received_amount': receivedAmount,
        'p_note': note,
      },
    );
  }

  /// Owner-only refund-case action: 'approve' (requires refundAmount),
  /// 'complete' (externalRef/receiptPath for the manual transfer record),
  /// 'fail' or 'not_refundable' (reason required for the last).
  Future<void> decideRefundCase({
    required String userId,
    required String caseId,
    required String action,
    double? refundAmount,
    String? reason,
    String? externalRef,
    String? receiptPath,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'decide_sports_venue_booking_refund_case',
      params: {
        'p_user_id': userId,
        'p_case_id': caseId,
        'p_action': action,
        'p_refund_amount': refundAmount,
        'p_reason': reason,
        'p_external_ref': externalRef,
        'p_receipt_path': receiptPath,
      },
    );
  }

  /// Mint a one-time upload grant binding this user/group/purpose (and
  /// requirement for evidence) to a pre-assigned private path.
  /// [purpose] is 'evidence' or 'claim'.
  Future<EvidenceUploadGrant> createEvidenceUploadGrant({
    required String userId,
    required String groupId,
    required String purpose,
    String? requirementKey,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'create_sports_venue_evidence_upload_grant',
      params: {
        'p_user_id': userId,
        'p_booking_group_id': groupId,
        'p_purpose': purpose,
        'p_requirement_key': requirementKey,
      },
    );
    return EvidenceUploadGrant.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Redeem [grant] at the Node gateway: magic-byte check, decode +
  /// re-encode (EXIF/GPS stripped server-side), then service-role write
  /// to the private bucket. Fail-closed — never fall back to a direct
  /// storage upload.
  Future<({String mime, int sizeBytes})> uploadEvidenceViaGateway({
    required EvidenceUploadGrant grant,
    required Uint8List bytes,
  }) async {
    final baseUrl = AppConfig.backendApiUrl;
    if (baseUrl.isEmpty) {
      throw StateError('EVIDENCE_UPLOAD_UNAVAILABLE');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/sports/evidence/upload'),
    );
    request.headers['x-app-version'] = AppConfig.appVersion;
    request.fields['token'] = grant.token;
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: 'evidence.jpg',
        contentType: MediaType.parse('image/jpeg'),
      ),
    );
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      String code = 'EVIDENCE_UPLOAD_FAILED';
      try {
        code =
            (jsonDecode(body) as Map<String, dynamic>)['error']
                ?.toString() ??
            code;
      } catch (_) {}
      throw StateError('$code:${streamed.statusCode}');
    }
    final map = jsonDecode(body) as Map<String, dynamic>;
    return (
      mime: map['mime']?.toString() ?? 'image/jpeg',
      sizeBytes:
          (map['sizeBytes'] as num?)?.toInt() ?? bytes.length,
    );
  }

  /// Mints a short-lived read token for one private evidence path. The
  /// Node backend redeems it and streams the object — the bucket stays
  /// private with no public URL.
  Future<String> mintEvidenceReadToken(
    String userId,
    String storagePath,
  ) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'mint_sports_venue_evidence_read_token',
      params: {'p_user_id': userId, 'p_path': storagePath},
    );
    final map = Map<String, dynamic>.from(res as Map);
    return map['token']?.toString() ?? '';
  }

  // =============== Owner evidence policy config ========================

  /// Venue-level evidence policy. `policy == null` disables the feature
  /// (server clears every policy column).
  Future<void> setVenueEvidencePolicy(
    String userId,
    String venueId,
    VenueEvidencePolicy? policy,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_sports_venue_evidence_policy',
      params: {
        'p_user_id': userId,
        'p_venue_id': venueId,
        'p_policy': policy?.toJson(),
      },
    );
  }

  /// Court override: [mode] is 'inherit' | 'off' | 'custom'. 'custom'
  /// requires a complete [policy]; 'inherit'/'off' ignore it.
  Future<void> setCourtEvidencePolicy(
    String userId,
    String courtId,
    String mode,
    VenueEvidencePolicy? policy,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_sports_venue_court_evidence_policy',
      params: {
        'p_user_id': userId,
        'p_court_id': courtId,
        'p_mode': mode,
        'p_policy': policy?.toJson(),
      },
    );
  }

  // =============== Admin provider controls (Phase 21.7.21.6) ===========

  Future<GlobalSlipVerificationPolicy> adminGetGlobalVerifyPolicy(
    String adminId,
  ) async {
    _assertCurrentUser(adminId);
    final res = await _client.rpc(
      'admin_get_sports_venue_verify_global_policy',
      params: {'p_admin_id': adminId},
    );
    return GlobalSlipVerificationPolicy.fromJson(
      Map<String, dynamic>.from(res as Map),
    );
  }

  Future<void> adminSetGlobalVerifyScope({
    required String adminId,
    required String scope,
  }) async {
    _assertCurrentUser(adminId);
    await _client.rpc(
      'admin_set_sports_venue_verify_global_scope',
      params: {'p_admin_id': adminId, 'p_scope': scope},
    );
  }

  Future<void> adminSetVenueVerifyControls({
    required String adminId,
    required String venueId,
    required bool isAllowlisted,
    String? costBearer,
    int? monthlyQuota,
    int? verifyTimeoutMinutes,
    bool clearQuota = false,
    bool clearTimeout = false,
  }) async {
    _assertCurrentUser(adminId);
    await _client.rpc(
      'admin_set_sports_venue_verify_controls',
      params: {
        'p_admin_id': adminId,
        'p_venue_id': venueId,
        'p_allowlisted': isAllowlisted,
        'p_verify_cost_bearer': costBearer,
        'p_verify_monthly_quota': monthlyQuota,
        'p_verify_timeout_minutes': verifyTimeoutMinutes,
        'p_clear_quota': clearQuota,
        'p_clear_timeout': clearTimeout,
      },
    );
  }

  /// Legacy adapter; new admin surfaces must use the platform scope and
  /// per-venue allowlist controls separately.
  Future<void> adminSetVenueVerifyPolicy({

    required String adminId,
    required String venueId,
    String? verifyScope,
    String? costBearer,
    int? monthlyQuota,
    int? verifyTimeoutMinutes,
    bool clearQuota = false,
    bool clearTimeout = false,
  }) async {
    _assertCurrentUser(adminId);
    await _client.rpc(
      'admin_set_sports_venue_verify_policy',
      params: {
        'p_admin_id': adminId,
        'p_venue_id': venueId,
        'p_verify_scope': verifyScope,
        'p_verify_cost_bearer': costBearer,
        'p_verify_monthly_quota': monthlyQuota,
        'p_verify_timeout_minutes': verifyTimeoutMinutes,
        'p_clear_quota': clearQuota,
        'p_clear_timeout': clearTimeout,
      },
    );
  }

  /// Admin-only read half of the venue verify policy — every venue with its
  /// current scope/bearer/quota/timeout plus provider and usage signals.
  Future<List<AdminVenueVerifyPolicy>> adminListVenueVerifyPolicies(
    String adminId,
  ) async {
    _assertCurrentUser(adminId);
    final res = await _client.rpc(
      'admin_list_sports_venue_verify_policies',
      params: {'p_admin_id': adminId},
    );
    return (res as List)
        .map(
          (e) => AdminVenueVerifyPolicy.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  Future<List<SlipVerificationProvider>> adminListSlipProviders(
    String adminId,
  ) async {
    _assertCurrentUser(adminId);
    final res = await _client.rpc(
      'admin_list_slip_verification_providers',
      params: {'p_admin_id': adminId},
    );
    return (res as List)
        .map(
          (e) => SlipVerificationProvider.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  /// Admin provider registry upsert. [apiKeyRef] is a secret-store name —
  /// never a raw key.
  Future<void> adminUpsertSlipProvider({
    required String adminId,
    required String code,
    required String displayName,
    String? endpointUrl,
    String? apiKeyRef,
    double? costPerCheck,
    int? verifyTimeoutMinutes,
    Map<String, dynamic>? capabilities,
    bool? isEnabled,
    int? priority,
    String? notes,
  }) async {
    _assertCurrentUser(adminId);
    await _client.rpc(
      'admin_upsert_slip_verification_provider',
      params: {
        'p_admin_id': adminId,
        'p_code': code,
        'p_display_name': displayName,
        'p_endpoint_url': endpointUrl,
        'p_api_key_ref': apiKeyRef,
        'p_cost_per_check': costPerCheck,
        'p_verify_timeout_minutes': verifyTimeoutMinutes,
        'p_capabilities': capabilities,
        'p_is_enabled': isEnabled,
        'p_priority': priority,
        'p_notes': notes,
      },
    );
  }

  // =============== Reviews ===============

  Future<String> submitReview({
    required String userId,
    required String bookingId,
    required int rating10,
    required Map<String, int> categoryScores,
    String? comment,
    List<String> tagIds = const [],
    List<String> customTags = const [],
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'submit_sports_venue_review_v2',
      params: {
        'p_user_id': userId,
        'p_booking_id': bookingId,
        'p_rating_10': rating10,
        'p_category_scores': categoryScores,
        'p_comment': comment,
        'p_tag_ids': tagIds,
        'p_custom_tags': customTags,
      },
    );
    return res.toString();
  }

  /// Active review categories that must each be scored (1–10) in the
  /// review form.
  Future<List<VenueReviewCategory>> listReviewCategoryCatalog() async {
    final res = await _client.rpc('list_sports_venue_review_categories');
    return (res as List)
        .map((e) => VenueReviewCategory.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Aggregated published-review summary for a venue, optionally scoped
  /// to one court (overall/category averages, band counts, topics).
  Future<VenueReviewSummary> getVenueReviewSummary(
    String venueId, {
    String? courtId,
  }) async {
    final res = await _client.rpc(
      'get_sports_venue_review_summary_v2',
      params: {'p_venue_id': venueId, 'p_court_id': courtId},
    );
    return VenueReviewSummary.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Server-side filtered/sorted/paginated review list. The caller's id
  /// is passed so rows can carry the `viewer_voted` flag; voting itself
  /// stays behind [setReviewHelpful].
  Future<VenueReviewListPage> listVenueReviewsV2(
    String venueId, {
    String? courtId,
    String? tagId,
    VenueReviewBand? band,
    VenueReviewSort sort = VenueReviewSort.helpful,
    int limit = 20,
    int offset = 0,
    String? viewerId,
  }) async {
    final res = await _client.rpc(
      'list_sports_venue_reviews_v2',
      params: {
        'p_venue_id': venueId,
        'p_court_id': courtId,
        'p_tag_id': tagId,
        'p_min_rating_10': band?.min,
        'p_max_rating_10': band?.max,
        'p_sort': sort.wireValue,
        'p_limit': limit,
        'p_offset': offset,
        'p_viewer_id': viewerId,
      },
    );
    final list = res as List;
    final rows = list
        .map((e) => VenueReview.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final total = list.isEmpty
        ? 0
        : (list.first['total_count'] as num?)?.toInt() ?? offset + rows.length;
    return VenueReviewListPage(
      reviews: rows,
      totalCount: total,
      nextOffset: offset + rows.length,
      hasMore: offset + rows.length < total,
    );
  }

  /// One helpful vote per review per account; idempotent in both
  /// directions. Self-votes and non-published reviews are rejected
  /// server-side.
  Future<void> setReviewHelpful(
    String userId,
    String reviewId, {
    required bool helpful,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_sports_venue_review_helpful',
      params: {
        'p_user_id': userId,
        'p_review_id': reviewId,
        'p_helpful': helpful,
      },
    );
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

/// Extracts the `opensAt` instant carried in the DETAIL clause of a
/// `BOOKING_NOT_OPEN_YET` PostgREST error (Phase 21.7.18). Returns null
/// for other errors or a malformed detail so callers can fall back to a
/// generic message.
DateTime? bookingReleaseOpensAt(Object error) {
  if (error is PostgrestException &&
      error.message.contains('BOOKING_NOT_OPEN_YET')) {
    return DateTime.tryParse(error.details?.toString() ?? '');
  }
  return null;
}
