import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/cost_editors.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/group_chat_popup.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/position_lineup.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/skill_level_chips.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/cost/session_cost_items_view.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/change_position_dialog.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/booking_action_dialogs.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/member_action_dialogs.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/sport_club_error_mapper.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/session_picker_sheet.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/edit_session_sheet.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/edit_group_sheet.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';

/// Signature for booking a session (optionally at a field position).
typedef SessionBookCallback =
    Future<void> Function(
      String sessionId, {
      required bool requiresOwnerApproval,
      String? groupId,
      String? positionId,
    });

/// Giant bottom sheet showing a group's full detail: banner, permission
/// level, members, pending approvals, cost standards, position lineup,
/// and expandable session rounds.
class GroupDetailSheet {
  GroupDetailSheet._({
    required this.pageContext,
    required this.repo,
    required this.client,
    required this.myAdminGroups,
    required this.myJoinedGroupIds,
    required this.myPendingGroupIds,
    required this.detailScrollController,
    required this.onBook,
    required this.onFeedRefresh,
    required this.onPageRefresh,
  });

  final BuildContext pageContext;
  final FitnessBuddiesRepository repo;
  final SupabaseClient client;
  final Set<String> myAdminGroups;
  final Set<String> myJoinedGroupIds;
  final Set<String> myPendingGroupIds;
  final ScrollController detailScrollController;
  final SessionBookCallback onBook;
  final Future<void> Function() onFeedRefresh;
  final Future<void> Function() onPageRefresh;

  static Future<void> show(
    BuildContext pageContext, {
    required Map<String, dynamic> group,
    required FitnessBuddiesRepository repo,
    required SupabaseClient client,
    required Set<String> myAdminGroups,
    required Set<String> myJoinedGroupIds,
    required Set<String> myPendingGroupIds,
    required ScrollController detailScrollController,
    required SessionBookCallback onBook,
    required Future<void> Function() onFeedRefresh,
    required Future<void> Function() onPageRefresh,
  }) {
    return GroupDetailSheet._(
      pageContext: pageContext,
      repo: repo,
      client: client,
      myAdminGroups: myAdminGroups,
      myJoinedGroupIds: myJoinedGroupIds,
      myPendingGroupIds: myPendingGroupIds,
      detailScrollController: detailScrollController,
      onBook: onBook,
      onFeedRefresh: onFeedRefresh,
      onPageRefresh: onPageRefresh,
    )._show(group);
  }

