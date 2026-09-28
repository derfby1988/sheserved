import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sheserved/services/auth_service.dart';
import 'coach_models.dart';

/// Supabase data access for the Find Coach domain.
///
/// Public reads go through the `coach_*_public` views (approved profiles
/// only). Every mutation goes through a SECURITY DEFINER RPC with an
/// explicit actor id — the client never writes coach tables directly.
class FindCoachRepository {
  final SupabaseClient _client;
  FindCoachRepository(this._client);

  void _assertCurrentUser(String actorUserId) {
    final currentUserId = AuthService.instance.currentUser?.id;
    if (currentUserId == null || currentUserId != actorUserId) {
      throw StateError('UNAUTHORIZED');
    }
  }

  // =============== Public discovery ===============

  /// Approved coaches. Sport/skill/mode/rate filtering that needs the
  /// per-sport relation is applied by the caller after hydration.
  Future<List<CoachSummary>> listPublicCoaches({
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    var q = _client.from('coach_profiles_public').select();
    if (query != null && query.trim().isNotEmpty) {
      q = q.ilike('display_name', '%${query.trim()}%');
    }
    final res = await q
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (res as List)
        .map((e) => CoachSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Hydrates sports, service areas and rating aggregates for coach cards.
  Future<List<CoachSummary>> hydrateCoachCards(
    List<CoachSummary> coaches,
  ) async {
    final ids = coaches.map((c) => c.id).toList();
    if (ids.isEmpty) return coaches;

    final results = await Future.wait([
      _client
          .from('coach_sports_public')
          .select('coach_id, sport_id, skill_levels, specialties')
          .inFilter('coach_id', ids),
      _client
          .from('coach_service_areas_public')
          .select()
          .inFilter('coach_id', ids),
      _client
          .from('coach_review_summary')
          .select()
          .inFilter('coach_id', ids),
      _client
          .from('coach_offerings_public')
          .select('coach_id, offering_type')
          .inFilter('coach_id', ids)
          .inFilter('status', const ['published', 'closed']),
    ]);

    final sportsByCoach = <String, Set<String>>{};
    final levelsByCoach = <String, Set<String>>{};
    final specialtiesByCoach = <String, List<String>>{};
    for (final row in (results[0] as List)) {
      final m = Map<String, dynamic>.from(row);
      final cid = m['coach_id']?.toString() ?? '';
      sportsByCoach.putIfAbsent(cid, () => {}).add(
        m['sport_id']?.toString() ?? '',
      );
      for (final level in (m['skill_levels'] as List?) ?? const []) {
        levelsByCoach.putIfAbsent(cid, () => {}).add(level.toString());
      }
      for (final spec in (m['specialties'] as List?) ?? const []) {
        final list = specialtiesByCoach.putIfAbsent(cid, () => []);
        if (!list.contains(spec.toString())) list.add(spec.toString());
      }
    }

    final areasByCoach = <String, List<CoachServiceArea>>{};
    for (final row in (results[1] as List)) {
      final m = Map<String, dynamic>.from(row);
      areasByCoach
          .putIfAbsent(m['coach_id']?.toString() ?? '', () => [])
          .add(CoachServiceArea.fromJson(m));
    }

    final ratingByCoach = <String, (double, int, double)>{};
    for (final row in (results[2] as List)) {
      final m = Map<String, dynamic>.from(row);
      ratingByCoach[m['coach_id']?.toString() ?? ''] = (
        (m['average_rating'] as num?)?.toDouble() ?? 0,
        (m['review_count'] as num?)?.toInt() ?? 0,
        (m['average_rating_10'] as num?)?.toDouble() ?? 0,
      );
    }

    final offeringTypesByCoach = <String, Set<String>>{};
    for (final row in (results[3] as List)) {
      final m = Map<String, dynamic>.from(row);
      offeringTypesByCoach
          .putIfAbsent(m['coach_id']?.toString() ?? '', () => {})
          .add(m['offering_type']?.toString() ?? '');
    }

    return coaches
        .map(
          (c) => c.copyWith(
            sportIds: sportsByCoach[c.id] ?? const {},
            skillLevels: levelsByCoach[c.id] ?? const {},
            specialties: specialtiesByCoach[c.id] ?? const [],
            serviceAreas: areasByCoach[c.id] ?? const [],
            offeringTypes: offeringTypesByCoach[c.id] ?? const {},
            averageRating: ratingByCoach[c.id]?.$1,
            averageRating10: ratingByCoach[c.id]?.$3,
            reviewCount: ratingByCoach[c.id]?.$2 ?? 0,
          ),
        )
        .toList();
  }

  Future<List<CoachAvailabilityWindow>> listCoachAvailability(
    String coachId,
  ) async {
    final res = await _client
        .from('coach_availability_public')
        .select()
        .eq('coach_id', coachId)
        .order('day_of_week');
    return (res as List)
        .map(
          (e) => CoachAvailabilityWindow.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  Future<List<CoachReview>> listCoachReviews(
    String coachId, {
    int limit = 50,
  }) async {
    final res = await _client
        .from('coach_reviews_public')
        .select()
        .eq('coach_id', coachId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (res as List)
        .map((e) => CoachReview.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // =============== Coach profile management ===============

  Future<CoachSummary?> getMyCoachProfile(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'get_my_coach_profile',
      params: {'p_user_id': userId},
    );
    final list = res as List;
    if (list.isEmpty) return null;
    return CoachSummary.fromJson(Map<String, dynamic>.from(list.first));
  }

  Future<String> upsertCoachProfile({
    required String userId,
    required String displayName,
    String? bio,
    String? timezone,
    double? hourlyRate,
    String teachingMode = 'onsite',
    String? experience,
    bool? acceptingStudents,
    String? coverUrl,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'upsert_coach_profile',
      params: {
        'p_user_id': userId,
        'p_display_name': displayName,
        'p_bio': bio,
        'p_timezone': timezone,
        'p_hourly_rate': hourlyRate,
        'p_teaching_mode': teachingMode,
        'p_experience': experience,
        'p_accepting_students': acceptingStudents,
        'p_cover_url': coverUrl,
      },
    );
    return res.toString();
  }

  Future<CoachProfileCompleteness> getProfileCompleteness(
    String userId,
  ) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'get_coach_profile_completeness',
      params: {'p_user_id': userId},
    );
    return CoachProfileCompleteness.fromJson(
      Map<String, dynamic>.from(res as Map),
    );
  }

  /// Submits the profile for admin review. Throws PROFILE_INCOMPLETE
  /// when the checklist is not satisfied.
  Future<void> submitProfileForReview(String userId) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'submit_coach_profile_review',
      params: {'p_user_id': userId},
    );
  }

  // =============== Contacts / credentials / locations ===============

  Future<CoachContact?> getMyCoachContacts(String userId) async {
    _assertCurrentUser(userId);
    final profile = await getMyCoachProfile(userId);
    if (profile == null) return null;
    final res = await _client.rpc(
      'get_coach_contacts',
      params: {'p_user_id': userId, 'p_coach_id': profile.id},
    );
    final list = res as List;
    if (list.isEmpty) return const CoachContact();
    return CoachContact.fromJson(Map<String, dynamic>.from(list.first));
  }

  /// Throws NOT_AUTHORIZED unless the caller is the coach, an admin or a
  /// learner with a confirmed/completed relationship.
  Future<CoachContact?> getCoachContacts(
    String userId,
    String coachId,
  ) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'get_coach_contacts',
      params: {'p_user_id': userId, 'p_coach_id': coachId},
    );
    final list = res as List;
    if (list.isEmpty) return const CoachContact();
    return CoachContact.fromJson(Map<String, dynamic>.from(list.first));
  }

  Future<void> setCoachContacts(
    String userId, {
    String? phone,
    String? lineId,
    String? facebookUrl,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_coach_contacts',
      params: {
        'p_user_id': userId,
        'p_phone': phone,
        'p_line_id': lineId,
        'p_facebook_url': facebookUrl,
      },
    );
  }

  Future<List<CoachCertification>> listMyCredentials(
    String userId,
  ) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_coach_credentials',
      params: {'p_user_id': userId},
    );
    return (res as List)
        .map(
          (e) =>
              CoachCertification.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  /// Replace-all writer: rows absent from [items] are deleted; edited
  /// content drops back to pending review.
  Future<void> setCoachCertifications(
    String userId,
    List<CoachCertification> items,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_coach_certifications',
      params: {
        'p_user_id': userId,
        'p_items': items.map((c) => c.toJson()).toList(),
      },
    );
  }

