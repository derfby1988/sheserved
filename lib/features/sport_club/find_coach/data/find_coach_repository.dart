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

    final ratingByCoach = <String, (double, int)>{};
    for (final row in (results[2] as List)) {
      final m = Map<String, dynamic>.from(row);
      ratingByCoach[m['coach_id']?.toString() ?? ''] = (
        (m['average_rating'] as num?)?.toDouble() ?? 0,
        (m['review_count'] as num?)?.toInt() ?? 0,
      );
    }

    return coaches
        .map(
          (c) => c.copyWith(
            sportIds: sportsByCoach[c.id] ?? const {},
            skillLevels: levelsByCoach[c.id] ?? const {},
            specialties: specialtiesByCoach[c.id] ?? const [],
            serviceAreas: areasByCoach[c.id] ?? const [],
            averageRating: ratingByCoach[c.id]?.$1,
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
      },
    );
    return res.toString();
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
}
