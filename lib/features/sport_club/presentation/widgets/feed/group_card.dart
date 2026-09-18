import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/community/find_buddies/domain/models/sport_skill_level.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/skill_level_chips.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/feed/sport_category_chips.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/create_session_sheet.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/group_detail_sheet.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/session_picker_sheet.dart';
import 'package:sheserved/features/sport_club/application/sport_club_card_hydrator.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';

/// A group card on the sport-club feed: cover, status badges, gender /
/// skill tags, fee + position summaries, next session, and Join /
/// create-session actions.
///
/// Renders synchronously from [cardData], which the page hydrates before
/// committing the group list — the card never issues repository calls in
/// [build].
class GroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final SportClubGroupCardData cardData;
  final FitnessBuddiesRepository repo;
  final SupabaseClient client;
  final Set<String> myAdminGroups;
  final Set<String> myJoinedGroupIds;
  final Set<String> myPendingGroupIds;
  final Set<String> myBlockedGroupIds;
  final VoidCallback onTap;
  final SessionBookCallback onBook;
  final VoidCallback onSessionCreated;

  const GroupCard({
    super.key,
    required this.group,
    required this.cardData,
    required this.repo,
    required this.client,
    required this.myAdminGroups,
    required this.myJoinedGroupIds,
    required this.myPendingGroupIds,
    required this.myBlockedGroupIds,
    required this.onTap,
    required this.onBook,
    required this.onSessionCreated,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Builder(
        builder: (context) {
          final coverUrl = (group['cover_image_url']?.toString() ?? '').trim();
          final hasCover = coverUrl.isNotEmpty;
          final genderPref = group['gender_preference']?.toString() ?? 'any';
          final isMalePref = genderPref == 'male';
          final genderChipColor = isMalePref ? Colors.blue : Colors.pink;
          Widget textPill(Widget child) => hasCover
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: child,
                )
              : child;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: hasCover
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              gradient: hasCover
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black38, Colors.black87],
                    )
                  : null,
              image: hasCover
                  ? DecorationImage(
                      image: NetworkImage(coverUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle(
                style: TextStyle(
                  color: hasCover ? Colors.white : Colors.black87,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if ((group['sport_name']?.toString() ?? '')
                                  .isNotEmpty)
                                textPill(
                                  SportChipLabel(
                                    icon: group['sport_icon']?.toString(),
                                    label: group['sport_name'].toString(),
                                  ),
                                ),
                              if ((group['sport_name']?.toString() ?? '')
                                  .isNotEmpty)
                                const SizedBox(width: 6),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: textPill(
                                    Text(
                                      group['name']?.toString() ?? '',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (genderPref != 'any')
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: hasCover
                                  ? Colors.black.withValues(alpha: 0.5)
                                  : genderChipColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: hasCover
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : genderChipColor.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              isMalePref ? 'ช.' : 'ญ.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: hasCover
                                    ? Colors.white
                                    : isMalePref
                                    ? Colors.blue.shade700
                                    : Colors.pink.shade700,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: hasCover
                                  ? Colors.black.withValues(alpha: 0.5)
                                  : Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: hasCover
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : Colors.green.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              'เสรี',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: hasCover
                                    ? Colors.white
                                    : Colors.green.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if ((group['description']?.toString() ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: textPill(
                          Text(
                            group['description'].toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    if ((group['province']?.toString() ?? '').isNotEmpty)
                      textPill(
                        Text(
                          'พื้นที่: ${group['province']}${group['district'] != null && group['district'].toString().isNotEmpty ? ' · ${group['district']}' : ''}',
                        ),
                      ),
                    const SizedBox(height: 8),
                    _renderDetail(
                      context,
                      hasCover: hasCover,
                      textPill: textPill,
                      items: cardData.upcomingSessions,
                      hasAnySessions: cardData.hasAnySessions,
                      groupFees: cardData.groupFees,
                      costItemsBySession: cardData.costItemsBySession,
                      groupPositions: cardData.groupPositions,
                      error: cardData.sessionError,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _renderDetail(
    BuildContext context, {
    required bool hasCover,
    required Widget Function(Widget child) textPill,
    required List<Map<String, dynamic>> items,
    required bool hasAnySessions,
    required List<Map<String, dynamic>> groupFees,
    required Map<String, List<Map<String, dynamic>>> costItemsBySession,
    required List<Map<String, dynamic>> groupPositions,
    required Object? error,
  }) {
    if (error != null) {
      return Text(
        'โหลดรอบนัดไม่สำเร็จ: $error',
        style: const TextStyle(color: Colors.red),
      );
    }
    final sortedItems = [...items]
      ..sort((a, b) {
        final aStart = DateTime.tryParse(a['starts_at']?.toString() ?? '');
        final bStart = DateTime.tryParse(b['starts_at']?.toString() ?? '');
        if (aStart == null && bStart == null) return 0;
        if (aStart == null) return 1;
        if (bStart == null) return -1;
        return aStart.compareTo(bStart);
      });
    final gid = group['id']?.toString() ?? '';
                        if (items.isEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              textPill(
                                Text(
                                  hasAnySessions
                                      ? 'รอบนัดล่าสุดสิ้นสุดแล้ว'
                                      : 'ยังไม่มีรอบนัด',
                                ),
                              ),
                              if (groupFees.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: textPill(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.card_membership_rounded,
                                          size: 13,
                                          color: hasCover
                                              ? Colors.white70
                                              : AppColors.primaryDark,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'ค่าก๊วน: ${groupFeeSummary(groupFees)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: hasCover
                                                ? Colors.white70
                                                : Colors.grey[800],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (groupPositions.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: textPill(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.sports_soccer_rounded,
                                          size: 13,
                                          color: hasCover
                                              ? Colors.white70
                                              : AppColors.primaryDark,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'รับตำแหน่ง: ${groupPositions.take(3).map((p) => "${p['label']}×${p['slots']}").join(' · ')}${groupPositions.length > 3 ? ' ...' : ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: hasCover
                                                ? Colors.white70
                                                : Colors.grey[800],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: SkillLevelBadge(
                                  targetSkillLevels:
                                      (group['target_skill_levels'] is List)
                                      ? (group['target_skill_levels'] as List)
                                            .map((e) => e.toString())
                                            .toList()
                                      : null,
                                  availableLevels: resolveSkillLevelsForSport(
                                    sportData:
                                        group['sport'] is Map<String, dynamic>
                                        ? group['sport']
                                        : null,
                                  ),
                                ),
                              ),
                              if (myBlockedGroupIds.contains(gid))
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.hourglass_empty),
                                    label: const Text('รอคิว'),
                                  ),
                                ),
                              if (AuthService.instance.currentUser?.isAdmin ==
                                      true ||
                                  myAdminGroups.contains(gid))
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => CreateSessionSheet.show(
                                      context,
                                      repo: repo,
                                      client: client,
                                      groupId: group['id'].toString(),
                                      onSessionCreated: onSessionCreated,
                                    ),
                                    icon: const Icon(Icons.add_circle_outline),
                                    label: const Text('เพิ่มรอบนัด'),
                                  ),
                                ),
                            ],
                          );
                        }
                        final isAdmin =
                            AuthService.instance.currentUser?.isAdmin == true ||
                            myAdminGroups.contains(gid);
                        final cardUserId = AuthService.instance.currentUser?.id;
                        final isGroupOwner =
                            cardUserId != null &&
                            (group['created_by']?.toString() ?? '')
                                .isNotEmpty &&
                            group['created_by']?.toString() == cardUserId;
                        final hasJoined = myJoinedGroupIds.contains(gid);
                        final hasPending = myPendingGroupIds.contains(gid);
                        final hasBlocked = myBlockedGroupIds.contains(gid);
                        final requiresOwnerApproval =
                            group['requires_owner_approval'] == true &&
                            !isGroupOwner;
                        final joinButton = hasBlocked
                            ? TextButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.hourglass_empty),
                                label: const Text('รอคิว'),
                              )
                            : hasJoined
                            ? TextButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('เข้าร่วมก๊วนแล้ว'),
                              )
                            : hasPending && !isGroupOwner
                            ? TextButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.hourglass_empty),
                                label: const Text('รออนุมัติ'),
                              )
                            : TextButton.icon(
                                onPressed: () => SessionPickerSheet.show(
                                  context,
                                  repo: repo,
                                  client: client,
                                  groupId: gid,
                                  requiresOwnerApproval: requiresOwnerApproval,
                                  onBook: (sessionId, {positionId}) => onBook(
                                    sessionId,
                                    requiresOwnerApproval:
                                        requiresOwnerApproval,
                                    groupId: gid,
                                    positionId: positionId,
                                  ),
                                ),
                                icon: const Icon(Icons.event_available),
                                label: Text(
                                  isGroupOwner
                                      ? 'กลับเข้าร่วมก๊วน'
                                      : requiresOwnerApproval
                                      ? 'ขอเข้าร่วมก๊วน'
                                      : 'เข้าร่วมก๊วน',
                                ),
                              );
                        final hasCosts =
                            groupFees.isNotEmpty ||
                            costItemsBySession.values.any(
                              (items) => items.isNotEmpty,
                            );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasCosts)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: textPill(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.receipt_long_rounded,
                                        size: 13,
                                        color: hasCover
                                            ? Colors.white70
                                            : AppColors.primaryDark,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'มีค่าใช้จ่าย กดเพื่อแสดงรายละเอียด',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: hasCover
                                              ? Colors.white70
                                              : Colors.grey[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (groupPositions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: textPill(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.sports_soccer_rounded,
                                        size: 13,
                                        color: hasCover
                                            ? Colors.white70
                                            : AppColors.primaryDark,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'รับตำแหน่ง: ${groupPositions.take(3).map((p) => "${p['label']}×${p['slots']}").join(' · ')}${groupPositions.length > 3 ? ' ...' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: hasCover
                                              ? Colors.white70
                                              : Colors.grey[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            for (final s in sortedItems.take(3))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: textPill(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              'รอบ: ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Flexible(
                                              child: Text(
                                                formatThaiSessionRange(
                                                  DateTime.parse(
                                                    s['starts_at'].toString(),
                                                  ).toLocal(),
                                                  DateTime.parse(
                                                    s['ends_at'].toString(),
                                                  ).toLocal(),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: textPill(
                                          Text(
                                            sessionCapacitySummary(s),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: hasCover
                                                  ? Colors.white70
                                                  : Colors.grey,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (sortedItems.length > 3)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Center(
                                  child: textPill(
                                    const Text('กดเพื่อแสดงรอบอื่น ๆ'),
                                  ),
                                ),
                              ),
                            if (isAdmin)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  joinButton,
                                  TextButton.icon(
                                    onPressed: () => CreateSessionSheet.show(
                                      context,
                                      repo: repo,
                                      client: client,
                                      groupId: group['id'].toString(),
                                      onSessionCreated: onSessionCreated,
                                    ),
                                    icon: const Icon(Icons.add_circle_outline),
                                    label: const Text('เพิ่มรอบนัด'),
                                  ),
                                ],
                              )
                            else
                              Align(
                                alignment: Alignment.centerRight,
                                child: joinButton,
                              ),
                          ],
                        );
  }
}
