import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/position_lineup.dart';
import 'package:sheserved/features/community/find_buddies/domain/models/sport_skill_level.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/skill_level_chips.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/cost/group_cost_manager.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/sport_club_error_mapper.dart';

/// Bottom sheet for editing a group: name, description, privacy,
/// skill levels, cost standards, and field layout (1 ฝั่ง / 2 ฝั่ง).
class EditGroupSheet {
  static Future<void> show(
    BuildContext pageContext, {
    required FitnessBuddiesRepository repo,
    required SupabaseClient client,
    required Map<String, dynamic> group,
    VoidCallback? onGroupSaved,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;

    final nameCtrl = TextEditingController(
      text: group['name']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(
      text: group['description']?.toString() ?? '',
    );
    String genderPref = group['gender_preference']?.toString() ?? 'any';
    List<String> targetSkillLevels = (group['target_skill_levels'] is List)
        ? (group['target_skill_levels'] as List)
              .map((e) => e.toString())
              .toList()
        : ['all'];
    final skillNoteCtrl = TextEditingController(
      text: group['skill_level_note']?.toString() ?? '',
    );
    final originalOwnerAutoJoin = group['owner_auto_join'] != false;
    final isGroupOwner = group['created_by']?.toString() == userId;
    bool requiresApproval = group['requires_owner_approval'] == true;
    bool ownerAutoJoin = originalOwnerAutoJoin;
    final groupId = group['id'].toString();
    var costStandards = <Map<String, dynamic>>[];
    var groupPositions = <Map<String, dynamic>>[];
    String? fieldLayout;
    FieldStyle fieldStyle = FieldStyle.fallback;
    Map<String, dynamic>? sportData;
    try {
      final results = await Future.wait<dynamic>([
        repo.listGroupCostStandards(groupId),
        repo.listGroupPositions(groupId, activeOnly: true),
        client
            .from('fitness_groups')
            .select(
              'field_layout, sport:sports(field_layout, field_style, skill_levels, name_th, name_en)',
            )
            .eq('id', groupId)
            .maybeSingle(),
      ]);
      costStandards = results[0] as List<Map<String, dynamic>>;
      groupPositions = results[1] as List<Map<String, dynamic>>;
      final gRow = results[2] as Map<String, dynamic>?;
      final sport = gRow?['sport'];
      if (sport is Map<String, dynamic>) {
        sportData = sport;
        fieldStyle = FieldStyle.fromJson(sport['field_style']);
        final groupLayout = gRow?['field_layout']?.toString();
        final rawLayout = sport['field_layout']?.toString();
        if (rawLayout == 'single' || rawLayout == 'double') {
          fieldLayout = groupLayout ?? rawLayout;
        }
      }
    } catch (_) {}
    if (!pageContext.mounted) return;

    await showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'แก้ไขก๊วน',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อก๊วน',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'คำอธิบาย',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: genderPref,
                        decoration: const InputDecoration(
                          labelText: 'เพศที่ต้องการชวน',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'any', child: Text('ทุกเพศ')),
                          DropdownMenuItem(value: 'male', child: Text('ชาย')),
                          DropdownMenuItem(
                            value: 'female',
                            child: Text('หญิง'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setSheetState(() => genderPref = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('ก๊วนส่วนตัว (ต้องรออนุมัติ)'),
                        value: requiresApproval,
                        onChanged: (v) =>
                            setSheetState(() => requiresApproval = v),
                      ),
                      if (isGroupOwner) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('เข้าร่วมทุกรอบอัตโนมัติ'),
                          subtitle: const Text(
                            'เปิดแล้วจะจองรอบนัดที่กำลังจะถึงให้เจ้าของก๊วนโดยอัตโนมัติ',
                          ),
                          value: ownerAutoJoin,
                          onChanged: (v) =>
                              setSheetState(() => ownerAutoJoin = v),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SkillLevelSelector(
                        availableLevels: resolveSkillLevelsForSport(
                          sportData: sportData,
                        ),
                        selectedLevels: targetSkillLevels,
                        onLevelsChanged: (lvls) {
                          setSheetState(() => targetSkillLevels = lvls);
                        },
                        noteController: skillNoteCtrl,
                      ),
                      const Divider(height: 24),
                      GroupCostManager(
                        sheetContext: ctx,
                        groupId: groupId,
                        actorUserId: userId,
                        standards: costStandards,
                        refresh: () async {
                          try {
                            costStandards = await repo.listGroupCostStandards(
                              groupId,
                            );
                          } catch (_) {}
                          setSheetState(() {});
                        },
                        repo: repo,
                      ),
                      if (fieldLayout != null) ...[
                        const Divider(height: 24),
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
                                Icons.sports_soccer_rounded,
                                size: 16,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'จัดการตำแหน่งผู้เล่นบนสนาม',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'แก้ไขตำแหน่งผู้เล่นบนสนามจำลองของก๊วน (กดบันทึกเพื่อบันทึกการเปลี่ยนแปลงทั้งหมด)',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        if (sportData?['field_layout'] != null &&
                            sportData?['field_layout'] != 'none') ...[
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'single',
                                  label: Text('ครึ่งสนาม (1 ฝั่ง)'),
                                ),
                                ButtonSegment(
                                  value: 'double',
                                  label: Text('เต็มสนาม (2 ฝั่ง)'),
                                ),
                              ],
                              selected: {fieldLayout ?? 'double'},
                              onSelectionChanged: (Set<String> newSelection) {
                                setSheetState(() {
                                  fieldLayout = newSelection.first;
                                  // Reset positions draft because the layout changed
                                  groupPositions.clear();
                                });
                              },
                              style: ButtonStyle(
                                backgroundColor:
                                    WidgetStateProperty.resolveWith<Color>((
                                      Set<WidgetState> states,
                                    ) {
                                      if (states.contains(
                                        WidgetState.selected,
                                      )) {
                                        return AppColors.primary.withValues(
                                          alpha: 0.1,
                                        );
                                      }
                                      return Colors.transparent;
                                    }),
                                side: WidgetStateProperty.all(
                                  BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        PositionLineupEditor(
                          layout: fieldLayout!,
                          fieldStyle: fieldStyle,
                          positions: groupPositions,
                          onChanged: (updated) {
                            groupPositions = updated;
                          },
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('กรุณากรอกชื่อก๊วน'),
                                ),
                              );
                              return;
                            }
                            var cancelOwnerBookings = false;
                            if (isGroupOwner &&
                                originalOwnerAutoJoin &&
                                !ownerAutoJoin) {
                              final choice = await showDialog<bool?>(
                                context: ctx,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('ปิดการเข้าร่วมอัตโนมัติ'),
                                  content: const Text(
                                    'ต้องการจัดการ booking ของ owner ในรอบอนาคตอย่างไร?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: const Text('ยกเลิก'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('คงการจองเดิม'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
                                      child: const Text('ยกเลิกการจองอนาคต'),
                                    ),
                                  ],
                                ),
                              );
                              if (!ctx.mounted || choice == null) return;
                              cancelOwnerBookings = choice;
                            }
                            try {
                              await repo.updateGroup(
                                groupId: group['id'].toString(),
                                userId: userId,
                                name: name,
                                description: descCtrl.text.trim().isEmpty
                                    ? null
                                    : descCtrl.text.trim(),
                                ownerAutoJoin: ownerAutoJoin,
                                cancelOwnerBookings: cancelOwnerBookings,
                                genderPreference: genderPref,
                                requiresOwnerApproval: requiresApproval,
                                targetSkillLevels: targetSkillLevels,
                                skillLevelNote:
                                    skillNoteCtrl.text.trim().isEmpty
                                    ? null
                                    : skillNoteCtrl.text.trim(),
                                fieldLayout: fieldLayout,
                              );
                              if (fieldLayout != null) {
                                await repo.replaceGroupPositions(
                                  groupId: groupId,
                                  actorUserId: userId,
                                  positions: groupPositions,
                                );
                              }
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('อัปเดตก๊วนแล้ว')),
                              );
                              Navigator.pop(ctx);
                              onGroupSaved?.call();
                            } catch (e) {
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'อัปเดตไม่สำเร็จ: ${mapManagementError(e)}',
                                  ),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('บันทึก'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
