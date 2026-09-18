import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/cost_editors.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/position_lineup.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';

/// Bottom sheet listing upcoming sessions for a group; lets the user
/// pick a session (and a field position when required) to book.
class SessionPickerSheet {
  static Future<void> show(
    BuildContext pageContext, {
    required FitnessBuddiesRepository repo,
    required SupabaseClient client,
    required String groupId,
    required bool requiresOwnerApproval,
    required Future<void> Function(String sessionId, {String? positionId})
    onBook,
  }) async {
    final sessions = await repo.listUpcomingSessions(groupId);
    final sessionIds = sessions
        .map((s) => s['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    var costItemsBySession = <String, List<Map<String, dynamic>>>{};
    List<Map<String, dynamic>> groupPositions = [];
    String? fieldLayout;
    FieldStyle fieldStyle = FieldStyle.fallback;
    Map<String, Map<String, int>> sessionPositionTaken =
        {}; // session_id -> (position_id -> count)

    try {
      final results = await Future.wait<dynamic>([
        repo.listPublicSessionCostItems(sessionIds),
        repo.listPublicGroupPositions(groupId),
        repo.listSessionPositionAvailability(sessionIds),
        client
            .from('fitness_groups')
            .select('sport:sports(field_layout, field_style)')
            .eq('id', groupId)
            .maybeSingle(),
      ]);
      final allItems = results[0] as List<Map<String, dynamic>>;
      for (final item in allItems) {
        final sid = item['session_id']?.toString() ?? '';
        if (sid.isNotEmpty) {
          costItemsBySession.putIfAbsent(sid, () => []).add(item);
        }
      }
      groupPositions = results[1] as List<Map<String, dynamic>>;
      final takenList = results[2] as List<Map<String, dynamic>>;
      for (final t in takenList) {
        final sid = t['session_id']?.toString() ?? '';
        final pid = t['position_id']?.toString() ?? '';
        final count = (t['taken_count'] as num?)?.toInt() ?? 0;
        if (sid.isNotEmpty && pid.isNotEmpty) {
          sessionPositionTaken.putIfAbsent(sid, () => {})[pid] = count;
        }
      }
      final gRow = results[3] as Map<String, dynamic>?;
      final sport = gRow?['sport'];
      final rawLayout = sport is Map ? sport['field_layout']?.toString() : null;
      if (sport is Map) {
        fieldStyle = FieldStyle.fromJson(sport['field_style']);
      }
      if (rawLayout == 'single' || rawLayout == 'double') {
        fieldLayout = rawLayout;
      }
    } catch (_) {}
    if (!pageContext.mounted) return;
    if (sessions.isEmpty) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text('ยังไม่มีรอบนัดให้เข้าร่วม')),
      );
      return;
    }
    await showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.event_available_rounded,
                        color: AppColors.primaryDark,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'เลือกรอบนัดที่ต้องการเข้าร่วม',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final s = sessions[i];
                      final startsAt = DateTime.parse(
                        s['starts_at'].toString(),
                      ).toLocal();
                      final endsAt = DateTime.parse(
                        s['ends_at'].toString(),
                      ).toLocal();
                      final note = s['note']?.toString();
                      final capacity = (s['capacity'] as num?)?.toInt() ?? 0;
                      final confirmedCount =
                          (s['confirmed_count'] as num?)?.toInt() ?? 0;
                      final pendingCount =
                          (s['pending_count'] as num?)?.toInt() ?? 0;
                      final availableCount =
                          (s['available_count'] as num?)?.toInt() ??
                          (capacity - confirmedCount).clamp(0, capacity);
                      final isFull = capacity > 0 && availableCount <= 0;
                      final sessionCostItems =
                          costItemsBySession[s['id']?.toString() ?? ''] ??
                          const <Map<String, dynamic>>[];

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isFull
                                ? Colors.grey.shade300
                                : AppColors.primary.withValues(alpha: 0.35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: isFull
                                ? null
                                : () async {
                                    if (groupPositions.isNotEmpty &&
                                        fieldLayout != null) {
                                      // Position picker flow
                                      final takenMap =
                                          sessionPositionTaken[s['id']
                                              ?.toString()] ??
                                          {};
                                      final chosenPosId = await showModalBottomSheet<String>(
                                        context: pageContext,
                                        isScrollControlled: true,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(24),
                                          ),
                                        ),
                                        builder: (bctx) {
                                          String? tempSelectedId;
                                          return StatefulBuilder(
                                            builder: (bctx, setModalState) {
                                              return SafeArea(
                                                top: false,
                                                child: Padding(
                                                  padding: EdgeInsets.only(
                                                    left: 16,
                                                    right: 16,
                                                    top: 14,
                                                    bottom:
                                                        MediaQuery.of(
                                                          bctx,
                                                        ).viewInsets.bottom +
                                                        20,
                                                  ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Center(
                                                        child: Container(
                                                          width: 40,
                                                          height: 4,
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .grey
                                                                .shade300,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  2,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Row(
                                                        children: [
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  8,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: AppColors
                                                                  .primary
                                                                  .withValues(
                                                                    alpha: 0.15,
                                                                  ),
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                            child: const Icon(
                                                              Icons
                                                                  .sports_soccer_rounded,
                                                              color: AppColors
                                                                  .primaryDark,
                                                              size: 20,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 10,
                                                          ),
                                                          const Expanded(
                                                            child: Text(
                                                              'เลือกตำแหน่งที่ต้องการเล่น',
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      const Text(
                                                        'แตะหมุดบนสนามจำลอง หรือเลือกจากรายการด้านล่าง',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      PositionLineupView(
                                                        layout: fieldLayout!,
                                                        fieldStyle: fieldStyle,
                                                        positions:
                                                            groupPositions,
                                                        takenCounts: takenMap,
                                                        selectedPositionId:
                                                            tempSelectedId,
                                                        onPositionSelected: (pid) {
                                                          setModalState(
                                                            () =>
                                                                tempSelectedId =
                                                                    pid,
                                                          );
                                                        },
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        children: groupPositions.map((
                                                          pos,
                                                        ) {
                                                          final pid =
                                                              pos['id']
                                                                  ?.toString() ??
                                                              '';
                                                          final label =
                                                              pos['label']
                                                                  ?.toString() ??
                                                              '';
                                                          final slots =
                                                              (pos['slots']
                                                                      as num?)
                                                                  ?.toInt() ??
                                                              1;
                                                          final taken =
                                                              takenMap[pid] ??
                                                              0;
                                                          final remaining =
                                                              slots - taken;
                                                          final isFullPos =
                                                              remaining <= 0;
                                                          final isSelected =
                                                              tempSelectedId ==
                                                              pid;
                                                          final color =
                                                              parseHexColor(
                                                                pos['color']
                                                                    ?.toString(),
                                                              );

                                                          return ChoiceChip(
                                                            selected:
                                                                isSelected,
                                                            avatar: CircleAvatar(
                                                              backgroundColor:
                                                                  isFullPos
                                                                  ? Colors.grey
                                                                  : color,
                                                              radius: 8,
                                                            ),
                                                            label: Text(
                                                              '$label (${isFullPos ? 'เต็ม' : 'ว่าง $remaining'})',
                                                            ),
                                                            selectedColor:
                                                                AppColors
                                                                    .primary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.25,
                                                                    ),
                                                            onSelected:
                                                                isFullPos
                                                                ? null
                                                                : (
                                                                    _,
                                                                  ) => setModalState(
                                                                    () =>
                                                                        tempSelectedId =
                                                                            pid,
                                                                  ),
                                                          );
                                                        }).toList(),
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),
                                                      SizedBox(
                                                        width: double.infinity,
                                                        height: 48,
                                                        child: ElevatedButton(
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                AppColors
                                                                    .primary,
                                                            foregroundColor:
                                                                Colors.white,
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                          ),
                                                          onPressed:
                                                              tempSelectedId ==
                                                                  null
                                                              ? null
                                                              : () => Navigator.pop(
                                                                  bctx,
                                                                  tempSelectedId,
                                                                ),
                                                          child: const Text(
                                                            'ยืนยันตำแหน่งนี้',
                                                            style: TextStyle(
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      );
                                      if (chosenPosId == null) return;
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      onBook(
                                        s['id'].toString(),
                                        positionId: chosenPosId,
                                      );
                                    } else {
                                      Navigator.pop(ctx);
                                      onBook(s['id'].toString());
                                    }
                                  },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isFull
                                              ? Colors.grey.shade200
                                              : AppColors.primary.withValues(
                                                  alpha: 0.15,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.calendar_today_rounded,
                                          size: 18,
                                          color: isFull
                                              ? Colors.grey.shade600
                                              : AppColors.primaryDark,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              formatThaiSessionRange(
                                                startsAt,
                                                endsAt,
                                              ),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: isFull
                                                    ? Colors.grey.shade600
                                                    : Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'ยืนยันแล้ว $confirmedCount / $capacity คน'
                                              '${pendingCount > 0 ? ' · รออนุมัติ $pendingCount คน' : ''}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isFull
                                              ? Colors.red.shade50
                                              : Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: isFull
                                                ? Colors.red.shade200
                                                : Colors.green.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          isFull
                                              ? 'เต็ม'
                                              : 'เหลือ $availableCount ที่',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isFull
                                                ? Colors.red.shade700
                                                : Colors.green.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (note != null && note.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'หมายเหตุ: $note',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                  if (sessionCostItems.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final item in sessionCostItems)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 4,
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    costCategoryIcon(
                                                      item['category']
                                                          ?.toString(),
                                                    ),
                                                    size: 14,
                                                    color:
                                                        AppColors.primaryDark,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      '${item['name']}: ${sessionCostItemSummary(item)}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  paymentTimingBadge(
                                                    item['payment_timing']
                                                        ?.toString(),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const Divider(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'ค่าใช้จ่ายรอบนี้รวมโดยประมาณ',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              Text(
                                                '~${formatBaht(sessionCostItemsTotal(sessionCostItems))}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primaryDark,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          isFull
                                              ? 'รอบนี้เต็มแล้ว'
                                              : (requiresOwnerApproval
                                                    ? 'กดเพื่อส่งคำขอเข้าร่วม'
                                                    : 'กดเพื่อเข้าร่วมรอบนี้'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isFull
                                                ? Colors.grey.shade500
                                                : AppColors.primaryDark,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 15,
                                          color: isFull
                                              ? Colors.grey.shade500
                                              : AppColors.primaryDark,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
