import 'package:supabase_flutter/supabase_flutter.dart';

class FitnessBuddiesRepository {
  final SupabaseClient _client;
  FitnessBuddiesRepository(this._client);

  /// Thai consonants in dictionary order (ก → ฮ)
  static const _thaiConsonants = 'กขฃคฅฆงจฉชซฌญฎฏฐฑฒณดตถทธนบปผฝพฟภมยรลวศษสหฬอฮ';

  /// Leading vowels that appear before the first consonant in Thai
  static const _thaiLeadingVowels = 'เแโใไ';

  /// Returns the index of the first *consonant* in [text] within the Thai
  /// consonant alphabet. Leading vowels (เ แ โ ใ ไ) are skipped so that
  /// "แฮนด์บอล" sorts by "ฮ", not "แ". Returns -1 when no consonant is found.
  static int _thaiFirstConsonantIndex(String text) {
    for (final ch in text.runes) {
      final c = String.fromCharCode(ch);
      if (_thaiLeadingVowels.contains(c)) continue;
      final idx = _thaiConsonants.indexOf(c);
      if (idx >= 0) return idx;
      // Non-Thai/non-consonant char — break so we don't skip past real content
      break;
    }
    return -1;
  }

  /// Comparator that sorts Thai sport names by first consonant, ascending
  /// (ก → ฮ). Falls back to plain string comparison for non-Thai or when
  /// no consonant is found.
  static int _compareThaiAsc(String a, String b) {
    final ia = _thaiFirstConsonantIndex(a);
    final ib = _thaiFirstConsonantIndex(b);
    if (ia >= 0 && ib >= 0) {
      final cmp = ia.compareTo(ib); // ascending
      if (cmp != 0) return cmp;
    }
    // Tie-break: full string ascending
    return a.compareTo(b);
  }