  Future<void> reviewCertification(
    String adminId,
    String certId,
    String decision, {
    String? reason,
  }) async {
    _assertCurrentUser(adminId);
    await _client.rpc(
      'review_coach_certification',
      params: {
        'p_admin_id': adminId,
        'p_cert_id': certId,
        'p_decision': decision,
        'p_reason': reason,
      },
    );
  }

  Future<List<CoachTeachingLocation>> listPublicLocations(
    String coachId,
  ) async {
    final res = await _client
        .from('coach_teaching_locations_public')
        .select()
        .eq('coach_id', coachId);
    return (res as List)
        .map(
          (e) => CoachTeachingLocation.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  /// Coach's own locations (including any the public view would hide).
  Future<List<CoachTeachingLocation>> listMyLocations(
    String userId,
  ) async {
    _assertCurrentUser(userId);
    final profile = await getMyCoachProfile(userId);
    if (profile == null) return const [];
    final res = await _client
        .from('coach_teaching_locations')
        .select()
        .eq('coach_id', profile.id);
    return (res as List)
        .map(
          (e) => CoachTeachingLocation.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  Future<void> setCoachTeachingLocations(
    String userId,
    List<CoachTeachingLocation> items,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_coach_teaching_locations',
      params: {
        'p_user_id': userId,
        'p_items': items.map((l) => l.toJson()).toList(),
      },
    );
  }

  // =============== Favorites / relationships ===============

  /// Returns the new favorited state.
  Future<bool> toggleCoachFavorite(String userId, String coachId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'toggle_coach_favorite',
      params: {'p_user_id': userId, 'p_coach_id': coachId},
    );
    return res == true;
  }

  Future<Set<String>> listMyFavoriteCoachIds(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_coach_favorite_ids',
      params: {'p_user_id': userId},
    );
    return (res as List).map((e) => e.toString()).toSet();
  }

  /// Coaches the caller has a confirmed/completed booking or enrollment
  /// with — backs the "ผู้ฝึกสอนของฉัน" filter.
  Future<Set<String>> listMyCoachRelationshipIds(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_coach_relationship_ids',
      params: {'p_user_id': userId},
    );
    return (res as List).map((e) => e.toString()).toSet();
  }

