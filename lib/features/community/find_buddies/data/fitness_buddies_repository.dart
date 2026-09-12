import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/websocket_service.dart';

class FitnessBuddiesRepository {
  final SupabaseClient _client;
  FitnessBuddiesRepository(this._client);

  void _assertCurrentUser(String actorUserId) {
    final currentUserId = AuthService.instance.currentUser?.id;
    if (currentUserId == null || currentUserId != actorUserId) {
      throw StateError('UNAUTHORIZED');
    }
  }

  Future<Map<String, dynamic>> _requireGroupManager({
    required String groupId,
    required String actorUserId,
  }) async {
    _assertCurrentUser(actorUserId);
    final group = await _client
        .from('fitness_groups')
        .select('created_by, owner_auto_join')
        .eq('id', groupId)
        .maybeSingle();
    if (group == null) throw StateError('GROUP_NOT_FOUND');

    final isOwner = group['created_by']?.toString() == actorUserId;
    final isSheservedAdmin = AuthService.instance.currentUser?.isAdmin == true;
    if (!isOwner && !isSheservedAdmin) {
      final member = await _client
          .from('fitness_group_members')
          .select('role, is_active')
          .eq('group_id', groupId)
          .eq('user_id', actorUserId)
          .maybeSingle();
      final isGroupAdmin =
          member?['role']?.toString() == 'admin' &&
          member?['is_active'] == true;
      if (!isGroupAdmin) throw StateError('NOT_GROUP_ADMIN');
    }

    return Map<String, dynamic>.from(group);
  }

  Future<String> _getSessionGroupId(String sessionId) async {
    final session = await _client
        .from('fitness_group_sessions')
        .select('group_id')
        .eq('id', sessionId)
        .maybeSingle();
    final groupId = session?['group_id']?.toString();
    if (groupId == null || groupId.isEmpty) {
      throw StateError('SESSION_NOT_FOUND');
    }
    return groupId;
  }

  Future<String> _getBookingGroupId(String bookingId) async {
    final booking = await _client
        .from('fitness_group_bookings')
        .select('session_id')
        .eq('id', bookingId)
        .maybeSingle();
    final sessionId = booking?['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('BOOKING_NOT_FOUND');
    }
    return _getSessionGroupId(sessionId);
  }

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
    final currentUser = AuthService.instance.currentUser;
    if (currentUser?.id == userId && currentUser?.isAdmin == true) {
      final allGroups = await _client.from('fitness_groups').select('id');
      return (allGroups as List)
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    }

