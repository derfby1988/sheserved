import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/websocket_service.dart';

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
    final res = await _client
        .from('sports')
        .select('*')
        .eq('status', 'approved')
        .order('name_th');
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

  Future<Set<String>> listMyJoinedGroupIds(String userId) async {
    final results = await Future.wait([
      _client
          .from('fitness_group_members')
          .select('group_id, role')
          .eq('user_id', userId)
          .eq('is_active', true),
      _client
          .from('fitness_group_blocklist')
          .select('group_id')
          .eq('blocked_user_id', userId)
          .eq('is_active', true),
      _client
          .from('fitness_group_bookings')
          .select('session:fitness_group_sessions!inner(group_id)')
          .eq('user_id', userId)
          .eq('status', 'confirmed'),
    ]);
    final blockedGroupIds = (results[1] as List)
        .map((e) => e['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final confirmedGroupIds = (results[2] as List)
        .map((row) {
          final session = (row['session'] as Map?) ?? {};
          return session['group_id']?.toString() ?? '';
        })
        .where((id) => id.isNotEmpty)
        .toSet();
    return (results[0] as List)
        .where((member) {
          final groupId = member['group_id']?.toString() ?? '';
          final isAdmin = member['role']?.toString() == 'admin';
          return groupId.isNotEmpty &&
              !blockedGroupIds.contains(groupId) &&
              (isAdmin || confirmedGroupIds.contains(groupId));
        })
        .map((member) => member['group_id']?.toString() ?? '')
        .toSet();
  }

  /// Returns group IDs where [userId] is actively blocked.
  Future<Set<String>> listMyBlockedGroupIds(String userId) async {
    final res = await _client
        .from('fitness_group_blocklist')
        .select('group_id')
        .eq('blocked_user_id', userId)
        .eq('is_active', true);
    return (res as List)
        .map((row) => row['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// Returns group IDs where [userId] has at least one pending booking.
  Future<Set<String>> listMyPendingGroupIds(String userId) async {
    final results = await Future.wait([
      _client
          .from('fitness_group_bookings')
          .select('session:fitness_group_sessions!inner(group_id)')
          .eq('user_id', userId)
          .eq('status', 'pending'),
      _client
          .from('fitness_group_blocklist')
          .select('group_id')
          .eq('blocked_user_id', userId)
          .eq('is_active', true),
    ]);
    final blockedGroupIds = (results[1] as List)
        .map((e) => e['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    return (results[0] as List)
        .map((r) {
          final session = (r['session'] as Map?) ?? {};
          return session['group_id']?.toString() ?? '';
        })
        .where((id) => id.isNotEmpty && !blockedGroupIds.contains(id))
        .toSet();
  }

  Future<Set<String>> listMyCreatedSportIds(String userId) async {
    final res = await _client
        .from('fitness_groups')
        .select('sport_id')
        .eq('created_by', userId);
    return (res as List)
        .map((e) => e['sport_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<List<Map<String, dynamic>>> listGroups({
    String? sportId,
    String? q,
    String? province,
    String? district,
    bool openOnly = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final base = _client.from('fitness_groups').select('*');
    var query = base;
    if (sportId != null && sportId.isNotEmpty)
      query = query.eq('sport_id', sportId);
    if (province != null && province.isNotEmpty)
      query = query.eq('province', province);
    if (district != null && district.isNotEmpty)
      query = query.eq('district', district);
    if (q != null && q.isNotEmpty) query = query.ilike('name', '%$q%');
    // ทุกก๊วน (รวมก๊วนส่วนตัว) แสดงในรายการเปิดรับ; openOnly = เฉพาะก๊วนที่เข้าร่วมได้ทันที
    if (openOnly) {
      query = query.eq('requires_owner_approval', false);
    }

    final res = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    final groups = List<Map<String, dynamic>>.from(res);

    // Batch fetch all sports referenced by groups in a single query
    final sportIds = groups
        .map((g) => g['sport_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    final sportsMap = <String, Map<String, dynamic>>{};
    if (sportIds.isNotEmpty) {
      final sportsRes = await _client
          .from('sports')
          .select('id, name_th, icon')
          .inFilter('id', sportIds.toList());
      for (final s in sportsRes as List) {
        final id = s['id']?.toString();
        if (id != null) {
          sportsMap[id] = Map<String, dynamic>.from(s);
        }
      }
    }

    // Add member count and attach sport data for each group
    for (var group in groups) {
      final groupId = group['id']?.toString();
      if (groupId != null) {
        final countResults = await Future.wait([
          _client
              .from('fitness_group_members')
              .select('user_id, role')
              .eq('group_id', groupId)
              .eq('is_active', true),
          _client
              .from('fitness_group_blocklist')
              .select('blocked_user_id')
              .eq('group_id', groupId)
              .eq('is_active', true),
          _client
              .from('fitness_group_bookings')
              .select('user_id, session:fitness_group_sessions!inner(group_id)')
              .eq('session.group_id', groupId)
              .eq('status', 'confirmed'),
        ]);
        final blockedUserIds = (countResults[1] as List)
            .map((e) => e['blocked_user_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        final confirmedUserIds = (countResults[2] as List)
            .map((booking) => booking['user_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        group['member_count'] = (countResults[0] as List).where((member) {
          final userId = member['user_id']?.toString() ?? '';
          final isAdmin = member['role']?.toString() == 'admin';
          return !blockedUserIds.contains(userId) &&
              (isAdmin || confirmedUserIds.contains(userId));
        }).length;
      }
      final sid = group['sport_id']?.toString();
      final sport = sportsMap[sid];
      group['sport_name'] = sport?['name_th']?.toString();
      group['sport_icon'] = sport?['icon']?.toString();
    }

    return groups;
  }

  Future<List<Map<String, dynamic>>> listUpcomingSessions(
    String groupId, {
    DateTime? from,
    int limit = 20,
  }) async {
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

  /// Returns a set of group IDs (from [groupIds]) that have at least one
  /// upcoming session (ends_at >= now). Uses a single query for efficiency.
  Future<Set<String>> filterGroupIdsWithUpcomingSessions(
    List<String> groupIds, {
    DateTime? from,
  }) async {
    if (groupIds.isEmpty) return {};
    final nowIso = (from ?? DateTime.now()).toUtc().toIso8601String();
    final res = await _client
        .from('fitness_group_sessions')
        .select('group_id')
        .inFilter('group_id', groupIds)
        .gte('ends_at', nowIso);
    return (res as List)
        .map((e) => e['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<List<Map<String, dynamic>>> listSessions(
    String groupId, {
    int limit = 50,
  }) async {
    final res = await _client
        .from('fitness_group_sessions')
        .select('*')
        .eq('group_id', groupId)
        .order('starts_at', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> listGroupMembers(String groupId) async {
    final results = await Future.wait([
      _client
          .from('fitness_group_members')
          .select(
            '*, user:users(id, first_name, last_name, profile_image_url, is_active, verification_status)',
          )
          .eq('group_id', groupId)
          .eq('is_active', true)
          .order('joined_at', ascending: false),
      _client
          .from('fitness_group_blocklist')
          .select('blocked_user_id')
          .eq('group_id', groupId)
          .eq('is_active', true),
      _client
          .from('fitness_group_bookings')
          .select('user_id, session:fitness_group_sessions!inner(group_id)')
          .eq('session.group_id', groupId)
          .eq('status', 'confirmed'),
    ]);
    final blockedUserIds = (results[1] as List)
        .map((e) => e['blocked_user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final confirmedUserIds = (results[2] as List)
        .map((booking) => booking['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    return (results[0] as List)
        .map((e) {
          final member = Map<String, dynamic>.from(e);
          final userData = member['user'];
          if (userData is List && userData.isNotEmpty) {
            member['user'] = userData.first;
          } else if (userData is Map) {
            member['user'] = userData;
          } else {
            member['user'] = <String, dynamic>{};
          }
          return member;
        })
        .where((member) {
          final memberUserId = member['user_id']?.toString() ?? '';
          final isAdmin = member['role']?.toString() == 'admin';
          return !blockedUserIds.contains(memberUserId) &&
              (isAdmin || confirmedUserIds.contains(memberUserId));
        })
        .toList();
  }

  Future<Map<String, dynamic>?> _getSessionWithGroup(String sessionId) async {
    final res = await _client
        .from('fitness_group_sessions')
        .select(
          'id, group_id, starts_at, ends_at, place_name, group:fitness_groups(id, name, created_by)',
        )
        .eq('id', sessionId)
        .maybeSingle();
    if (res == null) return null;
    return Map<String, dynamic>.from(res);
  }

  Future<List<String>> _getGroupAdminUserIds(
    String groupId, {
    String? fallbackUserId,
  }) async {
    final res = await _client
        .from('fitness_group_members')
        .select('user_id, role, is_active')
        .eq('group_id', groupId)
        .eq('is_active', true);

    final adminIds = (res as List)
        .where((row) => row['role']?.toString() == 'admin')
        .map((row) => row['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (fallbackUserId != null && fallbackUserId.isNotEmpty) {
      adminIds.add(fallbackUserId);
    }

    return adminIds.toSet().toList();
  }

  Future<String> _getUserDisplayName(String userId) async {
    final res = await _client
        .from('users')
        .select('first_name, last_name')
        .eq('id', userId)
        .maybeSingle();

    if (res == null) return 'ผู้ใช้';

    final firstName = (res['first_name']?.toString() ?? '').trim();
    final lastName = (res['last_name']?.toString() ?? '').trim();
    final fullName = '$firstName $lastName'.trim();
    return fullName.isNotEmpty ? fullName : 'ผู้ใช้';
  }

  void _emitFitnessBookingStatus({
    required List<String> recipientUserIds,
    required String bookingId,
    required String sessionId,
    required String groupId,
    required String groupName,
    required String status,
    required String message,
    String? requesterId,
    String? requesterName,
    String? reason,
  }) {
    final socket = WebSocketService().socket;
    if (socket == null || recipientUserIds.isEmpty) return;

    for (final recipientUserId in recipientUserIds.toSet()) {
      socket.emit('fitness_booking_status', {
        'userId': recipientUserId,
        'bookingId': bookingId,
        'booking_id': bookingId,
        'sessionId': sessionId,
        'session_id': sessionId,
        'groupId': groupId,
        'group_id': groupId,
        'groupName': groupName,
        'group_name': groupName,
        'status': status,
        'message': message,
        if (requesterId != null) 'requesterUserId': requesterId,
        if (requesterId != null) 'requester_user_id': requesterId,
        if (requesterName != null) 'requesterName': requesterName,
        if (requesterName != null) 'requester_name': requesterName,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
    }
  }

  Future<void> cancelSession(String sessionId) async {
    await _client.from('fitness_group_sessions').delete().eq('id', sessionId);
  }

  Future<String> bookSession(String sessionId, String userId) async {
    final result = await _client.rpc(
      'book_fitness_session',
      params: {'p_session_id': sessionId, 'p_user_id': userId},
    );
    final bookingId = result is String
        ? result
        : (result is Map && result['book_fitness_session'] is String
              ? result['book_fitness_session'] as String
              : null);
    if (bookingId != null) {
      final session = await _getSessionWithGroup(sessionId);
      if (session != null) {
        final groupId = session['group_id']?.toString() ?? '';
        final group = session['group'];
        final groupName = group is Map
            ? (group['name']?.toString() ?? 'ก๊วนกีฬา')
            : 'ก๊วนกีฬา';
        final groupCreatedBy = group is Map
            ? group['created_by']?.toString()
            : null;
        final requesterName = await _getUserDisplayName(userId);
        final recipientUserIds = await _getGroupAdminUserIds(
          groupId,
          fallbackUserId: groupCreatedBy,
        );
        _emitFitnessBookingStatus(
          recipientUserIds: recipientUserIds,
          bookingId: bookingId,
          sessionId: sessionId,
          groupId: groupId,
          groupName: groupName,
          status: 'pending',
          message: 'มีคำขอเข้าร่วมก๊วนใหม่',
          requesterId: userId,
          requesterName: requesterName,
        );
      }
      return bookingId;
    }
    throw Exception('ไม่สามารถจองรอบได้');
  }

  Future<Map<String, dynamic>?> getBookingDetail(
    String bookingId, {
    required String userId,
  }) async {
    final res = await _client
        .from('fitness_group_bookings')
        .select('*, session:fitness_group_sessions(*, group:fitness_groups(*))')
        .eq('id', bookingId)
        .eq('user_id', userId)
        .maybeSingle();
    if (res == null) return null;
    return Map<String, dynamic>.from(res);
  }

  /// Check if [userId] has any pending bookings for sessions in [groupId].
  /// Returns the list of pending booking rows (empty if none).
  Future<List<Map<String, dynamic>>> listMyPendingBookingsForGroup(
    String groupId,
    String userId,
  ) async {
    final res = await _client
        .from('fitness_group_bookings')
        .select(
          'id, status, session_id, session:fitness_group_sessions!inner(group_id)',
        )
        .eq('user_id', userId)
        .eq('status', 'pending')
        .eq('session.group_id', groupId);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> cancelBooking(
    String bookingId,
    String userId, {
    String? reason,
  }) async {
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

  /// List bookings for a given session (both pending and confirmed),
  /// including basic user profile fields for display.
  Future<List<Map<String, dynamic>>> listSessionBookings(
    String sessionId,
  ) async {
    final res = await _client
        .from('fitness_group_bookings')
        .select(
          '*, user:users(first_name, last_name, profile_image_url), session:fitness_group_sessions(ends_at)',
        )
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
    return (res as List).map((e) {
      final b = Map<String, dynamic>.from(e);
      final userData = b['user'];
      if (userData is List && userData.isNotEmpty) {
        b['user'] = userData.first;
      } else if (userData is Map) {
        b['user'] = userData;
      } else {
        b['user'] = <String, dynamic>{};
      }
      return b;
    }).toList();
  }

  /// Approve a pending booking (owner action) via RPC with server-side overlap validation.
  Future<void> approveBooking({
    required String bookingId,
    required String ownerId,
  }) async {
    await _client.rpc(
      'approve_fitness_session_booking',
      params: {'p_booking_id': bookingId, 'p_owner_id': ownerId},
    );

    final booking = await _client
        .from('fitness_group_bookings')
        .select(
          'user_id, session_id, session:fitness_group_sessions(id, group_id, group:fitness_groups(id, name, created_by))',
        )
        .eq('id', bookingId)
        .maybeSingle();

    if (booking == null) return;

    final requesterId = booking['user_id']?.toString();
    final session = booking['session'];
    final sessionId = booking['session_id']?.toString() ?? '';
    if (requesterId == null || requesterId.isEmpty || session is! Map) return;

    final group = session['group'];
    final groupId = session['group_id']?.toString() ?? '';
    final groupName = group is Map
        ? (group['name']?.toString() ?? 'ก๊วนกีฬา')
        : 'ก๊วนกีฬา';
    final requesterName = await _getUserDisplayName(requesterId);
    _emitFitnessBookingStatus(
      recipientUserIds: [requesterId],
      bookingId: bookingId,
      sessionId: sessionId,
      groupId: groupId,
      groupName: groupName,
      status: 'confirmed',
      message: 'คำขอเข้าร่วมก๊วนของคุณได้รับการอนุมัติแล้ว',
      requesterId: ownerId,
      requesterName: requesterName,
    );
  }

  /// Reject a pending booking (owner action). Minimal update: set status to 'rejected'.
  /// Optionally records a cancel_reason with cancelled_by='owner' for audit consistency.
  Future<void> rejectBooking({
    required String bookingId,
    required String ownerId,
    String? reason,
  }) async {
    await _client
        .from('fitness_group_bookings')
        .update({
          'status': 'rejected',
          'cancelled_by': 'owner',
          if (reason != null && reason.isNotEmpty) 'cancel_reason': reason,
        })
        .eq('id', bookingId)
        .eq('status', 'pending');

    final booking = await _client
        .from('fitness_group_bookings')
        .select(
          'user_id, session_id, session:fitness_group_sessions(id, group_id, group:fitness_groups(id, name, created_by))',
        )
        .eq('id', bookingId)
        .maybeSingle();

    if (booking == null) return;

    final requesterId = booking['user_id']?.toString();
    final session = booking['session'];
    final sessionId = booking['session_id']?.toString() ?? '';
    if (requesterId == null || requesterId.isEmpty || session is! Map) return;

    final group = session['group'];
    final groupId = session['group_id']?.toString() ?? '';
    final groupName = group is Map
        ? (group['name']?.toString() ?? 'ก๊วนกีฬา')
        : 'ก๊วนกีฬา';
    final requesterName = await _getUserDisplayName(requesterId);
    _emitFitnessBookingStatus(
      recipientUserIds: [requesterId],
      bookingId: bookingId,
      sessionId: sessionId,
      groupId: groupId,
      groupName: groupName,
      status: 'rejected',
      message: 'คำขอเข้าร่วมก๊วนของคุณถูกปฏิเสธ',
      requesterId: ownerId,
      requesterName: requesterName,
      reason: reason,
    );
  }

  Future<String> createGroup({
    required String userId,
    required String name,
    String? sportId,
    String? description,
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
    final res = await _client
        .from('fitness_groups')
        .insert(data)
        .select('id')
        .single();
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
    final res = await _client
        .from('fitness_group_sessions')
        .insert(data)
        .select('id')
        .single();
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
    final res = await _client
        .from('sports')
        .select('*')
        .eq('status', 'proposed')
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> approveSport({
    required String sportId,
    required String reviewedBy,
    String? icon,
  }) async {
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

  Future<void> rejectSport({
    required String sportId,
    required String reviewedBy,
    required String reason,
  }) async {
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

  // ── Phase 4: Update group ──
  Future<void> updateGroup({
    required String groupId,
    required String userId,
    String? name,
    String? description,
    bool? requiresOwnerApproval,
    int? capacity,
    String? coverImageUrl,
    String? venuePhotoUrl,
    String? genderPreference,
    String? province,
    String? district,
    double? lat,
    double? lng,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (requiresOwnerApproval != null)
      data['requires_owner_approval'] = requiresOwnerApproval;
    if (capacity != null) data['capacity'] = capacity;
    if (coverImageUrl != null) data['cover_image_url'] = coverImageUrl;
    if (venuePhotoUrl != null) data['venue_photo_url'] = venuePhotoUrl;
    if (genderPreference != null) data['gender_preference'] = genderPreference;
    if (province != null) data['province'] = province;
    if (district != null) data['district'] = district;
    if (lat != null) data['lat'] = lat;
    if (lng != null) data['lng'] = lng;
    if (data.isEmpty) return;
    await _client
        .from('fitness_groups')
        .update(data)
        .eq('id', groupId)
        .eq('created_by', userId);
  }

  // ── Phase 4: Update session ──
  Future<void> updateSession({
    required String sessionId,
    DateTime? startsAt,
    DateTime? endsAt,
    String? placeName,
    double? lat,
    double? lng,
    String? note,
  }) async {
    final data = <String, dynamic>{};
    if (startsAt != null)
      data['starts_at'] = startsAt.toUtc().toIso8601String();
    if (endsAt != null) data['ends_at'] = endsAt.toUtc().toIso8601String();
    if (placeName != null) data['place_name'] = placeName;
    if (lat != null) data['lat'] = lat;
    if (lng != null) data['lng'] = lng;
    if (note != null) data['note'] = note;
    if (data.isEmpty) return;
    await _client
        .from('fitness_group_sessions')
        .update(data)
        .eq('id', sessionId);
  }

  // ── Phase 4: Leave group (RPC for atomic cascade) ──
  Future<void> leaveGroup({
    required String groupId,
    required String userId,
  }) async {
    await _client.rpc(
      'leave_fitness_group',
      params: {'p_group_id': groupId, 'p_user_id': userId},
    );
  }

  // ── Phase 4: Blocklist (per-group; table: fitness_group_blocklist) ──
  Future<void> blockUser({
    required String groupId,
    required String blockedUserId,
    required String blockedBy,
    String? reason,
  }) async {
    await _client.from('fitness_group_blocklist').upsert({
      'group_id': groupId,
      'blocked_user_id': blockedUserId,
      'blocked_by': blockedBy,
      'is_active': true,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'group_id,blocked_user_id');
    await leaveGroup(groupId: groupId, userId: blockedUserId);
  }

  Future<Map<String, int>?> getUnblockCapacityStatus({
    required String groupId,
    required String requesterUserId,
  }) async {
    final accessResults = await Future.wait([
      _client
          .from('fitness_groups')
          .select('created_by, capacity')
          .eq('id', groupId)
          .maybeSingle(),
      _client
          .from('users')
          .select('role')
          .eq('id', requesterUserId)
          .maybeSingle(),
    ]);
    final group = accessResults[0];
    final groupOwnerId = group?['created_by']?.toString();
    final requesterRole = accessResults[1]?['role']?.toString();
    if (group == null ||
        (groupOwnerId != requesterUserId && requesterRole != 'admin')) {
      return null;
    }
    final members = await listGroupMembers(groupId);
    return {
      'capacity': (group['capacity'] as num?)?.toInt() ?? 0,
      'member_count': members.length,
    };
  }

  Future<void> unblockUser({
    required String groupId,
    required String blockedUserId,
  }) async {
    await _client
        .from('fitness_group_blocklist')
        .delete()
        .eq('group_id', groupId)
        .eq('blocked_user_id', blockedUserId);
  }

  Future<List<Map<String, dynamic>>> listBlockedUsers(
    String groupId, {
    required String requesterUserId,
  }) async {
    final accessResults = await Future.wait([
      _client
          .from('fitness_groups')
          .select('created_by')
          .eq('id', groupId)
          .maybeSingle(),
      _client
          .from('users')
          .select('role')
          .eq('id', requesterUserId)
          .maybeSingle(),
    ]);
    final groupOwnerId = accessResults[0]?['created_by']?.toString();
    final requesterRole = accessResults[1]?['role']?.toString();
    if (groupOwnerId != requesterUserId && requesterRole != 'admin') return [];

    final res = await _client
        .from('fitness_group_blocklist')
        .select(
          'blocked_user_id, reason, created_at, blocked_user:users!fitness_group_blocklist_blocked_user_id_fkey(first_name, last_name, profile_image_url)',
        )
        .eq('group_id', groupId)
        .eq('is_active', true)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<bool> isUserBlocked({
    required String groupId,
    required String targetUserId,
  }) async {
    final res = await _client
        .from('fitness_group_blocklist')
        .select('group_id')
        .eq('group_id', groupId)
        .eq('blocked_user_id', targetUserId)
        .eq('is_active', true)
        .maybeSingle();
    return res != null;
  }

  // ── Phase 8: List pending bookings for a group (all sessions) ──
  Future<List<Map<String, dynamic>>> listGroupPendingBookings(
    String groupId,
  ) async {
    final results = await Future.wait([
      _client
          .from('fitness_group_bookings')
          .select(
            'id, created_at, user:users!fitness_group_bookings_user_id_fkey(first_name, last_name, profile_image_url, id), session:fitness_group_sessions!inner(id, group_id, starts_at, ends_at)',
          )
          .eq('session.group_id', groupId)
          .eq('status', 'pending')
          .order('created_at', ascending: true),
      _client
          .from('fitness_group_blocklist')
          .select('blocked_user_id')
          .eq('group_id', groupId)
          .eq('is_active', true),
    ]);
    final blockedUserIds = (results[1] as List)
        .map((e) => e['blocked_user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    return (results[0] as List)
        .map((e) {
          final b = Map<String, dynamic>.from(e);
          final userData = b['user'];
          if (userData is List && userData.isNotEmpty) {
            b['user'] = userData.first;
          } else if (userData is Map) {
            b['user'] = userData;
          } else {
            b['user'] = <String, dynamic>{};
          }
          return b;
        })
        .where((booking) {
          final user = booking['user'];
          final userId = user is Map ? user['id']?.toString() ?? '' : '';
          return !blockedUserIds.contains(userId);
        })
        .toList();
  }

  // ── Phase 3: Check group membership ──
  Future<bool> isGroupMember({
    required String groupId,
    required String userId,
  }) async {
    final results = await Future.wait([
      _client
          .from('fitness_group_members')
          .select('user_id, role')
          .eq('group_id', groupId)
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle(),
      _client
          .from('fitness_group_blocklist')
          .select('blocked_user_id')
          .eq('group_id', groupId)
          .eq('blocked_user_id', userId)
          .eq('is_active', true)
          .maybeSingle(),
      _client
          .from('fitness_group_bookings')
          .select('id, session:fitness_group_sessions!inner(group_id)')
          .eq('user_id', userId)
          .eq('session.group_id', groupId)
          .eq('status', 'confirmed')
          .limit(1)
          .maybeSingle(),
    ]);
    final member = results[0];
    final isAdmin = member?['role']?.toString() == 'admin';
    return member != null &&
        results[1] == null &&
        (isAdmin || results[2] != null);
  }

  // ── Phase 4: List my groups (created + joined) with booking history ──
  Future<List<Map<String, dynamic>>> listMyGroups(String userId) async {
    final results = await Future.wait([
      _client
          .from('fitness_group_members')
          .select('group_id, role, joined_at, is_active')
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('joined_at', ascending: false),
      _client
          .from('fitness_group_bookings')
          .select('session:fitness_group_sessions!inner(group_id)')
          .eq('user_id', userId)
          .eq('status', 'confirmed'),
      _client
          .from('fitness_group_blocklist')
          .select('group_id')
          .eq('blocked_user_id', userId)
          .eq('is_active', true),
    ]);
    final confirmedGroupIds = (results[1] as List)
        .map((row) {
          final session = (row['session'] as Map?) ?? {};
          return session['group_id']?.toString() ?? '';
        })
        .where((id) => id.isNotEmpty)
        .toSet();
    final blockedGroupIds = (results[2] as List)
        .map((row) => row['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final memberRows = (results[0] as List).where((member) {
      final groupId = member['group_id']?.toString() ?? '';
      final isAdmin = member['role']?.toString() == 'admin';
      return !blockedGroupIds.contains(groupId) &&
          (isAdmin || confirmedGroupIds.contains(groupId));
    }).toList();
    final groupIds = memberRows
        .map((e) => e['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (groupIds.isEmpty) return [];

    final groupsRes = await _client
        .from('fitness_groups')
        .select('*, sport:sports(id, name_th, icon)')
        .inFilter('id', groupIds);

    final groups = List<Map<String, dynamic>>.from(groupsRes);
    final memberMap = <String, Map<String, dynamic>>{};
    for (final m in memberRows) {
      final gid = m['group_id']?.toString() ?? '';
      if (gid.isNotEmpty) memberMap[gid] = Map<String, dynamic>.from(m);
    }

    for (final g in groups) {
      final gid = g['id']?.toString() ?? '';
      final m = memberMap[gid];
      g['my_role'] = m?['role']?.toString();
      g['my_joined_at'] = m?['joined_at']?.toString();
      g['my_is_active'] = m?['is_active'] == true;
      final sport = g['sport'];
      if (sport is Map) {
        g['sport_name'] = sport['name_th']?.toString();
        g['sport_icon'] = sport['icon']?.toString();
      }
    }
    return groups;
  }

  Future<List<Map<String, dynamic>>> listMyBookings(
    String userId, {
    int limit = 50,
  }) async {
    final res = await _client
        .from('fitness_group_bookings')
        .select(
          '*, session:fitness_group_sessions(*, group:fitness_groups(*, sport:sports(id, name_th, icon)))',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(res);
  }
}