  // =============== Offerings / sessions ===============

  /// Public board for the coach detail sheet. Pass [viewerId] to
  /// include per-session enrollment state for the signed-in learner.
  Future<List<CoachOffering>> getOfferingBoard(
    String coachId, {
    String? viewerId,
  }) async {
    final res = await _client.rpc(
      'get_coach_offering_board',
      params: {'p_coach_id': coachId, 'p_viewer_id': viewerId},
    );
    return (res as List)
        .map((e) => CoachOffering.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<CoachOffering>> listMyOfferings(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_coach_offerings',
      params: {'p_user_id': userId},
    );
    return (res as List)
        .map((e) => CoachOffering.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<String> upsertOffering(
    String userId, {
    String? offeringId,
    required String offeringType,
    required String title,
    String? description,
    String? sportId,
    List<String> learnerLevels = const [],
    String teachingMode = 'onsite',
    String? locationId,
    String? locationLabel,
    double? price,
    String pricingUnit = 'per_hour',
    int? capacity,
    int minEnrollment = 0,
    int enrollmentCutoffHours = 24,
    int cancellationCutoffHours = 24,
    String scheduleNoResponse = 'cancel',
    bool autoConfirm = false,
    bool allowPartialEnrollment = true,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'upsert_coach_offering',
      params: {
        'p_user_id': userId,
        'p_offering_id': offeringId,
        'p_offering_type': offeringType,
        'p_title': title,
        'p_description': description,
        'p_sport_id': sportId,
        'p_learner_levels': learnerLevels,
        'p_teaching_mode': teachingMode,
        'p_location_id': locationId,
        'p_location_label': locationLabel,
        'p_price': price,
        'p_pricing_unit': pricingUnit,
        'p_capacity': capacity,
        'p_min_enrollment': minEnrollment,
        'p_enrollment_cutoff_hours': enrollmentCutoffHours,
        'p_cancellation_cutoff_hours': cancellationCutoffHours,
        'p_schedule_no_response': scheduleNoResponse,
        'p_auto_confirm': autoConfirm,
        'p_allow_partial_enrollment': allowPartialEnrollment,
      },
    );
    return res.toString();
  }

  Future<void> setOfferingSessions(
    String userId,
    String offeringId,
    List<Map<String, dynamic>> sessions,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_coach_offering_sessions',
      params: {
        'p_user_id': userId,
        'p_offering_id': offeringId,
        'p_sessions': sessions,
      },
    );
  }

  Future<void> publishOffering(String userId, String offeringId) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'publish_coach_offering',
      params: {'p_user_id': userId, 'p_offering_id': offeringId},
    );
  }