    final results = await Future.wait([
      _client
          .from('fitness_group_members')
          .select('group_id')
          .eq('user_id', userId)
          .eq('role', 'admin')
          .eq('is_active', true),
      _client.from('fitness_groups').select('id').eq('created_by', userId),
    ]);
    final memberAdminIds = (results[0] as List)
        .map((e) => e['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty);
    final ownedGroupIds = (results[1] as List)
        .map((e) => e['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty);
    return {...memberAdminIds, ...ownedGroupIds};
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
    final base = _client.from('fitness_groups_public').select('*');
    var query = base;
    if (sportId != null && sportId.isNotEmpty)
      query = query.eq('sport_id', sportId);
    if (province != null && province.isNotEmpty)
      query = query.eq('province', province);
    if (district != null && district.isNotEmpty)
      query = query.eq('district', district);
    if (q != null && q.isNotEmpty) query = query.ilike('name', '%$q%');
    // Phase 13.0: fitness_groups_public view only exposes visibility='public' groups
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

  Future<List<Map<String, dynamic>>> _attachSessionBookingSummaries(
    List<Map<String, dynamic>> sessions,
  ) async {
    if (sessions.isEmpty) return sessions;

    final sessionIds = sessions
        .map((session) => session['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (sessionIds.isEmpty) return sessions;

    final bookings = await _client
        .from('fitness_group_bookings')
        .select('session_id, user_id, status')
        .inFilter('session_id', sessionIds)
        .inFilter('status', ['pending', 'confirmed']);
    final confirmedBySession = <String, Set<String>>{};
    final pendingBySession = <String, Set<String>>{};
    for (final booking in bookings as List) {
      final sessionId = booking['session_id']?.toString() ?? '';
      final userId = booking['user_id']?.toString() ?? '';
      if (sessionId.isEmpty || userId.isEmpty) continue;
      final status = booking['status']?.toString();
      final target = status == 'confirmed'
          ? confirmedBySession
          : pendingBySession;
      target.putIfAbsent(sessionId, () => <String>{}).add(userId);
    }

    return sessions.map((session) {
      final copy = Map<String, dynamic>.from(session);
      final sessionId = copy['id']?.toString() ?? '';
      final confirmed = confirmedBySession[sessionId] ?? <String>{};
      final pending = pendingBySession[sessionId] ?? <String>{};
      final capacity = (copy['capacity'] as num?)?.toInt() ?? 0;
      copy['confirmed_count'] = confirmed.length;
      copy['pending_count'] = pending.length;
      copy['reserved_count'] = confirmed.length;
      copy['available_count'] = capacity > confirmed.length
          ? capacity - confirmed.length
          : 0;
      return copy;
    }).toList();
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
    return _attachSessionBookingSummaries(List<Map<String, dynamic>>.from(res));
  }

  Future<bool> hasAnySessions(String groupId) async {
    final res = await _client
        .from('fitness_group_sessions')
        .select('id')
        .eq('group_id', groupId)
        .limit(1);
    return (res as List).isNotEmpty;
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
    return _attachSessionBookingSummaries(List<Map<String, dynamic>>.from(res));
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
          .select(
            'id, user_id, session:fitness_group_sessions!inner(id, group_id, starts_at, ends_at)',
          )
          .eq('session.group_id', groupId)
          .eq('status', 'confirmed'),
    ]);
    final blockedUserIds = (results[1] as List)
        .map((e) => e['blocked_user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final confirmedSessionsByUser = <String, List<Map<String, dynamic>>>{};
    for (final booking in results[2] as List) {
      final userId = booking['user_id']?.toString() ?? '';
      if (userId.isEmpty) continue;
      final session = booking['session'];
      final sessionData = session is List && session.isNotEmpty
          ? session.first
          : session is Map
          ? session
          : null;
      if (sessionData is Map) {
        final sessionCopy = Map<String, dynamic>.from(sessionData);
        sessionCopy['booking_id'] = booking['id']?.toString();
        confirmedSessionsByUser.putIfAbsent(userId, () => []).add(sessionCopy);
      }
    }
    final confirmedUserIds = confirmedSessionsByUser.keys.toSet();
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
          final userId = member['user_id']?.toString() ?? '';
          member['confirmed_sessions'] = confirmedSessionsByUser[userId] ?? [];
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
          'id, group_id, starts_at, ends_at, place_name, group:fitness_groups(id, name, created_by, requires_owner_approval)',
        )
        .eq('id', sessionId)
        .maybeSingle();
    if (res == null) return null;
    return Map<String, dynamic>.from(res);
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
    String? actorUserId,
  }) {
    final ws = WebSocketService();
    final socket = ws.socket;
    final currentUserId = AuthService.instance.currentUser?.id;

    final basePayload = <String, dynamic>{
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
      'recipientUserIds': recipientUserIds,
      'recipient_user_ids': recipientUserIds,
      if (actorUserId != null) 'actorUserId': actorUserId,
      if (actorUserId != null) 'actor_user_id': actorUserId,
      if (requesterId != null) 'requesterUserId': requesterId,
      if (requesterId != null) 'requester_user_id': requesterId,
      if (requesterName != null) 'requesterName': requesterName,
      if (requesterName != null) 'requester_name': requesterName,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    };

    for (final recipientUserId in recipientUserIds.toSet()) {
      final payload = Map<String, dynamic>.from(basePayload)
        ..['userId'] = recipientUserId
        ..['user_id'] = recipientUserId;
      if (socket != null && socket.connected) {
        socket.emit('fitness_booking_status', payload);
      }
      if (currentUserId != null && recipientUserId == currentUserId) {
        ws.publishFitnessBookingAlert(payload);
      }
    }
  }

  Future<void> cancelSession(
    String sessionId, {
    required String actorUserId,
  }) async {
    final groupId = await _getSessionGroupId(sessionId);
    await _requireGroupManager(groupId: groupId, actorUserId: actorUserId);
    await _client.from('fitness_group_sessions').delete().eq('id', sessionId);
  }

  Future<String> bookSession(String sessionId, String userId) async {
    final currentUserId = AuthService.instance.currentUser?.id;
    if (currentUserId == null || currentUserId != userId) {
      throw StateError('UNAUTHORIZED');
    }
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
      try {
        final session = await _getSessionWithGroup(sessionId);
        if (session != null) {
          final group = session['group'];
          final groupId = session['group_id']?.toString() ?? '';
          final ownerId = group is Map ? group['created_by']?.toString() : null;
          final groupName = group is Map
              ? (group['name']?.toString() ?? 'ก๊วนกีฬา')
              : 'ก๊วนกีฬา';
          final requiresOwnerApproval =
              group is Map && group['requires_owner_approval'] == true;
          final booking = await _client
              .from('fitness_group_bookings')
              .select('status')
              .eq('id', bookingId)
              .maybeSingle();
          final isPending = booking?['status']?.toString() == 'pending';
          if (requiresOwnerApproval &&
              isPending &&
              ownerId != null &&
              ownerId.isNotEmpty &&
              ownerId != userId) {
            final requesterName = await _getUserDisplayName(userId);
            _emitFitnessBookingStatus(
              recipientUserIds: [ownerId],
              bookingId: bookingId,
              sessionId: sessionId,
              groupId: groupId,
              groupName: groupName,
              status: 'pending',
              message: 'มีคำขอเข้าร่วมก๊วนใหม่',
              requesterId: userId,
              requesterName: requesterName,
              actorUserId: userId,
            );
          }
        }
      } catch (_) {}
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

  /// Lists only [userId]'s pending bookings for sessions in [groupId].
  Future<List<Map<String, dynamic>>> listMyPendingBookingsForGroup(
    String groupId,
    String userId,
  ) async {
    _assertCurrentUser(userId);
    final res = await _client
        .from('fitness_group_bookings')
        .select(
          'id, status, created_at, user:users!fitness_group_bookings_user_id_fkey(first_name, last_name, profile_image_url, id), session:fitness_group_sessions!inner(id, group_id, starts_at, ends_at)',
        )
        .eq('user_id', userId)
        .eq('status', 'pending')
        .eq('session.group_id', groupId)
        .order('created_at', ascending: true);
    return (res as List).map((row) {
      final booking = Map<String, dynamic>.from(row);
      final user = booking['user'];
      if (user is List && user.isNotEmpty) {
        booking['user'] = user.first;
      } else if (user is! Map) {
        booking['user'] = <String, dynamic>{};
      }
      return booking;
    }).toList();
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
    String sessionId, {
    required String requesterUserId,
  }) async {
    final groupId = await _getSessionGroupId(sessionId);
    await _requireGroupManager(groupId: groupId, actorUserId: requesterUserId);
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

  /// Approve a pending booking (group manager action) via RPC with server-side overlap validation.
  Future<void> approveBooking({
    required String bookingId,
    required String actorUserId,
  }) async {
    final bookingGroupId = await _getBookingGroupId(bookingId);
    await _requireGroupManager(
      groupId: bookingGroupId,
      actorUserId: actorUserId,
    );
    await _client.rpc(
      'approve_fitness_session_booking',
      params: {'p_booking_id': bookingId, 'p_owner_id': actorUserId},
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
      requesterId: actorUserId,
      requesterName: requesterName,
      actorUserId: actorUserId,
    );
  }

  /// Reject a pending booking (group manager action). Minimal update: set status to 'rejected'.
  /// Optionally records a cancel_reason with cancelled_by='owner' for audit consistency.
  Future<void> rejectBooking({
    required String bookingId,
    required String actorUserId,
    String? reason,
  }) async {
    final bookingGroupId = await _getBookingGroupId(bookingId);
    await _requireGroupManager(
      groupId: bookingGroupId,
      actorUserId: actorUserId,
    );
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
      requesterId: actorUserId,
      requesterName: requesterName,
      reason: reason,
      actorUserId: actorUserId,
    );
  }

  Future<String> createGroup({
    required String userId,
    required String name,
    String? sportId,
    String? description,
    bool requiresOwnerApproval = false,
    bool ownerAutoJoin = true,
    String? coverImageUrl,
    String? venuePhotoUrl,
    String? genderPreference = 'any',
    String? province,
    String? district,
    String? subdistrict,
    String? postalCode,
    double? lat,
    double? lng,
  }) async {
    _assertCurrentUser(userId);
    final data = {
      'name': name,
      if (sportId != null) 'sport_id': sportId,
      if (description != null) 'description': description,
      'requires_owner_approval': requiresOwnerApproval,
      'owner_auto_join': ownerAutoJoin,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      if (venuePhotoUrl != null) 'venue_photo_url': venuePhotoUrl,
      'gender_preference': genderPreference,
      if (province != null) 'province': province,
      if (district != null) 'district': district,
      if (subdistrict != null) 'subdistrict': subdistrict,
      if (postalCode != null) 'postal_code': postalCode,
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
    required String actorUserId,
    required int capacity,
    required DateTime startsAt,
    required DateTime endsAt,
    String? placeName,
    double? lat,
    double? lng,
    String? note,
    List<Map<String, dynamic>>? costItems,
  }) async {
    await _requireGroupManager(groupId: groupId, actorUserId: actorUserId);
    if (capacity < 1 || capacity > 30) {
      throw ArgumentError('capacity must be between 1 and 30');
    }
    if (startsAt.isBefore(DateTime.now().add(const Duration(minutes: 15)))) {
      throw ArgumentError('startsAt must be at least 15 minutes in the future');
    }
    if (!endsAt.isAfter(startsAt)) {
      throw ArgumentError('endsAt must be after startsAt');
    }
    final data = {
      'group_id': groupId,
      'capacity': capacity,
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
    final sessionId = res['id'].toString();
    if (costItems != null && costItems.isNotEmpty) {
      try {
        await replaceSessionCostItems(
          sessionId: sessionId,
          actorUserId: actorUserId,
          items: costItems,
        );
      } catch (_) {
        // Compensate: remove the session so a failed cost write never
        // leaves a half-created round.
        await _client
            .from('fitness_group_sessions')
            .delete()
            .eq('id', sessionId);
        rethrow;
      }
    }
    return sessionId;
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
    bool? ownerAutoJoin,
    bool cancelOwnerBookings = false,
    String? coverImageUrl,
    String? venuePhotoUrl,
    String? genderPreference,
    String? province,
    String? district,
    String? subdistrict,
    String? postalCode,
    double? lat,
    double? lng,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (requiresOwnerApproval != null)
      data['requires_owner_approval'] = requiresOwnerApproval;
    if (coverImageUrl != null) data['cover_image_url'] = coverImageUrl;
    if (venuePhotoUrl != null) data['venue_photo_url'] = venuePhotoUrl;
    if (genderPreference != null) data['gender_preference'] = genderPreference;
    if (province != null) data['province'] = province;
    if (district != null) data['district'] = district;
    if (subdistrict != null) data['subdistrict'] = subdistrict;
    if (postalCode != null) data['postal_code'] = postalCode;
    if (lat != null) data['lat'] = lat;
    if (lng != null) data['lng'] = lng;
    if (data.isEmpty && ownerAutoJoin == null) return;

    final group = await _requireGroupManager(
      groupId: groupId,
      actorUserId: userId,
    );
    final currentOwnerAutoJoin = group['owner_auto_join'] != false;
    if (ownerAutoJoin != null && ownerAutoJoin != currentOwnerAutoJoin) {
      await _client.rpc(
        'set_fitness_group_owner_auto_join',
        params: {
          'p_group_id': groupId,
          'p_actor_id': userId,
          'p_enabled': ownerAutoJoin,
          'p_cancel_bookings': cancelOwnerBookings,
        },
      );
    }
    if (data.isNotEmpty) {
      await _client.from('fitness_groups').update(data).eq('id', groupId);
    }
  }

  // ── Phase 4: Update session ──
  Future<void> updateSession({
    required String sessionId,
    required String actorUserId,
    int? capacity,
    DateTime? startsAt,
    DateTime? endsAt,
    String? placeName,
    double? lat,
    double? lng,
    String? note,
    List<Map<String, dynamic>>? costItems,
  }) async {
    if (capacity != null && (capacity < 1 || capacity > 30)) {
      throw ArgumentError('capacity must be between 1 and 30');
    }
    final data = <String, dynamic>{};
    if (capacity != null) data['capacity'] = capacity;
    if (startsAt != null)
      data['starts_at'] = startsAt.toUtc().toIso8601String();
    if (endsAt != null) data['ends_at'] = endsAt.toUtc().toIso8601String();
    if (placeName != null) data['place_name'] = placeName;
    if (lat != null) data['lat'] = lat;
    if (lng != null) data['lng'] = lng;
    if (note != null) data['note'] = note;
    if (data.isEmpty && costItems == null) return;
    final groupId = await _getSessionGroupId(sessionId);
    await _requireGroupManager(groupId: groupId, actorUserId: actorUserId);
    if (data.isNotEmpty) {
      await _client
          .from('fitness_group_sessions')
          .update(data)
          .eq('id', sessionId);
    }
    if (costItems != null) {
      await replaceSessionCostItems(
        sessionId: sessionId,
        actorUserId: actorUserId,
        items: costItems,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // Phase 9.1: Two-level expense system
  // Level 1 — fitness_group_cost_standards (group_fee / round_expense
  //           templates, managed from group create/edit)
  // Level 2 — fitness_group_session_cost_items (per-session line items that
  //           snapshot a standard or are custom)
  // No charging, receipts, split-bill or payment_status in this phase.
  // ══════════════════════════════════════════════════════════════════

  static const costStandardTypes = ['group_fee', 'round_expense'];
  static const roundExpenseCategories = [
    'venue',
    'equipment',
    'coach',
    'insurance',
    'competition',
    'uniform',
    'other',
  ];
  static const billingPeriods = [
    'per_use',
    'per_day',
    'per_week',
    'per_month',
    'per_year',
    'lifetime',
  ];
  static const pricingUnits = ['flat', 'per_item', 'per_round', 'per_hour'];
  static const paymentTimings = [
    'before_round_approval',
    'before_group_join',
    'at_venue',
  ];

  static double _toDouble(num? v) => v?.toDouble() ?? 0;

  /// Estimated amount of one line item: flat/per_round use unit_amount
  /// (quantity forced to 1), per_item/per_hour use unit_amount × quantity.
  static double sessionCostItemEstimate(Map<String, dynamic> item) {
    return _toDouble(item['unit_amount'] as num?) *
        _toDouble(item['quantity'] as num? ?? 1);
  }

  static double sessionCostItemsTotal(Iterable<Map<String, dynamic>> items) {
    var total = 0.0;
    for (final item in items) {
      total += sessionCostItemEstimate(item);
    }
    return total;
  }

  void _validateMoney(String field, Object? value) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value');
    if (amount == null || amount <= 0 || amount > 99999999.99) {
      throw ArgumentError('$field must be > 0 and <= 99999999.99');
    }
    // At most 2 decimal places
    if ((amount * 100).roundToDouble() != amount * 100) {
      throw ArgumentError('$field must have at most 2 decimal places');
    }
  }

  void _validatePaymentTiming(Object? timing) {
    if (!paymentTimings.contains(timing)) {
      throw ArgumentError('payment_timing must be one of $paymentTimings');
    }
  }

  void _validateCostStandardInput({
    required String standardType,
    required String category,
    required String name,
    required Object? amount,
    String? billingPeriod,
    String? pricingUnit,
    required Object? defaultQuantity,
    required Object? paymentTiming,
  }) {
    if (!costStandardTypes.contains(standardType)) {
      throw ArgumentError('invalid standard_type');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 100) {
      throw ArgumentError('name must be 1-100 characters');
    }
    _validateMoney('amount', amount);
    _validatePaymentTiming(paymentTiming);
    final qty = defaultQuantity is num
        ? defaultQuantity.toDouble()
        : double.tryParse('$defaultQuantity');
    if (qty == null || qty <= 0) {
      throw ArgumentError('default_quantity must be > 0');
    }
    if (standardType == 'group_fee') {
      if (category != 'membership') {
        throw ArgumentError('group_fee requires category membership');
      }
      if (!billingPeriods.contains(billingPeriod)) {
        throw ArgumentError('group_fee requires a valid billing_period');
      }
      if (pricingUnit != null) {
        throw ArgumentError('group_fee must not set pricing_unit');
      }
    } else {
      if (!roundExpenseCategories.contains(category)) {
        throw ArgumentError('round_expense requires an expense category');
      }
      if (!pricingUnits.contains(pricingUnit)) {
        throw ArgumentError('round_expense requires a valid pricing_unit');
      }
      if (billingPeriod != null) {
        throw ArgumentError('round_expense must not set billing_period');
      }
    }
  }

  void _validateSessionCostItemInput(Map<String, dynamic> item) {
    final name = item['name']?.toString().trim() ?? '';
    if (name.isEmpty || name.length > 100) {
      throw ArgumentError('item name must be 1-100 characters');
    }
    if (!roundExpenseCategories.contains(item['category'])) {
      throw ArgumentError('invalid cost item category');
    }
    final unit = item['pricing_unit']?.toString();
    if (!pricingUnits.contains(unit)) {
      throw ArgumentError('invalid pricing_unit');
    }
    _validateMoney('unit_amount', item['unit_amount']);
    final qty = item['quantity'] is num
        ? (item['quantity'] as num).toDouble()
        : double.tryParse('${item['quantity']}');
    if (qty == null || qty <= 0) {
      throw ArgumentError('quantity must be > 0');
    }
    if (unit == 'flat' || unit == 'per_round') {
      if (qty != 1) {
        throw ArgumentError('flat/per_round items require quantity = 1');
      }
    } else if (unit == 'per_item' && qty != qty.roundToDouble()) {
      throw ArgumentError('per_item quantity must be an integer');
    }
    _validatePaymentTiming(item['payment_timing']);
    final sourceType = item['source_type']?.toString();
    final standardId = item['standard_id']?.toString();
    if (sourceType == 'standard') {
      if (standardId == null || standardId.isEmpty) {
        throw ArgumentError('standard items require standard_id');
      }
    } else if (sourceType == 'custom') {
      if (standardId != null && standardId.isNotEmpty) {
        throw ArgumentError('custom items must not set standard_id');
      }
    } else {
      throw ArgumentError('invalid source_type');
    }
    final note = item['note']?.toString();
    if (note != null && note.length > 200) {
      throw ArgumentError('note must be <= 200 characters');
    }
  }

  /// Manager view: all cost standards of a group (active and inactive).
  Future<List<Map<String, dynamic>>> listGroupCostStandards(
    String groupId, {
    String? standardType,
    bool activeOnly = false,
  }) async {
    var query = _client
        .from('fitness_group_cost_standards')
        .select('*')
        .eq('group_id', groupId);
    if (standardType != null) query = query.eq('standard_type', standardType);
    if (activeOnly) query = query.eq('is_active', true);
    final res = await query.order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Public view: active group_fee standards of a group.
  Future<List<Map<String, dynamic>>> listPublicGroupFees(String groupId) async {
    final res = await _client
        .from('fitness_group_fees_public')
        .select('*')
        .eq('group_id', groupId);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<String> createGroupCostStandard({
    required String groupId,
    required String actorUserId,
    required String standardType,
    required String category,
    required String name,
    required double amount,
    String? billingPeriod,
    String? pricingUnit,
    double defaultQuantity = 1,
    required String paymentTiming,
  }) async {
    _validateCostStandardInput(
      standardType: standardType,
      category: category,
      name: name,
      amount: amount,
      billingPeriod: billingPeriod,
      pricingUnit: pricingUnit,
      defaultQuantity: defaultQuantity,
      paymentTiming: paymentTiming,
    );
    await _requireGroupManager(groupId: groupId, actorUserId: actorUserId);
    final res = await _client
        .from('fitness_group_cost_standards')
        .insert({
          'group_id': groupId,
          'standard_type': standardType,
          'category': category,
          'name': name.trim(),
          'amount': amount,
          'billing_period': billingPeriod,
          'pricing_unit': pricingUnit,
          'default_quantity': defaultQuantity,
          'payment_timing': paymentTiming,
          'created_by': actorUserId,
        })
        .select('id')
        .single();
    return res['id'].toString();
  }

  Future<void> updateGroupCostStandard({
    required String standardId,
    required String actorUserId,
    String? name,
    double? amount,
    String? billingPeriod,
    String? pricingUnit,
    double? defaultQuantity,
    String? paymentTiming,
  }) async {
    final existing = await _client
        .from('fitness_group_cost_standards')
        .select('*')
        .eq('id', standardId)
        .maybeSingle();
    if (existing == null) throw StateError('STANDARD_NOT_FOUND');
    await _requireGroupManager(
      groupId: existing['group_id'].toString(),
      actorUserId: actorUserId,
    );
    _validateCostStandardInput(
      standardType: existing['standard_type'].toString(),
      category: existing['category'].toString(),
      name: name ?? existing['name'].toString(),
      amount: amount ?? existing['amount'],
      billingPeriod: billingPeriod ?? existing['billing_period']?.toString(),
      pricingUnit: pricingUnit ?? existing['pricing_unit']?.toString(),
      defaultQuantity: defaultQuantity ?? existing['default_quantity'],
      paymentTiming: paymentTiming ?? existing['payment_timing'].toString(),
    );
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name.trim();
    if (amount != null) data['amount'] = amount;
    if (billingPeriod != null) data['billing_period'] = billingPeriod;
    if (pricingUnit != null) data['pricing_unit'] = pricingUnit;
    if (defaultQuantity != null) data['default_quantity'] = defaultQuantity;
    if (paymentTiming != null) data['payment_timing'] = paymentTiming;
    if (data.isEmpty) return;
    // Snapshot rows in fitness_group_session_cost_items are not mutated.
    await _client
        .from('fitness_group_cost_standards')
        .update(data)
        .eq('id', standardId);
  }

  /// Disable instead of deleting — keeps history once a standard has been
  /// used by a session line item.
  Future<void> setGroupCostStandardActive({
    required String standardId,
    required String actorUserId,
    required bool isActive,
  }) async {
    final existing = await _client
        .from('fitness_group_cost_standards')
        .select('group_id')
        .eq('id', standardId)
        .maybeSingle();
    if (existing == null) throw StateError('STANDARD_NOT_FOUND');
    await _requireGroupManager(
      groupId: existing['group_id'].toString(),
      actorUserId: actorUserId,
    );
    await _client
        .from('fitness_group_cost_standards')
        .update({'is_active': isActive})
        .eq('id', standardId);
  }

  /// Hard delete is allowed only while no session item references it;
  /// otherwise the caller must disable it instead.
  Future<void> deleteGroupCostStandard({
    required String standardId,
    required String actorUserId,
  }) async {
    final existing = await _client
        .from('fitness_group_cost_standards')
        .select('group_id')
        .eq('id', standardId)
        .maybeSingle();
    if (existing == null) throw StateError('STANDARD_NOT_FOUND');
    await _requireGroupManager(
      groupId: existing['group_id'].toString(),
      actorUserId: actorUserId,
    );
    final used = await _client
        .from('fitness_group_session_cost_items')
        .select('id')
        .eq('standard_id', standardId)
        .limit(1);
    if ((used as List).isNotEmpty) {
      throw StateError('STANDARD_IN_USE');
    }
    await _client
        .from('fitness_group_cost_standards')
        .delete()
        .eq('id', standardId);
  }

  /// Manager view: all line items of a session.
  Future<List<Map<String, dynamic>>> listSessionCostItems(
    String sessionId,
  ) async {
    final res = await _client
        .from('fitness_group_session_cost_items')
        .select('*')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Public view: line items of the given sessions (public groups only).
  Future<List<Map<String, dynamic>>> listPublicSessionCostItems(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return [];
    final res = await _client
        .from('fitness_session_cost_items_public')
        .select('*')
        .inFilter('session_id', sessionIds)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Public view: all line items of every session in a group (public groups).
  Future<List<Map<String, dynamic>>> listPublicSessionCostItemsForGroup(
    String groupId,
  ) async {
    final res = await _client
        .from('fitness_session_cost_items_public')
        .select('*')
        .eq('group_id', groupId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Replaces all line items of a session with [items] (each item must carry
  /// source_type/standard_id consistently; standard items are re-validated
  /// against an active standard of the same group).
  Future<void> replaceSessionCostItems({
    required String sessionId,
    required String actorUserId,
    required List<Map<String, dynamic>> items,
  }) async {
    final groupId = await _getSessionGroupId(sessionId);
    await _requireGroupManager(groupId: groupId, actorUserId: actorUserId);
    for (final item in items) {
      _validateSessionCostItemInput(item);
    }
    // Guard against accidentally duplicated line items.
    final fingerprints = <String>{};
    for (final item in items) {
      final fp = [
        item['standard_id'] ?? '',
        item['name'],
        item['category'],
        item['pricing_unit'],
        item['unit_amount'],
        item['quantity'],
        item['payment_timing'],
      ].join('|');
      if (!fingerprints.add(fp)) {
        throw ArgumentError('duplicate cost item');
      }
    }
    // Every standard reference must point at an active round_expense
    // standard of the same group.
    final standardIds = items
        .where((i) => i['source_type'] == 'standard')
        .map((i) => i['standard_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (standardIds.isNotEmpty) {
      final rows = await _client
          .from('fitness_group_cost_standards')
          .select('id')
          .inFilter('id', standardIds)
          .eq('group_id', groupId)
          .eq('standard_type', 'round_expense')
          .eq('is_active', true);
      final validIds = (rows as List)
          .map((r) => r['id']?.toString() ?? '')
          .toSet();
      if (standardIds.any((id) => !validIds.contains(id))) {
        throw StateError('STANDARD_NOT_AVAILABLE');
      }
    }
    await _client
        .from('fitness_group_session_cost_items')
        .delete()
        .eq('session_id', sessionId);
    if (items.isEmpty) return;
    await _client.from('fitness_group_session_cost_items').insert([
      for (final item in items)
        {
          'session_id': sessionId,
          'standard_id': item['standard_id'],
          'source_type': item['source_type'],
          'name': item['name'].toString().trim(),
          'category': item['category'],
          'pricing_unit': item['pricing_unit'],
          'unit_amount': item['unit_amount'],
          'quantity': item['quantity'],
          'payment_timing': item['payment_timing'],
          if (item['note'] != null && item['note'].toString().trim().isNotEmpty)
            'note': item['note'].toString().trim(),
          'created_by': actorUserId,
        },
    ]);
  }

  // ── Phase 4: Leave group (RPC for atomic cascade) ──
  Future<void> leaveGroup({
    required String groupId,
    required String userId,
    String? actorUserId,
  }) async {
    final actorId = actorUserId ?? userId;
    final currentUserId = AuthService.instance.currentUser?.id;
    if (currentUserId == null || currentUserId != actorId) {
      throw StateError('UNAUTHORIZED');
    }
    await _client.rpc(
      'leave_fitness_group',
      params: {
        'p_group_id': groupId,
        'p_user_id': userId,
        'p_actor_id': actorId,
      },
    );
  }

  Future<void> removeParticipantFromSession({
    required String bookingId,
    required String actorUserId,
  }) async {
    final groupId = await _getBookingGroupId(bookingId);
    await _requireGroupManager(groupId: groupId, actorUserId: actorUserId);
    await _client.rpc(
      'remove_fitness_session_participant',
      params: {'p_booking_id': bookingId, 'p_actor_id': actorUserId},
    );
  }

  // ── Phase 4: Blocklist (per-group; table: fitness_group_blocklist) ──
  Future<void> blockUser({
    required String groupId,
    required String blockedUserId,
    required String blockedBy,
    String? reason,
  }) async {
    final group = await _requireGroupManager(
      groupId: groupId,
      actorUserId: blockedBy,
    );
    if (group['created_by']?.toString() == blockedUserId) {
      throw StateError('OWNER_CANNOT_BE_BLOCKED');
    }
    await _client.from('fitness_group_blocklist').upsert({
      'group_id': groupId,
      'blocked_user_id': blockedUserId,
      'blocked_by': blockedBy,
      'is_active': true,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'group_id,blocked_user_id');
    await leaveGroup(
      groupId: groupId,
      userId: blockedUserId,
      actorUserId: blockedBy,
    );
  }

  Future<void> unblockUser({
    required String groupId,
    required String blockedUserId,
    required String actorUserId,
  }) async {
    await _requireGroupManager(groupId: groupId, actorUserId: actorUserId);
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
    try {
      await _requireGroupManager(
        groupId: groupId,
        actorUserId: requesterUserId,
      );
    } on StateError {
      return [];
    }

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
    String groupId, {
    required String requesterUserId,
  }) async {
    await _requireGroupManager(groupId: groupId, actorUserId: requesterUserId);
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
      _client
          .from('fitness_groups')
          .select('id, owner_auto_join')
          .eq('created_by', userId),
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
    final memberGroupIds = memberRows
        .map((e) => e['group_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final ownedGroups = (results[3] as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final ownedGroupIds = ownedGroups
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final groupIds = {...memberGroupIds, ...ownedGroupIds}.toList();
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
    final ownerAutoJoinMap = <String, bool>{};
    for (final row in ownedGroups) {
      final gid = row['id']?.toString() ?? '';
      if (gid.isNotEmpty) {
        ownerAutoJoinMap[gid] = row['owner_auto_join'] == true;
      }
    }

    for (final g in groups) {
      final gid = g['id']?.toString() ?? '';
      final m = memberMap[gid];
      final isOwner = ownedGroupIds.contains(gid);
      if (m != null) {
        g['my_role'] = m['role']?.toString();
        g['my_joined_at'] = m['joined_at']?.toString();
        g['my_is_active'] = m['is_active'] == true;
      } else if (isOwner) {
        g['my_role'] = 'admin';
        g['my_is_active'] = ownerAutoJoinMap[gid] ?? true;
      }
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
