import 'dart:async';
import 'dart:ui';
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
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/group_session_history_dialog.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/sport_club_error_mapper.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/session_picker_sheet.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/edit_session_sheet.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/edit_group_sheet.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/group_invite_poster_sheet.dart';
import 'package:sheserved/features/sport_club/services/sport_club_deep_link_service.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';

/// Signature for booking a session (optionally at a field position).
typedef SessionBookCallback =
    Future<void> Function(
      String sessionId, {
      required bool requiresOwnerApproval,
      String? groupId,
      String? positionId,
    });

bool canOpenGroupChatFromMemberSwipe({
  required bool canChat,
  required bool isActiveMember,
}) => canChat && isActiveMember;

Map<String, String> currentUserSessionBookingStatuses({
  required String? userId,
  required List<Map<String, dynamic>> members,
  required List<Map<String, dynamic>> pendingBookings,
}) {
  final statuses = <String, String>{};
  if (userId == null || userId.isEmpty) return statuses;

  for (final member in members) {
    if (member['user_id']?.toString() != userId) continue;
    final confirmedSessions = (member['confirmed_sessions'] as List?) ?? [];
    for (final rawSession in confirmedSessions) {
      if (rawSession is! Map) continue;
      final sessionId = rawSession['id']?.toString() ?? '';
      if (sessionId.isNotEmpty) statuses[sessionId] = 'confirmed';
    }
  }

  for (final booking in pendingBookings) {
    final user = booking['user'];
    final bookingUserId =
        booking['user_id']?.toString() ??
        (user is Map ? user['id']?.toString() ?? '' : '');
    if (bookingUserId != userId) continue;
    final rawSession = booking['session'];
    final session = rawSession is List && rawSession.isNotEmpty
        ? rawSession.first
        : rawSession is Map
        ? rawSession
        : null;
    final sessionId = session is Map ? session['id']?.toString() ?? '' : '';
    if (sessionId.isNotEmpty) statuses.putIfAbsent(sessionId, () => 'pending');
  }

  return statuses;
}

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
    bool openChatOnShow = false,
    String? chatRoomId,
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
    )._show(group, openChatOnShow: openChatOnShow, chatRoomId: chatRoomId);
  }

  static Widget _frostedCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    EdgeInsetsGeometry? margin,
    Color? backgroundColor,
    Border? border,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border:
            border ??
            Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  static Widget _sectionHeader({
    required IconData icon,
    required String title,
    String? badge,
    Widget? trailing,
    Color iconColor = AppColors.primaryDark,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foregroundColor, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _show(
    Map<String, dynamic> group, {
    bool openChatOnShow = false,
    String? chatRoomId,
  }) async {
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
    final memberSwipeHint = isAdmin
        ? 'ปัดรายชื่อไปทางซ้ายเพื่อจัดการ'
        : 'ปัดรอบนัดไปทางซ้ายเพื่อเลือกเพิ่มรอบ';
    final canSelectSession = true;
    final canViewBlockedUsers = isAdmin;
    var initialChatOpened = false;

    Future<List<dynamic>> loadSheetData() {
      return Future.wait<dynamic>([
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
          repo.listBlockedUsers(groupId, requesterUserId: currentUserId ?? '')
        else
          Future.value(<Map<String, dynamic>>[]),
        repo
            .listPublicGroupFees(groupId)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
    }

    // Keep the same Future while the sheet rebuilds (including during scroll).
    // A new Future is assigned only after an action changes the data.
    var sheetDataFuture = loadSheetData();
    final positionsFuture = Future.wait<dynamic>([
      repo.listPublicGroupPositions(groupId),
      client
          .from('fitness_groups')
          .select('sport:sports(field_layout, field_style)')
          .eq('id', groupId)
          .maybeSingle(),
    ]);

    await showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final screenHeight = MediaQuery.of(ctx).size.height;
          void reloadSheetState(VoidCallback callback) {
            sheetDataFuture = loadSheetData();
            setSheetState(callback);
          }

          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                constraints: BoxConstraints(maxHeight: screenHeight * 0.90),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 1.5,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 25,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: FutureBuilder<List<dynamic>>(
                      future: sheetDataFuture,
                      builder: (pageContext, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'โหลดข้อมูลไม่สำเร็จ: ${snapshot.error}',
                            ),
                          );
                        }
                        final allSessions =
                            (snapshot.data?[0] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            [];
                        final sessions = allSessions
                            .where(
                              (session) => !isSportClubSessionEnded(session),
                            )
                            .toList();
                        final endedSessions = allSessions
                            .where(isSportClubSessionEnded)
                            .toList();
                        final members =
                            (snapshot.data?[1] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            [];
                        if (openChatOnShow && !initialChatOpened) {
                          initialChatOpened = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!pageContext.mounted) return;
                            unawaited(
                              showGroupChatPopup(
                                pageContext,
                                groupId: groupId,
                                groupName: group['name']?.toString() ?? 'ก๊วน',
                                roomId: chatRoomId,
                                memberCount: members.length,
                              ),
                            );
                          });
                        }
                        final managerPendingBookings =
                            (snapshot.data?.length ?? 0) > 2
                            ? (snapshot.data![2] as List?)
                                      ?.cast<Map<String, dynamic>>() ??
                                  []
                            : <Map<String, dynamic>>[];
                        final ownPendingBookings =
                            (snapshot.data?.length ?? 0) > 3
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
                            final sessionId =
                                rawSession['id']?.toString() ?? '';
                            if (sessionId.isEmpty) continue;
                            confirmedMembersBySession
                                .putIfAbsent(sessionId, () => [])
                                .add(member);
                          }
                        }
                        final mySessionBookingStatuses =
                            currentUserSessionBookingStatuses(
                              userId: currentUserId,
                              members: members,
                              pendingBookings: pendingBookings,
                            );
                        final canSelectAdditionalSession =
                            canSelectSession &&
                            sessions.any(
                              (session) => isSessionAvailableForBooking(
                                session,
                                excludedSessionIds: mySessionBookingStatuses
                                    .keys
                                    .toSet(),
                              ),
                            );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Top drag handle ──
                            Center(
                              child: Container(
                                width: 42,
                                height: 4.5,
                                margin: const EdgeInsets.only(
                                  top: 2,
                                  bottom: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            // ── Header Row: Avatar, Title, Badges, Close ──
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.primary.withValues(
                                          alpha: 0.2,
                                        ),
                                        AppColors.primaryDark.withValues(
                                          alpha: 0.25,
                                        ),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.35,
                                      ),
                                      width: 1.2,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    group['sport_icon']?.toString() ?? '🏅',
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        group['name']?.toString() ?? 'ก๊วนกีฬา',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1E293B),
                                          letterSpacing: -0.2,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 5),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: permissionColor.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: permissionColor
                                                    .withValues(alpha: 0.25),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isAdmin
                                                      ? Icons
                                                            .admin_panel_settings_rounded
                                                      : Icons
                                                            .person_outline_rounded,
                                                  size: 13,
                                                  color: permissionColor,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  permissionLabel,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: permissionColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (group['requires_owner_approval'] ==
                                                  true &&
                                              !isGroupOwner)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.orange
                                                      .withValues(alpha: 0.3),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.lock_clock_rounded,
                                                    size: 13,
                                                    color: Colors.orange,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'ต้องรออนุมัติ',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors
                                                          .orange
                                                          .shade800,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () =>
                                          GroupInvitePosterSheet.show(
                                            ctx,
                                            groupData: group,
                                          ),
                                      icon: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.share_rounded,
                                          size: 18,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      splashRadius: 20,
                                      tooltip: 'เชิญเข้าร่วมก๊วน',
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      icon: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      splashRadius: 20,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // ── Scrollable content (header/actions pinned) ──
                            Flexible(
                              child: Scrollbar(
                                controller: detailScrollController,
                                thumbVisibility:
                                    (members.length +
                                        pendingBookings.length +
                                        blockedUsers.length) >
                                    10,
                                child: SingleChildScrollView(
                                  controller: detailScrollController,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // ── Overview & Meta Card ──
                                      _frostedCard(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if ((group['description']
                                                        ?.toString() ??
                                                    '')
                                                .trim()
                                                .isNotEmpty) ...[
                                              Text(
                                                group['description']
                                                    .toString()
                                                    .trim(),
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  height: 1.45,
                                                  color: Color(0xFF475569),
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                            ],
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                if ((group['sport_name']
                                                            ?.toString() ??
                                                        '')
                                                    .trim()
                                                    .isNotEmpty)
                                                  _detailInfoChip(
                                                    '${group['sport_icon']?.toString() ?? '🏅'} ${group['sport_name']}',
                                                    Icons.sports_rounded,
                                                  ),
                                                if ((group['province']
                                                                ?.toString() ??
                                                            '')
                                                        .trim()
                                                        .isNotEmpty ||
                                                    (group['district']
                                                                ?.toString() ??
                                                            '')
                                                        .trim()
                                                        .isNotEmpty)
                                                  _detailInfoChip(
                                                    [
                                                          group['province']
                                                              ?.toString(),
                                                          group['district']
                                                              ?.toString(),
                                                        ]
                                                        .where(
                                                          (value) =>
                                                              value != null &&
                                                              value
                                                                  .trim()
                                                                  .isNotEmpty,
                                                        )
                                                        .join(' · '),
                                                    Icons.location_on_outlined,
                                                  ),
                                                if (group['gender_preference']
                                                        ?.toString() !=
                                                    null)
                                                  _detailInfoChip(
                                                    switch (group['gender_preference']
                                                        ?.toString()) {
                                                      'male' => 'เฉพาะผู้ชาย',
                                                      'female' =>
                                                        'เฉพาะผู้หญิง',
                                                      _ => 'เปิดรับทุกเพศ',
                                                    },
                                                    Icons
                                                        .people_outline_rounded,
                                                  ),
                                                if (group['target_skill_levels']
                                                    is List)
                                                  SkillLevelBadge(
                                                    targetSkillLevels:
                                                        (group['target_skill_levels']
                                                                as List)
                                                            .map(
                                                              (level) => level
                                                                  .toString(),
                                                            )
                                                            .toList(),
                                                    isCompact: false,
                                                    backgroundColor: Colors
                                                        .white
                                                        .withValues(alpha: 0.8),
                                                    borderColor: Colors
                                                        .grey
                                                        .shade300
                                                        .withValues(alpha: 0.8),
                                                  ),
                                              ],
                                            ),
                                            if ((group['skill_level_note']
                                                        ?.toString() ??
                                                    '')
                                                .trim()
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.shade50
                                                      .withValues(alpha: 0.7),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color:
                                                        Colors.amber.shade200,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .tips_and_updates_outlined,
                                                      size: 14,
                                                      color:
                                                          Colors.amber.shade800,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        group['skill_level_note']
                                                            .toString()
                                                            .trim(),
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .amber
                                                              .shade900,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            if ((group['venue_photo_url']
                                                        ?.toString() ??
                                                    '')
                                                .trim()
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 12),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                child: Stack(
                                                  children: [
                                                    Image.network(
                                                      group['venue_photo_url']
                                                          .toString(),
                                                      width: double.infinity,
                                                      height: 140,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, _, _) =>
                                                          Container(
                                                            height: 120,
                                                            alignment: Alignment
                                                                .center,
                                                            color: Colors
                                                                .grey
                                                                .shade100,
                                                            child: const Text(
                                                              'ไม่สามารถโหลดรูปสนามได้',
                                                            ),
                                                          ),
                                                    ),
                                                    Positioned(
                                                      bottom: 8,
                                                      left: 8,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.black
                                                              .withValues(
                                                                alpha: 0.6,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: const Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .stadium_rounded,
                                                              color:
                                                                  Colors.white,
                                                              size: 14,
                                                            ),
                                                            SizedBox(width: 4),
                                                            Text(
                                                              'รูปสนาม / สถานที่',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      FutureBuilder<List<dynamic>>(
                                        future: positionsFuture,
                                        builder: (pctx, psnap) {
                                          if (psnap.hasData) {
                                            final positions =
                                                (psnap.data?[0] as List?)
                                                    ?.cast<
                                                      Map<String, dynamic>
                                                    >() ??
                                                [];
                                            final gRow =
                                                psnap.data?[1]
                                                    as Map<String, dynamic>?;
                                            final sport = gRow?['sport'];
                                            final layout = sport is Map
                                                ? sport['field_layout']
                                                      ?.toString()
                                                : null;
                                            final fStyle = sport is Map
                                                ? FieldStyle.fromJson(
                                                    sport['field_style'],
                                                  )
                                                : FieldStyle.fallback;
                                            if (positions.isNotEmpty &&
                                                (layout == 'single' ||
                                                    layout == 'double')) {
                                              return _frostedCard(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    _sectionHeader(
                                                      icon: Icons
                                                          .sports_soccer_rounded,
                                                      title:
                                                          'ตำแหน่งผู้เล่นที่ก๊วนเปิดรับ',
                                                      trailing: isAdmin
                                                          ? TextButton.icon(
                                                              style: TextButton.styleFrom(
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                                foregroundColor:
                                                                    AppColors
                                                                        .primaryDark,
                                                              ),
                                                              onPressed: () {
                                                                Navigator.pop(
                                                                  ctx,
                                                                );
                                                                EditGroupSheet.show(
                                                                  pageContext,
                                                                  repo: repo,
                                                                  client:
                                                                      client,
                                                                  group: group,
                                                                  onGroupSaved:
                                                                      onPageRefresh,
                                                                );
                                                              },
                                                              icon: const Icon(
                                                                Icons
                                                                    .tune_rounded,
                                                                size: 15,
                                                              ),
                                                              label: const Text(
                                                                'จัดการ',
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            )
                                                          : null,
                                                    ),
                                                    const SizedBox(height: 12),
                                                    PositionLineupView(
                                                      layout: layout!,
                                                      fieldStyle: fStyle,
                                                      positions: positions,
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                      _frostedCard(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _sectionHeader(
                                              icon:
                                                  Icons.calendar_month_rounded,
                                              title: 'รอบนัด',
                                              badge: sessions.isNotEmpty
                                                  ? '${sessions.length}'
                                                  : null,
                                            ),
                                            if ((isAdmin ||
                                                    canSelectAdditionalSession) &&
                                                sessions.isNotEmpty)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  top: 8,
                                                  bottom: 4,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.08),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: AppColors.primary
                                                        .withValues(alpha: 0.2),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.swipe_left_rounded,
                                                      size: 15,
                                                      color:
                                                          AppColors.primaryDark,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        isAdmin &&
                                                                canSelectAdditionalSession
                                                            ? 'ปัดรอบนัดไปทางซ้ายเพื่อเลือกเพิ่มรอบหรือจัดการ'
                                                            : isAdmin
                                                            ? 'ปัดรอบนัดไปทางซ้ายเพื่อจัดการ'
                                                            : 'ปัดรอบนัดไปทางซ้ายเพื่อเลือกเพิ่มรอบ',
                                                        style: const TextStyle(
                                                          fontSize: 11.5,
                                                          color: AppColors
                                                              .primaryDark,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            if (sessions.isEmpty)
                                              Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 18,
                                                    ),
                                                alignment: Alignment.center,
                                                child: Column(
                                                  children: [
                                                    Icon(
                                                      Icons.event_busy_rounded,
                                                      size: 32,
                                                      color:
                                                          Colors.grey.shade400,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      'ยังไม่มีรอบนัดที่กำลังจะมาถึง',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else
                                              ListView.separated(
                                                shrinkWrap: true,
                                                physics:
                                                    const NeverScrollableScrollPhysics(),
                                                itemCount: sessions.length,
                                                separatorBuilder: (_, _) =>
                                                    const SizedBox(height: 10),
                                                itemBuilder: (ctx, i) {
                                                  final s = sessions[i];
                                                  final sessionId =
                                                      s['id']?.toString() ?? '';
                                                  final sessionLabel =
                                                      formatThaiSessionRange(
                                                        DateTime.parse(
                                                          s['starts_at']
                                                              .toString(),
                                                        ).toLocal(),
                                                        DateTime.parse(
                                                          s['ends_at']
                                                              .toString(),
                                                        ).toLocal(),
                                                      );
                                                  final confirmedMembers =
                                                      confirmedMembersBySession[sessionId] ??
                                                      [];
                                                  final pendingForSession =
                                                      pendingBySession[sessionId] ??
                                                      [];
                                                  final sessionChildren =
                                                      <Widget>[
                                                        SessionMetaView(
                                                          session: s,
                                                        ),
                                                        SessionCostItemsView(
                                                          session: s,
                                                        ),
                                                      ];

                                                  if (confirmedMembers
                                                      .isNotEmpty) {
                                                    sessionChildren.add(
                                                      Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets.fromLTRB(
                                                                16,
                                                                8,
                                                                16,
                                                                4,
                                                              ),
                                                          child: Text(
                                                            'ผู้เข้าร่วมรอบนี้ ${confirmedMembers.length} คน',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color: Colors
                                                                  .grey[700],
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                    sessionChildren.addAll(
                                                      confirmedMembers.map<
                                                        Widget
                                                      >((member) {
                                                        final user =
                                                            (member['user']
                                                                as Map?) ??
                                                            {};
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
                                                        final fullName =
                                                            '$firstName $lastName'
                                                                .trim();
                                                        final image =
                                                            user['profile_image_url']
                                                                ?.toString() ??
                                                            '';
                                                        final memberUserId =
                                                            user['id']
                                                                ?.toString() ??
                                                            member['user_id']
                                                                ?.toString() ??
                                                            '';
                                                        final role =
                                                            memberUserId ==
                                                                groupOwnerId
                                                            ? 'เจ้าของก๊วน'
                                                            : member['role']
                                                                      ?.toString() ==
                                                                  'admin'
                                                            ? 'ผู้ดูแล'
                                                            : 'สมาชิก';
                                                        final confirmedSessions =
                                                            (member['confirmed_sessions']
                                                                    as List?)
                                                                ?.whereType<
                                                                  Map
                                                                >() ??
                                                            [];
                                                        Map<String, dynamic>?
                                                        sessionBooking;
                                                        for (final rawSession
                                                            in confirmedSessions) {
                                                          if (rawSession['id']
                                                                  ?.toString() ==
                                                              sessionId) {
                                                            sessionBooking =
                                                                Map<
                                                                  String,
                                                                  dynamic
                                                                >.from(
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
                                                          contentPadding:
                                                              const EdgeInsets.only(
                                                                left: 16,
                                                                right: 16,
                                                              ),
                                                          leading: CircleAvatar(
                                                            radius: 18,
                                                            backgroundImage:
                                                                image.isNotEmpty
                                                                ? NetworkImage(
                                                                    image,
                                                                  )
                                                                : null,
                                                            child: image.isEmpty
                                                                ? const Icon(
                                                                    Icons
                                                                        .person,
                                                                  )
                                                                : null,
                                                          ),
                                                          title: Text(
                                                            fullName.isNotEmpty
                                                                ? fullName
                                                                : 'ไม่ระบุชื่อ',
                                                          ),
                                                          subtitle: Text(
                                                            '$role · ยืนยันแล้ว',
                                                          ),
                                                        );
                                                        if (!isAdmin ||
                                                            memberUserId ==
                                                                groupOwnerId ||
                                                            bookingId.isEmpty) {
                                                          return tile;
                                                        }
                                                        return Slidable(
                                                          key: ValueKey(
                                                            'session_member_${sessionId}_$memberUserId',
                                                          ),
                                                          endActionPane: ActionPane(
                                                            motion:
                                                                const ScrollMotion(),
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
                                                                      reloadSheetState,
                                                                    ),
                                                                backgroundColor:
                                                                    Colors.red,
                                                                foregroundColor:
                                                                    Colors
                                                                        .white,
                                                                icon: Icons
                                                                    .person_remove,
                                                                label:
                                                                    'ถอดจากรอบนี้',
                                                              ),
                                                            ],
                                                          ),
                                                          child: tile,
                                                        );
                                                      }),
                                                    );
                                                  }

                                                  if (pendingForSession
                                                      .isNotEmpty) {
                                                    sessionChildren.add(
                                                      Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets.fromLTRB(
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
                                                              color: Colors
                                                                  .orange
                                                                  .shade800,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                    sessionChildren.addAll(
                                                      pendingForSession.map<
                                                        Widget
                                                      >(
                                                        (
                                                          booking,
                                                        ) => _buildPendingBookingTile(
                                                          actionContext: ctx,
                                                          booking: booking,
                                                          sessionId: sessionId,
                                                          groupId: groupId,
                                                          canManage: isAdmin,
                                                          setSheetState:
                                                              reloadSheetState,
                                                        ),
                                                      ),
                                                    );
                                                  }

                                                  if (sessionChildren.isEmpty) {
                                                    sessionChildren.add(
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.fromLTRB(
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

                                                  final sessionTile = Theme(
                                                    data: Theme.of(ctx)
                                                        .copyWith(
                                                          dividerColor: Colors
                                                              .transparent,
                                                        ),
                                                    child: ExpansionTile(
                                                      tilePadding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 14,
                                                            vertical: 4,
                                                          ),
                                                      initiallyExpanded:
                                                          pendingForSession
                                                              .isNotEmpty ||
                                                          i == 0,
                                                      leading: Container(
                                                        width: 38,
                                                        height: 38,
                                                        decoration: BoxDecoration(
                                                          color: AppColors
                                                              .primary
                                                              .withValues(
                                                                alpha: 0.12,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons
                                                              .event_note_rounded,
                                                          color: AppColors
                                                              .primaryDark,
                                                          size: 20,
                                                        ),
                                                      ),
                                                      title: Text(
                                                        'รอบที่ ${i + 1} · $sessionLabel',
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Color(
                                                            0xFF1E293B,
                                                          ),
                                                        ),
                                                      ),
                                                      subtitle: Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 2,
                                                            ),
                                                        child: Text(
                                                          sessionCapacitySummary(
                                                            s,
                                                            detailed: true,
                                                            pendingCountOverride:
                                                                isAdmin
                                                                ? null
                                                                : pendingForSession
                                                                      .length,
                                                          ),
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors
                                                                .grey
                                                                .shade600,
                                                          ),
                                                        ),
                                                      ),
                                                      trailing: IconButton(
                                                        onPressed: () =>
                                                            GroupInvitePosterSheet.show(
                                                              ctx,
                                                              groupData: group,
                                                              sessionData: s,
                                                            ),
                                                        icon: const Icon(
                                                          Icons.share_outlined,
                                                          size: 20,
                                                          color: Color(
                                                            0xFF64748B,
                                                          ),
                                                        ),
                                                        tooltip:
                                                            'เชิญเข้าร่วมรอบนี้',
                                                      ),
                                                      children: sessionChildren,
                                                    ),
                                                  );
                                                  final sessionActions =
                                                      <Widget>[];
                                                  if (canSelectAdditionalSession) {
                                                    sessionActions.add(
                                                      _responsiveSlidableAction(
                                                        onPressed: (_) {
                                                          final requiresApproval =
                                                              group['requires_owner_approval'] ==
                                                                  true &&
                                                              !isGroupOwner;
                                                          SessionPickerSheet.show(
                                                            this.pageContext,
                                                            repo: repo,
                                                            client: client,
                                                            groupId: groupId,
                                                            requiresOwnerApproval:
                                                                requiresApproval,
                                                            existingBookingStatuses:
                                                                mySessionBookingStatuses,
                                                            onPickerWillOpen:
                                                                () =>
                                                                    Navigator.pop(
                                                                      ctx,
                                                                    ),
                                                            onBook:
                                                                (
                                                                  sessionId, {
                                                                  positionId,
                                                                }) => onBook(
                                                                  sessionId,
                                                                  requiresOwnerApproval:
                                                                      requiresApproval,
                                                                  groupId:
                                                                      groupId,
                                                                  positionId:
                                                                      positionId,
                                                                ),
                                                          );
                                                        },
                                                        backgroundColor:
                                                            Colors.teal,
                                                        foregroundColor:
                                                            Colors.white,
                                                        icon: Icons
                                                            .event_available,
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
                                                            onSessionUpdated:
                                                                onPageRefresh,
                                                          );
                                                        },
                                                        backgroundColor:
                                                            AppColors.primary,
                                                        foregroundColor:
                                                            Colors.white,
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
                                                              title: const Text(
                                                                'ยกเลิกรอบนัด',
                                                              ),
                                                              content: const Text(
                                                                'ต้องการลบรอบนัดนี้ใช่หรือไม่?',
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed: () =>
                                                                      Navigator.of(
                                                                        ctx2,
                                                                      ).pop(
                                                                        false,
                                                                      ),
                                                                  child:
                                                                      const Text(
                                                                        'ยกเลิก',
                                                                      ),
                                                                ),
                                                                TextButton(
                                                                  onPressed: () =>
                                                                      Navigator.of(
                                                                        ctx2,
                                                                      ).pop(
                                                                        true,
                                                                      ),
                                                                  child:
                                                                      const Text(
                                                                        'ยืนยัน',
                                                                      ),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                          if (confirm != true)
                                                            return;
                                                          try {
                                                            final actorUserId =
                                                                currentUserId;
                                                            if (actorUserId ==
                                                                null)
                                                              return;
                                                            await repo
                                                                .cancelSession(
                                                                  s['id']
                                                                      .toString(),
                                                                  actorUserId:
                                                                      actorUserId,
                                                                );
                                                            if (!pageContext
                                                                .mounted)
                                                              return;
                                                            ScaffoldMessenger.of(
                                                              pageContext,
                                                            ).showSnackBar(
                                                              const SnackBar(
                                                                content: Text(
                                                                  'ยกเลิกรอบนัดแล้ว',
                                                                ),
                                                              ),
                                                            );
                                                            reloadSheetState(
                                                              () {},
                                                            );
                                                          } catch (e) {
                                                            if (!pageContext
                                                                .mounted)
                                                              return;
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
                                                        backgroundColor:
                                                            Colors.red,
                                                        foregroundColor:
                                                            Colors.white,
                                                        icon: Icons.event_busy,
                                                        label: 'ยกเลิก',
                                                      ),
                                                    );
                                                  }
                                                  return Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.85,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors
                                                            .grey
                                                            .shade200,
                                                        width: 1,
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withValues(
                                                                alpha: 0.02,
                                                              ),
                                                          blurRadius: 6,
                                                          offset: const Offset(
                                                            0,
                                                            2,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      child:
                                                          sessionActions.isEmpty
                                                          ? sessionTile
                                                          : Slidable(
                                                              key: ValueKey(
                                                                'session_$sessionId',
                                                              ),
                                                              endActionPane: ActionPane(
                                                                motion:
                                                                    const ScrollMotion(),
                                                                extentRatio:
                                                                    (sessionActions.length *
                                                                            0.24)
                                                                        .clamp(
                                                                          0.2,
                                                                          0.75,
                                                                        ),
                                                                children:
                                                                    sessionActions,
                                                              ),
                                                              child:
                                                                  sessionTile,
                                                            ),
                                                    ),
                                                  );
                                                },
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (endedSessions.isNotEmpty)
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: OutlinedButton(
                                            onPressed: () =>
                                                GroupSessionHistoryDialog.show(
                                                  ctx,
                                                  groupName:
                                                      group['name']
                                                          ?.toString() ??
                                                      'ก๊วน',
                                                  groupOwnerId: groupOwnerId,
                                                  sessions: endedSessions,
                                                  confirmedMembersBySession:
                                                      confirmedMembersBySession,
                                                ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  AppColors.primaryDark,
                                              side: BorderSide(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.35),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                            ),
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: const [
                                                  Icon(
                                                    Icons.history_rounded,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'รอบนัดสิ้นสุดแล้ว',
                                                    maxLines: 1,
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      _frostedCard(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 6,
                                        ),
                                        child: Theme(
                                          data: Theme.of(ctx).copyWith(
                                            dividerColor: Colors.transparent,
                                          ),
                                          child: ExpansionTile(
                                            initiallyExpanded: false,
                                            tilePadding: EdgeInsets.zero,
                                            leading: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF6366F1,
                                                ).withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.people_alt_rounded,
                                                color: Color(0xFF6366F1),
                                                size: 18,
                                              ),
                                            ),
                                            title: Row(
                                              children: [
                                                const Text(
                                                  'สมาชิกก๊วนรวม',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF1E293B),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 7,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF6366F1,
                                                    ).withValues(alpha: 0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${members.length}',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Color(0xFF6366F1),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            subtitle: const Text(
                                              'นับผู้ใช้ไม่ซ้ำ ไม่ใช่จำนวนที่นั่งของรอบนัด',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                            children: [
                                              if (memberSwipeHint != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Text(
                                                    memberSwipeHint,
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
                                                    final user =
                                                        (m['user'] as Map?) ??
                                                        {};
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
                                                    final fullName =
                                                        '$firstName $lastName'
                                                            .trim();
                                                    final image =
                                                        user['profile_image_url']
                                                            ?.toString() ??
                                                        '';
                                                    final active =
                                                        m['is_active'] == true
                                                        ? 'เข้าร่วมแล้ว'
                                                        : 'หยุดพัก';
                                                    final memberUserId =
                                                        user['id']
                                                            ?.toString() ??
                                                        m['user_id']
                                                            ?.toString() ??
                                                        '';
                                                    final role =
                                                        memberUserId ==
                                                            groupOwnerId
                                                        ? 'เจ้าของก๊วน'
                                                        : (m['role']
                                                                  ?.toString() ==
                                                              'admin')
                                                        ? 'ผู้ดูแล'
                                                        : 'สมาชิก';
                                                    final isSelf =
                                                        memberUserId ==
                                                        currentUserId;
                                                    final mentionTargetName =
                                                        isSelf ||
                                                            firstName.isEmpty
                                                        ? null
                                                        : lastName.isEmpty
                                                        ? firstName
                                                        : '$firstName ${String.fromCharCode(lastName.runes.first)}.';
                                                    final isMemberAdmin =
                                                        m['role']?.toString() ==
                                                        'admin';
                                                    // Build swipe actions
                                                    final actions = <Widget>[];
                                                    final canChat =
                                                        myJoinedGroupIds
                                                            .contains(groupId);
                                                    final isActiveMember =
                                                        m['is_active'] == true;
                                                    if (canOpenGroupChatFromMemberSwipe(
                                                          canChat: canChat,
                                                          isActiveMember:
                                                              isActiveMember,
                                                        ) &&
                                                        memberUserId
                                                            .isNotEmpty) {
                                                      actions.add(
                                                        _responsiveSlidableAction(
                                                          onPressed: (_) {
                                                            final hasReplyTarget =
                                                                !isSelf &&
                                                                memberUserId
                                                                    .isNotEmpty;
                                                            showGroupChatPopup(
                                                              pageContext,
                                                              groupId: groupId,
                                                              groupName:
                                                                  group['name']
                                                                      ?.toString() ??
                                                                  'ก๊วน',
                                                              memberCount:
                                                                  members
                                                                      .length,
                                                              mentionTargetName:
                                                                  hasReplyTarget
                                                                  ? mentionTargetName
                                                                  : null,
                                                              replyTargetUserId:
                                                                  hasReplyTarget
                                                                  ? memberUserId
                                                                  : null,
                                                              replyTargetName:
                                                                  hasReplyTarget
                                                                  ? mentionTargetName
                                                                  : null,
                                                            );
                                                          },
                                                          backgroundColor:
                                                              AppColors.primary,
                                                          foregroundColor:
                                                              Colors.white,
                                                          icon: Icons
                                                              .chat_bubble_outline,
                                                          label: 'แชท',
                                                        ),
                                                      );
                                                    }
                                                    if (isSelf &&
                                                        isGroupOwner &&
                                                        group['owner_auto_join'] !=
                                                            false &&
                                                        memberUserId
                                                            .isNotEmpty) {
                                                      actions.add(
                                                        _responsiveSlidableAction(
                                                          onPressed: (_) =>
                                                              _withdrawOwnerParticipation(
                                                                sheetContext:
                                                                    ctx,
                                                                groupId:
                                                                    groupId,
                                                                userId:
                                                                    memberUserId,
                                                              ),
                                                          backgroundColor:
                                                              Colors.red,
                                                          foregroundColor:
                                                              Colors.white,
                                                          icon: Icons
                                                              .person_remove_alt_1,
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
                                                                reloadSheetState,
                                                                onFeedRefresh:
                                                                    onFeedRefresh,
                                                              ),
                                                          backgroundColor:
                                                              Colors.grey,
                                                          foregroundColor:
                                                              Colors.white,
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
                                                                reloadSheetState,
                                                              ),
                                                          backgroundColor:
                                                              Colors.red,
                                                          foregroundColor:
                                                              Colors.white,
                                                          icon: Icons
                                                              .person_remove,
                                                          label: 'ถอดทั้งก๊วน',
                                                        ),
                                                      );
                                                    }

                                                    final tile = ListTile(
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                      leading: CircleAvatar(
                                                        backgroundImage:
                                                            image.isNotEmpty
                                                            ? NetworkImage(
                                                                image,
                                                              )
                                                            : null,
                                                        child: image.isEmpty
                                                            ? const Icon(
                                                                Icons.person,
                                                              )
                                                            : null,
                                                      ),
                                                      title: Text(
                                                        fullName.isNotEmpty
                                                            ? fullName
                                                            : 'ไม่ระบุชื่อ',
                                                      ),
                                                      subtitle: Text(
                                                        '$role · $active',
                                                      ),
                                                    );

                                                    if (actions.isEmpty)
                                                      return tile;

                                                    return Slidable(
                                                      key: ValueKey(
                                                        'member_$memberUserId',
                                                      ),
                                                      endActionPane: ActionPane(
                                                        motion:
                                                            const ScrollMotion(),
                                                        extentRatio:
                                                            actions.length *
                                                            0.2,
                                                        children: actions,
                                                      ),
                                                      child: tile,
                                                    );
                                                  },
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      _frostedCard(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _sectionHeader(
                                              icon:
                                                  Icons.card_membership_rounded,
                                              title: 'ค่าใช้จ่ายมาตรฐานก๊วน',
                                              trailing: isAdmin
                                                  ? TextButton.icon(
                                                      style:
                                                          TextButton.styleFrom(
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                            foregroundColor:
                                                                AppColors
                                                                    .primaryDark,
                                                          ),
                                                      onPressed: () {
                                                        Navigator.pop(ctx);
                                                        EditGroupSheet.show(
                                                          pageContext,
                                                          repo: repo,
                                                          client: client,
                                                          group: group,
                                                          onGroupSaved:
                                                              onPageRefresh,
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
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(height: 10),
                                            if (groupFees.isEmpty)
                                              Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade50
                                                      .withValues(alpha: 0.8),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.grey.shade200,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .info_outline_rounded,
                                                      size: 16,
                                                      color:
                                                          Colors.grey.shade500,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      'ยังไม่ได้กำหนด (ไม่มีค่าสมาชิกก๊วน)',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else
                                              for (final fee in groupFees)
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    bottom: 8,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 10,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.9),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color:
                                                          Colors.grey.shade200,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.02,
                                                            ),
                                                        blurRadius: 4,
                                                        offset: const Offset(
                                                          0,
                                                          1,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 34,
                                                        height: 34,
                                                        decoration: BoxDecoration(
                                                          color: AppColors
                                                              .primary
                                                              .withValues(
                                                                alpha: 0.12,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                9,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons
                                                              .card_membership_rounded,
                                                          size: 18,
                                                          color: AppColors
                                                              .primaryDark,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              fee['name']
                                                                      ?.toString() ??
                                                                  '',
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 13.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Color(
                                                                  0xFF1E293B,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text.rich(
                                                              TextSpan(
                                                                children: [
                                                                  TextSpan(
                                                                    text: formatBaht(
                                                                      fee['amount']
                                                                          as num?,
                                                                    ),
                                                                    style: const TextStyle(
                                                                      fontSize:
                                                                          13.5,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      color: AppColors
                                                                          .primaryDark,
                                                                    ),
                                                                  ),
                                                                  TextSpan(
                                                                    text:
                                                                        ' / ${billingPeriodLabel(fee['billing_period']?.toString())}',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      color: Colors
                                                                          .grey
                                                                          .shade600,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Flexible(
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child: paymentTimingBadge(
                                                            fee['payment_timing']
                                                                ?.toString(),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                          ],
                                        ),
                                      ),
                                      if (canViewBlockedUsers &&
                                          blockedUsers.isNotEmpty) ...[
                                        _frostedCard(
                                          backgroundColor: Colors.red.shade50
                                              .withValues(alpha: 0.35),
                                          border: Border.all(
                                            color: Colors.red.shade100,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              _sectionHeader(
                                                icon: Icons.block_rounded,
                                                title: 'ผู้ใช้ที่ถูกบล็อก',
                                                badge:
                                                    '${blockedUsers.length} คน',
                                                iconColor: Colors.red.shade700,
                                              ),
                                              const SizedBox(height: 8),
                                              ListView.separated(
                                                shrinkWrap: true,
                                                physics:
                                                    const NeverScrollableScrollPhysics(),
                                                itemCount: blockedUsers.length,
                                                separatorBuilder: (_, _) =>
                                                    const SizedBox(height: 4),
                                                itemBuilder: (ctx, i) {
                                                  final blocked =
                                                      blockedUsers[i];
                                                  final blockedUser =
                                                      (blocked['blocked_user']
                                                          as Map?) ??
                                                      {};
                                                  final name =
                                                      '${blockedUser['first_name'] ?? ''} ${blockedUser['last_name'] ?? ''}'
                                                          .trim();
                                                  final image =
                                                      blockedUser['profile_image_url']
                                                          ?.toString() ??
                                                      '';
                                                  final reason =
                                                      blocked['reason']
                                                          ?.toString();
                                                  final blockedUserId =
                                                      blocked['blocked_user_id']
                                                          ?.toString() ??
                                                      '';
                                                  final tile = ListTile(
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    leading: CircleAvatar(
                                                      backgroundImage:
                                                          image.isNotEmpty
                                                          ? NetworkImage(image)
                                                          : null,
                                                      child: image.isEmpty
                                                          ? const Icon(
                                                              Icons.person_off,
                                                            )
                                                          : null,
                                                    ),
                                                    title: Text(
                                                      name.isNotEmpty
                                                          ? name
                                                          : 'ไม่ระบุชื่อ',
                                                    ),
                                                    subtitle: Text(
                                                      reason != null &&
                                                              reason.isNotEmpty
                                                          ? 'ถูกบล็อก · เหตุผล: $reason'
                                                          : 'ถูกบล็อก',
                                                    ),
                                                  );
                                                  return Slidable(
                                                    key: ValueKey(
                                                      'blocked_$blockedUserId',
                                                    ),
                                                    endActionPane: ActionPane(
                                                      motion:
                                                          const ScrollMotion(),
                                                      extentRatio: 0.24,
                                                      children: [
                                                        _responsiveSlidableAction(
                                                          onPressed: (_) async {
                                                            try {
                                                              final actorUserId =
                                                                  currentUserId;
                                                              if (actorUserId ==
                                                                  null)
                                                                return;
                                                              await repo.unblockUser(
                                                                groupId:
                                                                    groupId,
                                                                blockedUserId:
                                                                    blockedUserId,
                                                                actorUserId:
                                                                    actorUserId,
                                                              );
                                                              if (!pageContext
                                                                  .mounted)
                                                                return;
                                                              ScaffoldMessenger.of(
                                                                pageContext,
                                                              ).showSnackBar(
                                                                SnackBar(
                                                                  content: Text(
                                                                    'ปลดบล็อก "$name" แล้ว',
                                                                  ),
                                                                ),
                                                              );
                                                              reloadSheetState(
                                                                () {},
                                                              );
                                                              await onFeedRefresh();
                                                            } catch (e) {
                                                              if (!pageContext
                                                                  .mounted)
                                                                return;
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
                                                          backgroundColor:
                                                              Colors.green,
                                                          foregroundColor:
                                                              Colors.white,
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
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                      if (isAdmin) ...[
                                        _buildShareAnalyticsCard(group),
                                        const SizedBox(height: 16),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // ── Action buttons (pinned) ──
                            _buildGroupActionButtons(
                              ctx: ctx,
                              groupId: groupId,
                              isAdmin: isAdmin,
                              isMember: myJoinedGroupIds.contains(groupId),
                              group: group,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475569)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  void _handleJoinGroup(
    BuildContext ctx,
    String groupId,
    Map<String, dynamic> group,
  ) {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) {
      // Not logged in -> save intent and redirect to login
      SportClubDeepLinkService.storePendingDeepLink(
        GroupDetailDeepLinkData(groupId: groupId),
      );
      Navigator.of(ctx).popUntil((r) => r.isFirst);
      Navigator.of(pageContext).pushNamed('/login');
      return;
    }

    // Logged in -> open session picker to join
    SessionPickerSheet.show(
      pageContext,
      repo: repo,
      client: client,
      groupId: groupId,
      requiresOwnerApproval: group['requires_owner_approval'] == true,
      onBook: (sessionId, {positionId}) => onBook(
        sessionId,
        groupId: groupId,
        positionId: positionId,
        requiresOwnerApproval: group['requires_owner_approval'] == true,
      ),
    );
  }

  Widget _buildShareAnalyticsCard(Map<String, dynamic> group) {
    final visitCount = group['share_visit_count'] ?? 0;
    final joinCount = group['share_join_count'] ?? 0;
    final lastVisitStr = group['last_shared_visit_at']?.toString();
    final conversionRate = visitCount > 0
        ? ((joinCount / visitCount) * 100).toStringAsFixed(1)
        : '0.0';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'สถิติการแชร์เชิญชวน',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem(
                'เข้าชม',
                '$visitCount',
                Icons.visibility_outlined,
              ),
              _buildStatItem(
                'กดเข้าร่วม',
                '$joinCount',
                Icons.group_add_outlined,
              ),
              _buildStatItem(
                'อัตราแปลง',
                '$conversionRate%',
                Icons.trending_up_outlined,
              ),
            ],
          ),
          if (lastVisitStr != null && lastVisitStr.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'มีผู้เข้าชมล่าสุดเมื่อ: ${formatThaiBuddhistDateTime(DateTime.parse(lastVisitStr).toLocal())}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _buildGroupActionButtons({
    required BuildContext ctx,
    required String groupId,
    required bool isAdmin,
    required bool isMember,
    required Map<String, dynamic> group,
  }) {
    final userId = AuthService.instance.currentUser?.id;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          // Join group (non-members or guests)
          if (!isMember)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _handleJoinGroup(ctx, groupId, group),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  group['is_private'] == true
                      ? 'ขอเข้าร่วมก๊วน'
                      : 'เข้าร่วมก๊วนทันที',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          // Edit group (admin only)
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
              icon: const Icon(Icons.edit_rounded, size: 17),
              label: const Text('แก้ไขก๊วน'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryDark,
                side: const BorderSide(color: AppColors.primaryDark),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          // Leave group (non-admin members only)
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
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    const SnackBar(content: Text('ออกจากก๊วนแล้ว')),
                  );
                  Navigator.pop(ctx);
                  onPageRefresh();
                } catch (e) {
                  if (!pageContext.mounted) return;
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    SnackBar(content: Text('ออกจากก๊วนไม่สำเร็จ: $e')),
                  );
                }
              },
              icon: const Icon(
                Icons.exit_to_app_rounded,
                size: 17,
                color: Colors.red,
              ),
              label: const Text(
                'ออกจากก๊วน',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.orange.shade100,
        backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
        child: image.isEmpty
            ? const Icon(Icons.person, color: Colors.orange, size: 20)
            : null,
      ),
      title: Text(
        fullName.isNotEmpty ? fullName : 'ไม่ระบุชื่อ',
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'รออนุมัติ',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                  ),
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
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
    if (!canManage) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade100),
        ),
        child: tile,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade50.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Slidable(
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
                icon: Icons.check_circle_rounded,
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
                icon: Icons.cancel_rounded,
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
                backgroundColor: Colors.grey.shade700,
                foregroundColor: Colors.white,
                icon: Icons.block_rounded,
                label: 'บล็อก',
              ),
            ],
          ),
          child: tile,
        ),
      ),
    );
  }
}