  Future<void> closeOffering(String userId, String offeringId) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'close_coach_offering',
      params: {'p_user_id': userId, 'p_offering_id': offeringId},
    );
  }

  Future<void> cancelOffering(
    String userId,
    String offeringId,
    String reason,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'cancel_coach_offering',
      params: {
        'p_user_id': userId,
        'p_offering_id': offeringId,
        'p_reason': reason,
      },
    );
  }

  Future<void> cancelSession(
    String userId,
    String sessionId,
    String reason,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'cancel_coach_session',
      params: {
        'p_user_id': userId,
        'p_session_id': sessionId,
        'p_reason': reason,
      },
    );
  }

  /// Minimum-enrollment decision once intake has closed.
  Future<void> resolveMinimum(
    String userId,
    String offeringId, {
    required bool proceed,
    DateTime? reopenUntil,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'resolve_coach_minimum',
      params: {
        'p_user_id': userId,
        'p_offering_id': offeringId,
        'p_action': proceed ? 'proceed' : 'cancel',
        'p_reopen_until': reopenUntil?.toUtc().toIso8601String(),
      },
    );
  }

  // =============== 1:1 slots ===============

  /// Published, still-bookable slots for the public detail sheet.
  Future<List<CoachSlot>> listPublicSlots(String coachId) async {
    final res = await _client
        .from('coach_slots_public')
        .select()
        .eq('coach_id', coachId)
        .order('starts_at');
    return (res as List)
        .map((e) => CoachSlot.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<CoachSlot>> listMySlots(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_coach_slots',
      params: {'p_user_id': userId},
    );
    return (res as List)
        .map((e) => CoachSlot.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<String> createSlot(
    String userId,
    String offeringId, {
    required DateTime startsAt,
    required DateTime endsAt,
    bool publish = false,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'create_coach_slot',
      params: {
        'p_user_id': userId,
        'p_offering_id': offeringId,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_publish': publish,
      },
    );
    return res.toString();
  }

  Future<void> updateSlot(
    String userId,
    String slotId, {
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'update_coach_slot',
      params: {
        'p_user_id': userId,
        'p_slot_id': slotId,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> publishSlot(String userId, String slotId) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'publish_coach_slot',
      params: {'p_user_id': userId, 'p_slot_id': slotId},
    );
  }

  Future<void> cancelSlot(
    String userId,
    String slotId, {
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'cancel_coach_slot',
      params: {
        'p_user_id': userId,
        'p_slot_id': slotId,
        'p_reason': reason,
      },
    );
  }

  /// Slot-based 1:1 request — pending does not reserve the slot; first
  /// approval claims it atomically.
  Future<String> createSlotBookingRequest({
    required String userId,
    required String slotId,
    String? message,
    String? idempotencyKey,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'create_coach_booking_request_v2',
      params: {
        'p_user_id': userId,
        'p_slot_id': slotId,
        'p_message': message,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return res.toString();
  }

  // =============== Enrollments ===============

  /// [policyAccepted] must be true — the consent timestamp and the
  /// cancellation policy snapshot are stored on the enrollment.
  Future<String> createEnrollment({
    required String userId,
    required String offeringId,
    required List<String> sessionIds,
    required bool policyAccepted,
    String? idempotencyKey,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'create_coach_enrollment',
      params: {
        'p_user_id': userId,
        'p_offering_id': offeringId,
        'p_session_ids': sessionIds,
        'p_policy_accepted': policyAccepted,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return res.toString();
  }

  Future<List<CoachEnrollment>> listMyEnrollments(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_coach_enrollments',
      params: {'p_user_id': userId},
    );
    return (res as List)
        .map(
          (e) => CoachEnrollment.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  Future<List<CoachEnrollment>> listEnrollmentsForCoach(
    String userId, {
    List<String>? statuses,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_coach_enrollments_for_coach',
      params: {'p_user_id': userId, 'p_statuses': statuses},
    );
    return (res as List)
        .map(
          (e) => CoachEnrollment.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  Future<void> decideEnrollment(
    String userId,
    String enrollmentId,
    String decision, {
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'decide_coach_enrollment',
      params: {
        'p_user_id': userId,
        'p_enrollment_id': enrollmentId,
        'p_decision': decision,
        'p_reason': reason,
      },
    );
  }

  Future<void> cancelEnrollment(
    String userId,
    String enrollmentId, {
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'cancel_coach_enrollment',
      params: {
        'p_user_id': userId,
        'p_enrollment_id': enrollmentId,
        'p_reason': reason,
      },
    );
  }

  // =============== Schedule-change proposals ===============

  Future<String> proposeSessionChange(
    String userId,
    String sessionId, {
    required DateTime newStartsAt,
    required DateTime newEndsAt,
    String? newLocation,
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'propose_coach_session_change',
      params: {
        'p_user_id': userId,
        'p_session_id': sessionId,
        'p_new_starts_at': newStartsAt.toUtc().toIso8601String(),
        'p_new_ends_at': newEndsAt.toUtc().toIso8601String(),
        'p_new_location': newLocation,
        'p_reason': reason,
      },
    );
    return res.toString();
  }

  Future<void> respondScheduleChange(
    String userId,
    String proposalId, {
    required bool accept,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'respond_coach_schedule_change',
      params: {
        'p_user_id': userId,
        'p_proposal_id': proposalId,
        'p_accept': accept,
      },
    );
  }

  // =============== Sports / availability / service areas ===============

  /// The caller's own sport rows (public RLS allows select; filtered to
  /// the caller's coach id for the management page).
  Future<List<CoachSportRow>> listMyCoachSports(String userId) async {
    _assertCurrentUser(userId);
    final profile = await getMyCoachProfile(userId);
    if (profile == null) return const [];
    final res = await _client
        .from('coach_sports')
        .select()
        .eq('coach_id', profile.id);
    return (res as List)
        .map(
          (e) => CoachSportRow.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  Future<void> setCoachSports(
    String userId,
    List<Map<String, dynamic>> sports,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_coach_sports',
      params: {'p_user_id': userId, 'p_sports': sports},
    );
  }

  Future<void> setCoachAvailability(
    String userId,
    List<Map<String, dynamic>> windows,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_coach_availability',
      params: {'p_user_id': userId, 'p_windows': windows},
    );
  }

  Future<void> setCoachServiceAreas(
    String userId,
    List<Map<String, dynamic>> areas,
  ) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_coach_service_areas',
      params: {'p_user_id': userId, 'p_areas': areas},
    );
  }

  // =============== Admin review ===============

  Future<List<CoachSummary>> listCoachApplications(
    String adminId, {
    String status = 'pending',
  }) async {
    _assertCurrentUser(adminId);
    final res = await _client.rpc(
      'list_coach_applications',
      params: {'p_admin_id': adminId, 'p_status': status},
    );
    return (res as List)
        .map((e) => CoachSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> reviewCoachProfile(
    String adminId,
    String coachId,
    String decision, {
    bool? verified,
    String? reason,
  }) async {
    _assertCurrentUser(adminId);
    await _client.rpc(
      'review_coach_profile',
      params: {
        'p_admin_id': adminId,
        'p_coach_id': coachId,
        'p_decision': decision,
        'p_verified': verified,
        'p_reason': reason,
      },
    );
  }

  // =============== Booking requests ===============

  Future<String> createBookingRequest({
    required String userId,
    required String coachId,
    required String sportId,
    required String teachingMode,
    required DateTime startsAt,
    required DateTime endsAt,
    String? message,
    String? idempotencyKey,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'create_coach_booking_request',
      params: {
        'p_user_id': userId,
        'p_coach_id': coachId,
        'p_sport_id': sportId,
        'p_teaching_mode': teachingMode,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_message': message,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return res.toString();
  }

  Future<void> decideBookingRequest(
    String userId,
    String requestId,
    String decision, {
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'decide_coach_booking_request',
      params: {
        'p_user_id': userId,
        'p_request_id': requestId,
        'p_decision': decision,
        'p_reason': reason,
      },
    );
  }

  Future<void> cancelBookingRequest(
    String userId,
    String requestId, {
    String? reason,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'cancel_coach_booking_request',
      params: {
        'p_user_id': userId,
        'p_request_id': requestId,
        'p_reason': reason,
      },
    );
  }

  Future<List<CoachBookingRequest>> listMyBookingRequests(
    String userId, {
    List<String>? statuses,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_coach_booking_requests',
      params: {'p_user_id': userId, 'p_statuses': statuses},
    );
    return (res as List)
        .map(
          (e) => CoachBookingRequest.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  Future<List<CoachBookingRequest>> listCoachBookingRequestsForCoach(
    String userId, {
    List<String>? statuses,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_coach_booking_requests_for_coach',
      params: {'p_user_id': userId, 'p_statuses': statuses},
    );
    return (res as List)
        .map(
          (e) => CoachBookingRequest.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  // =============== Reviews ===============

  Future<String> submitReview({
    required String userId,
    required String requestId,
    required int rating,
    String? comment,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'submit_coach_review',
      params: {
        'p_user_id': userId,
        'p_request_id': requestId,
        'p_rating': rating,
        'p_comment': comment,
      },
    );
    return res.toString();
  }

  Future<void> moderateReview(
    String adminId,
    String reviewId,
    String action,
  ) async {
    _assertCurrentUser(adminId);
    await _client.rpc(
      'moderate_coach_review',
      params: {
        'p_admin_id': adminId,
        'p_review_id': reviewId,
        'p_action': action,
      },
    );
  }

  // =============== Reviews v2 (1–10, five categories) ===============

  Future<List<CoachReviewCategory>> listReviewCategories() async {
    final res = await _client.rpc('list_coach_review_categories');
    return (res as List)
        .map(
          (e) =>
              CoachReviewCategory.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  Future<List<CoachReviewTag>> listReviewTags() async {
    final res = await _client.rpc('list_coach_review_tags');
    return (res as List)
        .map(
          (e) => CoachReviewTag.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  /// v2 submit: [categoryScores] maps category-id → 1–10; exactly one of
  /// [bookingId] or ([enrollmentId]+[sessionId]) is required.
  Future<String> submitReviewV2({
    required String userId,
    required Map<String, int> categoryScores,
    String? comment,
    List<String>? tagIds,
    List<String>? customTags,
    String? bookingId,
    String? enrollmentId,
    String? sessionId,
  }) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'submit_coach_review_v2',
      params: {
        'p_user_id': userId,
        'p_category_scores': categoryScores,
        'p_comment': comment,
        'p_tag_ids': tagIds,
        'p_custom_tags': customTags,
        'p_booking_id': bookingId,
        'p_enrollment_id': enrollmentId,
        'p_session_id': sessionId,
      },
    );
    return res.toString();
  }

  Future<void> setReviewHelpful(
    String userId,
    String reviewId, {
    required bool helpful,
  }) async {
    _assertCurrentUser(userId);
    await _client.rpc(
      'set_coach_review_helpful',
      params: {
        'p_user_id': userId,
        'p_review_id': reviewId,
        'p_helpful': helpful,
      },
    );
  }

  Future<CoachReviewSummaryV2> getReviewSummaryV2(String coachId) async {
    final res = await _client.rpc(
      'get_coach_review_summary_v2',
      params: {'p_coach_id': coachId},
    );
    return CoachReviewSummaryV2.fromJson(
      Map<String, dynamic>.from(res as Map),
    );
  }

  /// Server-side filtered/sorted/paginated review discovery.
  Future<(List<CoachReview>, int)> listReviewsV2(
    String coachId, {
    String? tagId,
    double? minRating10,
    double? maxRating10,
    String sort = 'helpful',
    int limit = 20,
    int offset = 0,
    String? viewerId,
  }) async {
    final res = await _client.rpc(
      'list_coach_reviews_v2',
      params: {
        'p_coach_id': coachId,
        'p_tag_id': tagId,
        'p_min_rating_10': minRating10,
        'p_max_rating_10': maxRating10,
        'p_sort': sort,
        'p_limit': limit,
        'p_offset': offset,
        'p_viewer_id': viewerId,
      },
    );
    final rows = (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final total = rows.isEmpty
        ? 0
        : (rows.first['total_count'] as num?)?.toInt() ?? rows.length;
    return (
      rows.map(CoachReview.fromJson).toList(),
      total,
    );
  }

  /// Completed bookings / enrollment sessions the caller can review.
  Future<({Set<String> bookingIds, Set<String> sessionIds})>
      listMyReviewableIds(String userId) async {
    _assertCurrentUser(userId);
    final res = await _client.rpc(
      'list_my_coach_reviewable_ids',
      params: {'p_user_id': userId},
    );
    final j = Map<String, dynamic>.from(res as Map);
    return (
      bookingIds:
          (j['bookingIds'] as List?)?.map((e) => e.toString()).toSet() ??
              const {},
      sessionIds: ((j['enrollmentSessions'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((e) =>
              '${e['enrollmentId']}:${e['sessionId']}')
          .toSet(),
    );
  }
}