  static Widget _responsiveSlidableAction({
    required void Function(BuildContext) onPressed,
    required Color backgroundColor,
    required Color foregroundColor,
    required IconData icon,
    required String label,
  }) {
    return CustomSlidableAction(
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foregroundColor, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _show(Map<String, dynamic> group) async {
    final groupId = group['id'].toString();
    final currentUser = AuthService.instance.currentUser;
    final currentUserId = currentUser?.id;
    final groupOwnerId = group['created_by']?.toString();
    final isGroupOwner =
        currentUserId != null &&
        groupOwnerId != null &&
        groupOwnerId.isNotEmpty &&
        groupOwnerId == currentUserId;
    final isSheservedAdmin = currentUser?.isAdmin == true;
    final isGroupAdmin =
        myAdminGroups.contains(groupId) && !isGroupOwner && !isSheservedAdmin;
    final isAdmin = isGroupOwner || isGroupAdmin || isSheservedAdmin;
    final permissionLabel = isGroupOwner
        ? 'เจ้าของก๊วน'
        : isSheservedAdmin
        ? 'ผู้ดูแล Sheserved'
        : isGroupAdmin
        ? 'ผู้ดูแลก๊วน'
        : currentUserId != null && myJoinedGroupIds.contains(groupId)
        ? 'สมาชิกก๊วน'
        : currentUserId != null && myPendingGroupIds.contains(groupId)
        ? 'ผู้ขอเข้าร่วม'
        : 'ผู้เยี่ยมชม';
    final permissionColor = isAdmin
        ? AppColors.primary
        : permissionLabel == 'ผู้ขอเข้าร่วม'
        ? Colors.orange.shade800
        : Colors.grey.shade600;
    final isCurrentUserMember =
        currentUserId != null && myJoinedGroupIds.contains(groupId);
    final canSelectSession = isCurrentUserMember || isGroupOwner;
    final canViewBlockedUsers = isAdmin;
    await showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: FutureBuilder<List<dynamic>>(
                  future: Future.wait([
                    loadSessionsWithCostItems(repo, groupId),
                    repo.listGroupMembers(groupId),
                    if (isAdmin)
                      repo.listGroupPendingBookings(
                        groupId,
                        requesterUserId: currentUserId ?? '',
                      )
                    else
                      Future.value(<Map<String, dynamic>>[]),
                    if (!isAdmin && currentUserId != null)
                      repo.listMyPendingBookingsForGroup(groupId, currentUserId)
                    else
                      Future.value(<Map<String, dynamic>>[]),
                    if (canViewBlockedUsers)
                      repo.listBlockedUsers(
                        groupId,
                        requesterUserId: currentUserId ?? '',
                      )
                    else
                      Future.value(<Map<String, dynamic>>[]),
                    repo
                        .listPublicGroupFees(groupId)
                        .catchError((_) => <Map<String, dynamic>>[]),
                  ]),
                  builder: (pageContext, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('โหลดข้อมูลไม่สำเร็จ: ${snapshot.error}'),
                      );
                    }
                    final sessions =
                        (snapshot.data?[0] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [];
                    final members =
                        (snapshot.data?[1] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [];
                    final managerPendingBookings =
                        (snapshot.data?.length ?? 0) > 2
                        ? (snapshot.data![2] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              []
                        : <Map<String, dynamic>>[];
                    final ownPendingBookings = (snapshot.data?.length ?? 0) > 3
                        ? (snapshot.data![3] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              []
                        : <Map<String, dynamic>>[];
                    final pendingBookings = isAdmin
                        ? managerPendingBookings
                        : ownPendingBookings;
                    final blockedUsers = (snapshot.data?.length ?? 0) > 4
                        ? (snapshot.data![4] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              []
                        : <Map<String, dynamic>>[];
                    final groupFees = (snapshot.data?.length ?? 0) > 5
                        ? (snapshot.data![5] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              []
                        : <Map<String, dynamic>>[];

                    final pendingBySession =
                        <String, List<Map<String, dynamic>>>{};
                    for (final booking in pendingBookings) {
                      final rawSession = booking['session'];
                      final session =
                          rawSession is List && rawSession.isNotEmpty
                          ? rawSession.first
                          : rawSession is Map
                          ? rawSession
                          : null;
                      final sessionId = session is Map
                          ? session['id']?.toString() ?? ''
                          : '';
                      if (sessionId.isEmpty) continue;
                      pendingBySession
                          .putIfAbsent(sessionId, () => [])
                          .add(booking);
                    }
                    final confirmedMembersBySession =
                        <String, List<Map<String, dynamic>>>{};
                    for (final member in members) {
                      final confirmedSessions =
                          (member['confirmed_sessions'] as List?) ?? [];
                      for (final rawSession in confirmedSessions) {
                        if (rawSession is! Map) continue;
                        final sessionId = rawSession['id']?.toString() ?? '';
                        if (sessionId.isEmpty) continue;
                        confirmedMembersBySession
                            .putIfAbsent(sessionId, () => [])
                            .add(member);
                      }
                    }
                    return Scrollbar(
                      controller: detailScrollController,
                      thumbVisibility:
                          (members.length +
                              pendingBookings.length +
                              blockedUsers.length) >
                          10,
                      child: SingleChildScrollView(
                        controller: detailScrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: Text(
                                'ก๊วน ${group['name']?.toString() ?? ''}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'สิทธิ์ของคุณ: $permissionLabel',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: permissionColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (group['requires_owner_approval'] == true &&
                                !isGroupOwner) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.lock,
                                      size: 14,
                                      color: Colors.orange,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'การจองรอบใหม่ต้องรออนุมัติ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if ((group['description']?.toString() ?? '')
                                .trim()
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  group['description'].toString().trim(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            if ((group['sport_name']?.toString() ?? '')
                                    .trim()
                                    .isNotEmpty ||
                                (group['province']?.toString() ?? '')
                                    .trim()
                                    .isNotEmpty ||
                                (group['district']?.toString() ?? '')
                                    .trim()
                                    .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if ((group['sport_name']?.toString() ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      _detailInfoChip(
                                        '${group['sport_icon']?.toString() ?? '🏅'} ${group['sport_name']}',
                                        Icons.sports_rounded,
                                      ),
                                    if ((group['province']?.toString() ?? '')
                                            .trim()
                                            .isNotEmpty ||
                                        (group['district']?.toString() ?? '')
                                            .trim()
                                            .isNotEmpty)
                                      _detailInfoChip(
                                        [
                                              group['province']?.toString(),
                                              group['district']?.toString(),
                                            ]
                                            .where(
                                              (value) =>
                                                  value != null &&
                                                  value.trim().isNotEmpty,
                                            )
                                            .join(' · '),
                                        Icons.location_on_outlined,
                                      ),
                                  ],
                                ),
                              ),
                            if (group['gender_preference']?.toString() !=
                                    null ||
                                group['target_skill_levels'] is List)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _detailInfoChip(
                                      switch (group['gender_preference']
                                          ?.toString()) {
                                        'male' => 'ชวนผู้ชาย',
                                        'female' => 'ชวนผู้หญิง',
                                        _ => 'เปิดรับทุกเพศ',
                                      },
                                      Icons.people_outline_rounded,
                                    ),
                                    if (group['target_skill_levels'] is List)
                                      SkillLevelBadge(
                                        targetSkillLevels:
                                            (group['target_skill_levels']
                                                    as List)
                                                .map(
                                                  (level) => level.toString(),
                                                )
                                                .toList(),
                                        isCompact: false,
                                      ),
                                  ],
                                ),
                              ),
                            if ((group['skill_level_note']?.toString() ?? '')
                                .trim()
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  group['skill_level_note'].toString().trim(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            FutureBuilder<List<dynamic>>(
                              future: Future.wait([
                                repo.listPublicGroupPositions(groupId),
                                client
                                    .from('fitness_groups')
                                    .select(
                                      'sport:sports(field_layout, field_style)',
                                    )
                                    .eq('id', groupId)
                                    .maybeSingle(),
                              ]),
                              builder: (pctx, psnap) {
                                if (psnap.hasData) {
                                  final positions =
                                      (psnap.data?[0] as List?)
                                          ?.cast<Map<String, dynamic>>() ??
                                      [];
                                  final gRow =
                                      psnap.data?[1] as Map<String, dynamic>?;
                                  final sport = gRow?['sport'];
                                  final layout = sport is Map
                                      ? sport['field_layout']?.toString()
                                      : null;
                                  final fStyle = sport is Map
                                      ? FieldStyle.fromJson(
                                          sport['field_style'],
                                        )
                                      : FieldStyle.fallback;
                                  if (positions.isNotEmpty &&
                                      (layout == 'single' ||
                                          layout == 'double')) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.sports_soccer_rounded,
                                                size: 16,
                                                color: AppColors.primaryDark,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Expanded(
                                              child: Text(
                                                'ตำแหน่งผู้เล่นที่ก๊วนเปิดรับ',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (isAdmin)
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  foregroundColor:
                                                      AppColors.primaryDark,
                                                ),
                                                onPressed: () {
                                                  Navigator.pop(ctx);
                                                  EditGroupSheet.show(
                                                    pageContext,
                                                    repo: repo,
                                                    client: client,
                                                    group: group,
                                                    onGroupSaved: onPageRefresh,
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.tune_rounded,
                                                  size: 15,
                                                ),
                                                label: const Text(
                                                  'จัดการ',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        PositionLineupView(
                                          layout: layout!,
                                          fieldStyle: fStyle,
                                          positions: positions,
                                        ),
                                      ],
                                    );
                                  }
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'รอบนัด',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if ((isAdmin || canSelectSession) &&
                                sessions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  isAdmin && canSelectSession
                                      ? 'ปัดรอบนัดไปทางซ้ายเพื่อเลือกเพิ่มรอบหรือจัดการ'
                                      : isAdmin
                                      ? 'ปัดรอบนัดไปทางซ้ายเพื่อจัดการ'
                                      : 'ปัดรอบนัดไปทางซ้ายเพื่อเลือกเพิ่มรอบ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            if (sessions.isEmpty)
                              const Text('ยังไม่มีรอบนัด')
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: sessions.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (ctx, i) {
                                  final s = sessions[i];
                                  final sessionId = s['id']?.toString() ?? '';
                                  final sessionLabel = formatThaiSessionRange(
                                    DateTime.parse(
                                      s['starts_at'].toString(),
                                    ).toLocal(),
                                    DateTime.parse(
                                      s['ends_at'].toString(),
                                    ).toLocal(),
                                  );
                                  final confirmedMembers =
                                      confirmedMembersBySession[sessionId] ??
                                      [];
                                  final pendingForSession =
                                      pendingBySession[sessionId] ?? [];
                                  final sessionChildren = <Widget>[
                                    SessionMetaView(session: s),
                                    SessionCostItemsView(session: s),
                                  ];

                                  if (confirmedMembers.isNotEmpty) {
                                    sessionChildren.add(
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            8,
                                            16,
                                            4,
                                          ),
                                          child: Text(
                                            'ผู้เข้าร่วมรอบนี้ ${confirmedMembers.length} คน',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                    sessionChildren.addAll(
                                      confirmedMembers.map<Widget>((member) {
                                        final user =
                                            (member['user'] as Map?) ?? {};
                                        final firstName =
                                            user['first_name']
                                                ?.toString()
                                                .trim() ??
                                            '';
                                        final lastName =
                                            user['last_name']
                                                ?.toString()
                                                .trim() ??
                                            '';
                                        final fullName = '$firstName $lastName'
                                            .trim();
                                        final image =
                                            user['profile_image_url']
                                                ?.toString() ??
                                            '';
                                        final memberUserId =
                                            user['id']?.toString() ??
                                            member['user_id']?.toString() ??
                                            '';
                                        final role =
                                            memberUserId == groupOwnerId
                                            ? 'เจ้าของก๊วน'
                                            : member['role']?.toString() ==
                                                  'admin'
                                            ? 'ผู้ดูแล'
                                            : 'สมาชิก';
                                        final confirmedSessions =
                                            (member['confirmed_sessions']
                                                    as List?)
                                                ?.whereType<Map>() ??
                                            [];
                                        Map<String, dynamic>? sessionBooking;
                                        for (final rawSession
                                            in confirmedSessions) {
                                          if (rawSession['id']?.toString() ==
                                              sessionId) {
                                            sessionBooking =
                                                Map<String, dynamic>.from(
                                                  rawSession,
                                                );
                                            break;
                                          }
                                        }
                                        final bookingId =
                                            sessionBooking?['booking_id']
                                                ?.toString() ??
                                            '';
                                        final tile = ListTile(
                                          dense: true,
                                          contentPadding: const EdgeInsets.only(
                                            left: 16,
                                            right: 16,
                                          ),
                                          leading: CircleAvatar(
                                            radius: 18,
                                            backgroundImage: image.isNotEmpty
                                                ? NetworkImage(image)
                                                : null,
                                            child: image.isEmpty
                                                ? const Icon(Icons.person)
                                                : null,
                                          ),
                                          title: Text(
                                            fullName.isNotEmpty
                                                ? fullName
                                                : 'ไม่ระบุชื่อ',
                                          ),
                                          subtitle: Text('$role · ยืนยันแล้ว'),
                                        );
                                        if (!isAdmin ||
                                            memberUserId == groupOwnerId ||
                                            bookingId.isEmpty) {
                                          return tile;
                                        }
                                        return Slidable(
                                          key: ValueKey(
                                            'session_member_${sessionId}_$memberUserId',
                                          ),
                                          endActionPane: ActionPane(
                                            motion: const ScrollMotion(),
                                            extentRatio: 0.26,
                                            children: [
                                              _responsiveSlidableAction(
                                                onPressed: (_) =>
                                                    BookingActionDialogs.removeParticipantFromSession(
                                                      pageContext,
                                                      ctx,
                                                      repo,
                                                      bookingId,
                                                      fullName,
                                                      sessionLabel,
                                                      setSheetState,
                                                    ),
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                                icon: Icons.person_remove,
                                                label: 'ถอดจากรอบนี้',
                                              ),
                                            ],
                                          ),
                                          child: tile,
                                        );
                                      }),
                                    );
                                  }

                                  if (pendingForSession.isNotEmpty) {
                                    sessionChildren.add(
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            12,
                                            16,
                                            4,
                                          ),
                                          child: Text(
                                            isAdmin
                                                ? 'คำขอรออนุมัติ ${pendingForSession.length} คน'
                                                : 'คำขอของฉัน ${pendingForSession.length} รายการ',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.orange.shade800,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                    sessionChildren.addAll(
                                      pendingForSession.map<Widget>(
                                        (booking) => _buildPendingBookingTile(
                                          actionContext: ctx,
                                          booking: booking,
                                          sessionId: sessionId,
                                          groupId: groupId,
                                          canManage: isAdmin,
                                          setSheetState: setSheetState,
                                        ),
                                      ),
                                    );
                                  }

                                  if (sessionChildren.isEmpty) {
                                    sessionChildren.add(
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          16,
                                          8,
                                          16,
                                          12,
                                        ),
                                        child: Text(
                                          'ยังไม่มีผู้เข้าร่วมรอบนี้',
                                        ),
                                      ),
                                    );
                                  }

                                  final sessionTile = ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    initiallyExpanded:
                                        pendingForSession.isNotEmpty || i == 0,
                                    title: Text(
                                      'รอบที่ ${i + 1} · $sessionLabel',
                                    ),
                                    subtitle: Text(
                                      sessionCapacitySummary(
                                        s,
                                        detailed: true,
                                        pendingCountOverride: isAdmin
                                            ? null
                                            : pendingForSession.length,
                                      ),
                                    ),
                                    children: sessionChildren,
                                  );
                                  final sessionActions = <Widget>[];
                                  if (canSelectSession) {
                                    sessionActions.add(
                                      _responsiveSlidableAction(
                                        onPressed: (_) {
                                          Navigator.pop(ctx);
                                          final requiresApproval =
                                              group['requires_owner_approval'] ==
                                                  true &&
                                              !isGroupOwner;
                                          SessionPickerSheet.show(
                                            pageContext,
                                            repo: repo,
                                            client: client,
                                            groupId: groupId,
                                            requiresOwnerApproval:
                                                requiresApproval,
                                            onBook: (sessionId, {positionId}) =>
                                                onBook(
                                                  sessionId,
                                                  requiresOwnerApproval:
                                                      requiresApproval,
                                                  groupId: groupId,
                                                  positionId: positionId,
                                                ),
                                          );
                                        },
                                        backgroundColor: Colors.teal,
                                        foregroundColor: Colors.white,
                                        icon: Icons.event_available,
                                        label: 'เลือกเพิ่มรอบ',
                                      ),
                                    );
                                  }
                                  if (isAdmin) {
                                    sessionActions.add(
                                      _responsiveSlidableAction(
                                        onPressed: (_) {
                                          Navigator.pop(ctx);
                                          EditSessionSheet.show(
                                            pageContext,
                                            repo: repo,
                                            client: client,
                                            session: s,
                                            onSessionUpdated: onPageRefresh,
                                          );
                                        },
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        icon: Icons.edit,
                                        label: 'แก้ไข',
                                      ),
                                    );
                                    sessionActions.add(
                                      _responsiveSlidableAction(
                                        onPressed: (_) async {
                                          final confirm = await showDialog<bool>(
                                            context: ctx,
                                            builder: (ctx2) => AlertDialog(
                                              title: const Text('ยกเลิกรอบนัด'),
                                              content: const Text(
                                                'ต้องการลบรอบนัดนี้ใช่หรือไม่?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                    ctx2,
                                                  ).pop(false),
                                                  child: const Text('ยกเลิก'),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                    ctx2,
                                                  ).pop(true),
                                                  child: const Text('ยืนยัน'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm != true) return;
                                          try {
                                            final actorUserId = currentUserId;
                                            if (actorUserId == null) return;
                                            await repo.cancelSession(
                                              s['id'].toString(),
                                              actorUserId: actorUserId,
                                            );
                                            if (!pageContext.mounted) return;
                                            ScaffoldMessenger.of(
                                              pageContext,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'ยกเลิกรอบนัดแล้ว',
                                                ),
                                              ),
                                            );
                                            setSheetState(() {});
                                          } catch (e) {
                                            if (!pageContext.mounted) return;
                                            ScaffoldMessenger.of(
                                              pageContext,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'ยกเลิกไม่สำเร็จ: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        icon: Icons.event_busy,
                                        label: 'ยกเลิก',
                                      ),
                                    );
                                  }
                                  if (sessionActions.isEmpty) {
                                    return sessionTile;
                                  }
                                  return Slidable(
                                    key: ValueKey('session_$sessionId'),
                                    endActionPane: ActionPane(
                                      motion: const ScrollMotion(),
                                      extentRatio: sessionActions.length * 0.2,
                                      children: sessionActions,
                                    ),
                                    child: sessionTile,
                                  );
                                },
                              ),
                            const SizedBox(height: 16),
                            ExpansionTile(
                              initiallyExpanded: false,
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                'สมาชิกก๊วนรวม (ไม่ซ้ำ) ${members.length} คน',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'นับผู้ใช้ไม่ซ้ำ ไม่ใช่จำนวนที่นั่งของรอบนัด',
                              ),
                              children: [
                                if (isAdmin)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'ปัดรายชื่อไปทางซ้ายเพื่อจัดการ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                if (members.isEmpty)
                                  const Text('ยังไม่มีสมาชิก')
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: members.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 4),
                                    itemBuilder: (ctx, i) {
                                      final m = members[i];
                                      final user = (m['user'] as Map?) ?? {};
                                      final firstName =
                                          user['first_name']
                                              ?.toString()
                                              .trim() ??
                                          '';
                                      final lastName =
                                          user['last_name']
                                              ?.toString()
                                              .trim() ??
                                          '';
                                      final fullName = '$firstName $lastName'
                                          .trim();
                                      final image =
                                          user['profile_image_url']
                                              ?.toString() ??
                                          '';
                                      final active = m['is_active'] == true
                                          ? 'เข้าร่วมแล้ว'
                                          : 'หยุดพัก';
                                      final memberUserId =
                                          user['id']?.toString() ??
                                          m['user_id']?.toString() ??
                                          '';
                                      final role = memberUserId == groupOwnerId
                                          ? 'เจ้าของก๊วน'
                                          : (m['role']?.toString() == 'admin')
                                          ? 'ผู้ดูแล'
                                          : 'สมาชิก';
                                      final isSelf =
                                          memberUserId == currentUserId;
                                      final mentionTargetName =
                                          isSelf || firstName.isEmpty
                                          ? null
                                          : lastName.isEmpty
                                          ? firstName
                                          : '$firstName ${String.fromCharCode(lastName.runes.first)}.';
                                      final isMemberAdmin =
                                          m['role']?.toString() == 'admin';
                                      // Build swipe actions
                                      final actions = <Widget>[];
                                      // Chat button: available for self, or for admin swiping others
                                      if (isSelf || (isAdmin && !isSelf)) {
                                        actions.add(
                                          _responsiveSlidableAction(
                                            onPressed: (_) {
                                              showGroupChatPopup(
                                                pageContext,
                                                groupId: groupId,
                                                groupName:
                                                    group['name']?.toString() ??
                                                    'ก๊วน',
                                                memberCount: members.length,
                                                mentionTargetName:
                                                    mentionTargetName,
                                              );
                                            },
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.white,
                                            icon: Icons.chat_bubble_outline,
                                            label: 'แชท',
                                          ),
                                        );
                                      }
                                      if (isSelf &&
                                          isGroupOwner &&
                                          group['owner_auto_join'] != false &&
                                          memberUserId.isNotEmpty) {
                                        actions.add(
                                          _responsiveSlidableAction(
                                            onPressed: (_) =>
                                                _withdrawOwnerParticipation(
                                                  sheetContext: ctx,
                                                  groupId: groupId,
                                                  userId: memberUserId,
                                                ),
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            icon: Icons.person_remove_alt_1,
                                            label: 'ถอน',
                                          ),
                                        );
                                      }
                                      // Block + Remove: admin only, not self, not other admin
                                      if (isAdmin &&
                                          !isSelf &&
                                          !isMemberAdmin) {
                                        actions.add(
                                          _responsiveSlidableAction(
                                            onPressed: (_) =>
                                                MemberActionDialogs.blockUser(
                                                  pageContext,
                                                  ctx,
                                                  repo,
                                                  groupId,
                                                  memberUserId,
                                                  fullName,
                                                  setSheetState,
                                                  onFeedRefresh: onFeedRefresh,
                                                ),
                                            backgroundColor: Colors.grey,
                                            foregroundColor: Colors.white,
                                            icon: Icons.block,
                                            label: 'บล็อก',
                                          ),
                                        );
                                        actions.add(
                                          _responsiveSlidableAction(
                                            onPressed: (_) =>
                                                MemberActionDialogs.removeMember(
                                                  pageContext,
                                                  ctx,
                                                  repo,
                                                  groupId,
                                                  memberUserId,
                                                  fullName,
                                                  setSheetState,
                                                ),
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            icon: Icons.person_remove,
                                            label: 'ถอดทั้งก๊วน',
                                          ),
                                        );
                                      }

                                      final tile = ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          backgroundImage: image.isNotEmpty
                                              ? NetworkImage(image)
                                              : null,
                                          child: image.isEmpty
                                              ? const Icon(Icons.person)
                                              : null,
                                        ),
                                        title: Text(
                                          fullName.isNotEmpty
                                              ? fullName
                                              : 'ไม่ระบุชื่อ',
                                        ),
                                        subtitle: Text('$role · $active'),
                                      );

                                      if (actions.isEmpty) return tile;

                                      return Slidable(
                                        key: ValueKey('member_$memberUserId'),
                                        endActionPane: ActionPane(
                                          motion: const ScrollMotion(),
                                          extentRatio: actions.length * 0.2,
                                          children: actions,
                                        ),
                                        child: tile,
                                      );
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.card_membership_rounded,
                                    size: 16,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'ค่าใช้จ่ายมาตรฐานก๊วน',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (isAdmin)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: AppColors.primaryDark,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      EditGroupSheet.show(
                                        pageContext,
                                        repo: repo,
                                        client: client,
                                        group: group,
                                        onGroupSaved: onPageRefresh,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.tune_rounded,
                                      size: 15,
                                    ),
                                    label: const Text(
                                      'จัดการ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (groupFees.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 16,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'ยังไม่ได้กำหนด (ไม่มีค่าสมาชิกก๊วน)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              for (final fee in groupFees)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.card_membership_rounded,
                                          size: 17,
                                          color: AppColors.primaryDark,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fee['name']?.toString() ?? '',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Row(
                                              children: [
                                                Text(
                                                  formatBaht(
                                                    fee['amount'] as num?,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        AppColors.primaryDark,
                                                  ),
                                                ),
                                                Text(
                                                  ' / ${billingPeriodLabel(fee['billing_period']?.toString())}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      paymentTimingBadge(
                                        fee['payment_timing']?.toString(),
                                      ),
                                    ],
                                  ),
                                ),
                            if ((group['venue_photo_url']?.toString() ?? '')
                                .trim()
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.network(
                                    group['venue_photo_url'].toString(),
                                    width: double.infinity,
                                    height: 150,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      height: 150,
                                      alignment: Alignment.center,
                                      color: Colors.grey.shade100,
                                      child: const Text(
                                        'ไม่สามารถโหลดรูปสนามได้',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (canViewBlockedUsers &&
                                blockedUsers.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Divider(),
                              Row(
                                children: [
                                  const Text(
                                    'ถูกบล็อก',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${blockedUsers.length} คน',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: blockedUsers.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (ctx, i) {
                                  final blocked = blockedUsers[i];
                                  final blockedUser =
                                      (blocked['blocked_user'] as Map?) ?? {};
                                  final name =
                                      '${blockedUser['first_name'] ?? ''} ${blockedUser['last_name'] ?? ''}'
                                          .trim();
                                  final image =
                                      blockedUser['profile_image_url']
                                          ?.toString() ??
                                      '';
                                  final reason = blocked['reason']?.toString();
                                  final blockedUserId =
                                      blocked['blocked_user_id']?.toString() ??
                                      '';
                                  final tile = ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundImage: image.isNotEmpty
                                          ? NetworkImage(image)
                                          : null,
                                      child: image.isEmpty
                                          ? const Icon(Icons.person_off)
                                          : null,
                                    ),
                                    title: Text(
                                      name.isNotEmpty ? name : 'ไม่ระบุชื่อ',
                                    ),
                                    subtitle: Text(
                                      reason != null && reason.isNotEmpty
                                          ? 'ถูกบล็อก · เหตุผล: $reason'
                                          : 'ถูกบล็อก',
                                    ),
                                  );
                                  return Slidable(
                                    key: ValueKey('blocked_$blockedUserId'),
                                    endActionPane: ActionPane(
                                      motion: const ScrollMotion(),
                                      extentRatio: 0.24,
                                      children: [
                                        _responsiveSlidableAction(
                                          onPressed: (_) async {
                                            try {
                                              final actorUserId = currentUserId;
                                              if (actorUserId == null) return;
                                              await repo.unblockUser(
                                                groupId: groupId,
                                                blockedUserId: blockedUserId,
                                                actorUserId: actorUserId,
                                              );
                                              if (!pageContext.mounted) return;
                                              ScaffoldMessenger.of(
                                                pageContext,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'ปลดบล็อก "$name" แล้ว',
                                                  ),
                                                ),
                                              );
                                              setSheetState(() {});
                                              await onFeedRefresh();
                                            } catch (e) {
                                              if (!pageContext.mounted) return;
                                              ScaffoldMessenger.of(
                                                pageContext,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'ปลดบล็อกไม่สำเร็จ: $e',
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          icon: Icons.lock_open,
                                          label: 'ปลด',
                                        ),
                                      ],
                                    ),
                                    child: tile,
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 16),
                            // ── Action buttons ──
                            _buildGroupActionButtons(
                              ctx: ctx,
                              setSheetState: setSheetState,
                              groupId: groupId,
                              isAdmin: isAdmin,
                              isMember: myJoinedGroupIds.contains(groupId),
                              group: group,
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _withdrawOwnerParticipation({
    required BuildContext sheetContext,
    required String groupId,
    required String userId,
  }) async {
    final confirm = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ถอนตัวจากสมาชิก'),
        content: const Text(
          'ต้องการหยุดการเข้าร่วมทุกรอบอัตโนมัติหรือไม่?\n'
          'ระบบจะยกเลิก booking ของ owner ในรอบอนาคต และคุณยังคงเป็นผู้ดูแลก๊วน',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ถอน', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await repo.updateGroup(
        groupId: groupId,
        userId: userId,
        ownerAutoJoin: false,
        cancelOwnerBookings: true,
      );
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text('ถอนจากสมาชิกแล้ว และยังคงเป็นผู้ดูแลก๊วน'),
        ),
      );
      Navigator.pop(sheetContext);
      await onFeedRefresh();
    } catch (e) {
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(content: Text('ถอนไม่สำเร็จ: ${mapManagementError(e)}')),
      );
    }
  }

  static Widget _detailInfoChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupActionButtons({
    required BuildContext ctx,
    required StateSetter setSheetState,
    required String groupId,
    required bool isAdmin,
    required bool isMember,
    required Map<String, dynamic> group,
  }) {
    final userId = AuthService.instance.currentUser?.id;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Phase 4: Edit group (admin only)
        if (isAdmin)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              EditGroupSheet.show(
                pageContext,
                repo: repo,
                client: client,
                group: group,
                onGroupSaved: onPageRefresh,
              );
            },
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('แก้ไขก๊วน'),
          ),
        // Phase 4: Leave group (non-admin members only)
        if (isMember && !isAdmin && userId != null)
          OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  title: const Text('ออกจากก๊วน'),
                  content: const Text(
                    'คุณต้องการออกจากก๊วนนี้ใช่หรือไม่? การจองทั้งหมดของคุณจะถูกยกเลิก',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('ยกเลิก'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text(
                        'ยืนยัน',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              try {
                await repo.leaveGroup(groupId: groupId, userId: userId);
                if (!pageContext.mounted) return;
                ScaffoldMessenger.of(
                  pageContext,
                ).showSnackBar(const SnackBar(content: Text('ออกจากก๊วนแล้ว')));
                Navigator.pop(ctx);
                onPageRefresh();
              } catch (e) {
                if (!pageContext.mounted) return;
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(content: Text('ออกจากก๊วนไม่สำเร็จ: $e')),
                );
              }
            },
            icon: const Icon(Icons.exit_to_app, size: 18, color: Colors.red),
            label: const Text(
              'ออกจากก๊วน',
              style: TextStyle(color: Colors.red),
            ),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
      ],
    );
  }

  Widget _buildPendingBookingTile({
    required BuildContext actionContext,
    required Map<String, dynamic> booking,
    required String sessionId,
    required String groupId,
    required bool canManage,
    required StateSetter setSheetState,
  }) {
    final userData = (booking['user'] as Map?) ?? {};
    final firstName = userData['first_name']?.toString().trim() ?? '';
    final lastName = userData['last_name']?.toString().trim() ?? '';
    final fullName = '$firstName $lastName'.trim();
    final image = userData['profile_image_url']?.toString() ?? '';
    final userId = userData['id']?.toString() ?? '';
    final bookingId = booking['id']?.toString() ?? '';
    final requestedAt = DateTime.tryParse(
      booking['created_at']?.toString() ?? '',
    );
    final posData = booking['position'];
    final posLabel = posData is Map ? posData['label']?.toString() : null;
    final declaredSkill = booking['declared_skill_level']?.toString();

    final requestTimeLabel = requestedAt == null
        ? 'เวลาที่ขอเข้าร่วมไม่พร้อมใช้งาน'
        : 'ขอเข้าร่วมเมื่อ ${formatThaiBuddhistDateTime(requestedAt.toLocal())}';
    final tile = ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 16, right: 16),
      leading: CircleAvatar(
        radius: 18,
        backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
        child: image.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(fullName.isNotEmpty ? fullName : 'ไม่ระบุชื่อ'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              const Text(
                'รออนุมัติ',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (posLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ตำแหน่ง: $posLabel',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (declaredSkill != null && declaredSkill.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '🎯 ระดับมือ: $declaredSkill',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            requestTimeLabel,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      trailing: !canManage && userId == AuthService.instance.currentUser?.id
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.primaryDark,
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: () => ChangePositionDialog.show(
                pageContext: pageContext,
                sheetContext: actionContext,
                repo: repo,
                client: client,
                bookingId: bookingId,
                sessionId: sessionId,
                groupId: groupId,
                setSheetState: setSheetState,
              ),
              child: const Text(
                'เปลี่ยนตำแหน่ง',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
    if (!canManage) return tile;

    return Slidable(
      key: ValueKey('pending_${sessionId}_$bookingId'),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.7,
        children: [
          _responsiveSlidableAction(
            onPressed: (_) => BookingActionDialogs.approveSingle(
              pageContext,
              repo,
              bookingId,
              fullName,
              setSheetState,
            ),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            icon: Icons.check_circle,
            label: 'อนุมัติ',
          ),
          _responsiveSlidableAction(
            onPressed: (_) => BookingActionDialogs.showRejectAll(
              pageContext,
              actionContext,
              repo,
              [booking],
              fullName,
              setSheetState,
            ),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.cancel,
            label: 'ปฏิเสธ',
          ),
          _responsiveSlidableAction(
            onPressed: (_) => MemberActionDialogs.blockUser(
              pageContext,
              actionContext,
              repo,
              groupId,
              userId,
              fullName,
              setSheetState,
              onFeedRefresh: onFeedRefresh,
            ),
            backgroundColor: Colors.grey,
            foregroundColor: Colors.white,
            icon: Icons.block,
            label: 'บล็อก',
          ),
        ],
      ),
      child: tile,
    );
  }
}