  /// Returns a map of sport_id → usage count for [userId], counting both
  /// groups the user created and groups they joined as a member.
  Future<Map<String, int>> getUserSportFrequency(String userId) async {
    final memberRows = await _client
        .from('fitness_group_members')
        .select('group_id')
        .eq('user_id', userId)
        .eq('is_active', true);
    final memberGroupIds = (memberRows as List)
        .map((e) => e['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    final createdRows = await _client
        .from('fitness_groups')
        .select('id')
        .eq('created_by', userId);
    final createdGroupIds = (createdRows as List)
        .map((e) => e['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    final allGroupIds = <String>{...memberGroupIds, ...createdGroupIds};
    if (allGroupIds.isEmpty) return {};

    final groupRows = await _client
        .from('fitness_groups')
        .select('sport_id')
        .inFilter('id', allGroupIds.toList());

    final freq = <String, int>{};
    for (final row in groupRows as List) {
      final sportId = row['sport_id']?.toString();
      if (sportId != null && sportId.isNotEmpty) {
        freq[sportId] = (freq[sportId] ?? 0) + 1;
      }
    }
    return freq;
  }

  /// Fetches approved sports sorted by:
  /// 1. Sports the user has used (created/joined groups), by frequency desc
  /// 2. Remaining sports by Thai first-consonant ascending (ก → ฮ)
  /// When [userId] is null or empty, all sports are sorted by ก → ฮ only.
  Future<List<Map<String, dynamic>>> getApprovedSports({String? userId}) async {
    final res = await _client.from('sports').select('*').eq('status', 'approved').order('name_th');
    final list = List<Map<String, dynamic>>.from(res);

    Map<String, int> freq = {};
    if (userId != null && userId.isNotEmpty) {
      freq = await getUserSportFrequency(userId);
    }

    list.sort((a, b) {
      final aId = a['id']?.toString() ?? '';
      final bId = b['id']?.toString() ?? '';
      final aFreq = freq[aId] ?? 0;
      final bFreq = freq[bId] ?? 0;
      final aUsed = aFreq > 0;
      final bUsed = bFreq > 0;

      // Used sports first
      if (aUsed && !bUsed) return -1;
      if (!aUsed && bUsed) return 1;

      // Within used group: sort by frequency desc
      if (aUsed && bUsed) {
        final cmp = bFreq.compareTo(aFreq);
        if (cmp != 0) return cmp;
      }

      // Within same group (or both unused): sort by ก → ฮ
      return _compareThaiAsc(
        a['name_th']?.toString() ?? '',
        b['name_th']?.toString() ?? '',
      );
    });

    return list;
  }

  Future<Set<String>> listMyAdminGroupIds(String userId) async {
    final res = await _client
        .from('fitness_group_members')
        .select('group_id')
        .eq('user_id', userId)
        .eq('role', 'admin')
        .eq('is_active', true);
    return (res as List)
        .map((e) => e['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<List<Map<String, dynamic>>> listGroups({String? sportId, String? q, String? province, String? district, String? currentUserId, int limit = 50, int offset = 0}) async {
    final base = _client.from('fitness_groups').select('*, sport:sports(name_th, icon)');
    var query = base;
    if (sportId != null && sportId.isNotEmpty) query = query.eq('sport_id', sportId);
    if (province != null && province.isNotEmpty) query = query.eq('province', province);
    if (district != null && district.isNotEmpty) query = query.eq('district', district);
    if (q != null && q.isNotEmpty) query = query.ilike('name', '%$q%');
    if (currentUserId == null || currentUserId.isEmpty) {
      query = query.eq('visibility', 'public');
    } else {
      final ids = await _client
          .from('fitness_group_members')
          .select('group_id')
          .eq('user_id', currentUserId)
          .eq('is_active', true);
      final memberGroupIds = List<String>.from((ids as List).map((e) => e['group_id'].toString()));
      if (memberGroupIds.isEmpty) {
        query = query.eq('visibility', 'public');
      } else {
        final quoted = memberGroupIds.map((e) => '"$e"').join(',');
        query = query.or('visibility.eq.public,id.in.($quoted)');
      }
    }

    final res = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
    final groups = List<Map<String, dynamic>>.from(res);
    
    // Add member count for each group
    for (var group in groups) {
      final groupId = group['id']?.toString();
      if (groupId != null) {
        final countRes = await _client
            .from('fitness_group_members')
            .select('user_id')
            .eq('group_id', groupId)
            .eq('is_active', true);
        group['member_count'] = (countRes as List).length;
        group['sport_name'] = group['sport']?['name_th'];
        group['sport_icon'] = group['sport']?['icon'];
      }
    }
    
    return groups;
  }

  Future<List<Map<String, dynamic>>> listUpcomingSessions(String groupId, {DateTime? from, int limit = 20}) async {
    final nowIso = (from ?? DateTime.now()).toUtc().toIso8601String();
    final res = await _client
        .from('fitness_group_sessions')
        .select('*')
        .eq('group_id', groupId)
        .gte('ends_at', nowIso)
        .order('starts_at', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<String> bookSession(String sessionId, String userId) async {
    final result = await _client.rpc('book_fitness_session', params: {
      'p_session_id': sessionId,
      'p_user_id': userId,
    });
    if (result is String) return result;
    if (result is Map && result['book_fitness_session'] is String) return result['book_fitness_session'] as String;
    throw Exception('ไม่สามารถจองรอบได้');
  }

  Future<Map<String, dynamic>?> getBookingDetail(String bookingId, {required String userId}) async {
    final res = await _client
        .from('fitness_group_bookings')
        .select('*, session:fitness_group_sessions(*, group:fitness_groups(*))')
        .eq('id', bookingId)
        .eq('user_id', userId)
        .maybeSingle();
    if (res == null) return null;
    return Map<String, dynamic>.from(res);
  }

  Future<void> cancelBooking(String bookingId, String userId, {String? reason}) async {
    await _client
        .from('fitness_group_bookings')
        .update({
          'status': 'cancelled',
          'cancelled_at': DateTime.now().toIso8601String(),
          'cancelled_by': 'user',
          'cancel_reason': reason ?? 'user_cancelled',
        })
        .eq('id', bookingId)
        .eq('user_id', userId);
  }

  Future<String> createGroup({
    required String userId,
    required String name,
    String? sportId,
    String? description,
    String visibility = 'public',
    bool requiresOwnerApproval = false,
    int capacity = 5,
    String? coverImageUrl,
    String? venuePhotoUrl,
    String genderPreference = 'any',
    String? province,
    String? district,
    double? lat,
    double? lng,
  }) async {
    final data = {
      'name': name,
      if (sportId != null) 'sport_id': sportId,
      if (description != null) 'description': description,
      'visibility': visibility,
      'requires_owner_approval': requiresOwnerApproval,
      'capacity': capacity,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      if (venuePhotoUrl != null) 'venue_photo_url': venuePhotoUrl,
      'gender_preference': genderPreference,
      if (province != null) 'province': province,
      if (district != null) 'district': district,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'created_by': userId,
    };
    final res = await _client.from('fitness_groups').insert(data).select('id').single();
    return res['id'].toString();
  }

  Future<String> createSession({
    required String groupId,
    required DateTime startsAt,
    required DateTime endsAt,
    String? placeName,
    double? lat,
    double? lng,
    String? note,
  }) async {
    final data = {
      'group_id': groupId,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      if (placeName != null) 'place_name': placeName,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (note != null) 'note': note,
    };
    final res = await _client.from('fitness_group_sessions').insert(data).select('id').single();
    return res['id'].toString();
  }

  Future<String> proposeSport({
    required String nameTh,
    String? nameEn,
    required String proposedBy,
  }) async {
    final data = {
      'name_th': nameTh,
      if (nameEn != null && nameEn.isNotEmpty) 'name_en': nameEn,
      'status': 'proposed',
      'proposed_by': proposedBy,
    };
    final res = await _client.from('sports').insert(data).select('id').single();
    return res['id'].toString();
  }

  Future<List<Map<String, dynamic>>> listProposedSports() async {
    final res = await _client.from('sports').select('*').eq('status', 'proposed').order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> approveSport({required String sportId, required String reviewedBy, String? icon}) async {
    await _client
        .from('sports')
        .update({
          'status': 'approved',
          'reviewed_by': reviewedBy,
          'rejection_reason': null,
          if (icon != null && icon.isNotEmpty) 'icon': icon,
        })
        .eq('id', sportId)
        .eq('status', 'proposed');
  }

  Future<void> rejectSport({required String sportId, required String reviewedBy, required String reason}) async {
    await _client
        .from('sports')
        .update({
          'status': 'rejected',
          'reviewed_by': reviewedBy,
          'rejection_reason': reason,
        })
        .eq('id', sportId)
        .eq('status', 'proposed');
  }
}
