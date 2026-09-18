import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/position_lineup.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';

/// Dialog/sheet for changing a confirmed participant's field position.
class ChangePositionDialog {
  static Future<void> show({
    required BuildContext pageContext,
    required BuildContext sheetContext,
    required FitnessBuddiesRepository repo,
    required SupabaseClient client,
    required String bookingId,
    required String sessionId,
    required String groupId,
    required StateSetter setSheetState,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      final results = await Future.wait<dynamic>([
        repo.listPublicGroupPositions(groupId),
        repo.listSessionPositionAvailability([sessionId]),
        client
            .from('fitness_groups')
            .select('sport:sports(field_layout, field_style)')
            .eq('id', groupId)
            .maybeSingle(),
      ]);
      final positions = results[0] as List<Map<String, dynamic>>;
      final takenList = results[1] as List<Map<String, dynamic>>;
      final gRow = results[2] as Map<String, dynamic>?;
      final sport = gRow?['sport'];
      final layout = sport is Map
          ? sport['field_layout']?.toString()
          : 'single';
      final fStyle = sport is Map
          ? FieldStyle.fromJson(sport['field_style'])
          : FieldStyle.fallback;

      final takenMap = <String, int>{};
      for (final t in takenList) {
        final pid = t['position_id']?.toString() ?? '';
        final count = (t['taken_count'] as num?)?.toInt() ?? 0;
        if (pid.isNotEmpty) takenMap[pid] = count;
      }

      if (!sheetContext.mounted) return;
      final newPosId = await showModalBottomSheet<String>(
        context: sheetContext,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (bctx) {
          String? selectedPos;
          return StatefulBuilder(
            builder: (bctx, setModalState) {
              return SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 14,
                    bottom: MediaQuery.of(bctx).viewInsets.bottom + 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.swap_horiz_rounded,
                              color: AppColors.primaryDark,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'เปลี่ยนตำแหน่งบนสนาม',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      PositionLineupView(
                        layout: layout ?? 'single',
                        fieldStyle: fStyle,
                        positions: positions,
                        takenCounts: takenMap,
                        selectedPositionId: selectedPos,
                        onPositionSelected: (pid) {
                          setModalState(() => selectedPos = pid);
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: positions.map((pos) {
                          final pid = pos['id']?.toString() ?? '';
                          final label = pos['label']?.toString() ?? '';
                          final slots = (pos['slots'] as num?)?.toInt() ?? 1;
                          final taken = takenMap[pid] ?? 0;
                          final remaining = slots - taken;
                          final isFull = remaining <= 0;
                          final isSelected = selectedPos == pid;
                          final color = parseHexColor(pos['color']?.toString());

                          return ChoiceChip(
                            selected: isSelected,
                            avatar: CircleAvatar(
                              backgroundColor: isFull ? Colors.grey : color,
                              radius: 8,
                            ),
                            label: Text(
                              '$label (${isFull ? 'เต็ม' : 'ว่าง $remaining'})',
                            ),
                            selectedColor: AppColors.primary.withValues(
                              alpha: 0.25,
                            ),
                            onSelected: isFull
                                ? null
                                : (_) => setModalState(() => selectedPos = pid),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: selectedPos == null
                              ? null
                              : () => Navigator.pop(bctx, selectedPos),
                          child: const Text(
                            'บันทึกการเปลี่ยนตำแหน่ง',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
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
      if (newPosId == null) return;
      await repo.setBookingPosition(
        bookingId: bookingId,
        userId: user.id,
        positionId: newPosId,
      );
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(const SnackBar(content: Text('เปลี่ยนตำแหน่งสำเร็จแล้ว')));
      setSheetState(() {});
    } catch (e) {
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(
          content: Text('เปลี่ยนตำแหน่งไม่สำเร็จ: ${mapBookingError(e)}'),
        ),
      );
    }
  }
}
