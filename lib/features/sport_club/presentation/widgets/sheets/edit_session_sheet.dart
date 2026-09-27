import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/position_lineup.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/cost/session_cost_editor.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/sport_club_error_mapper.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';

/// Phase 4: Bottom sheet for editing an existing session — time,
/// capacity, owner position, and per-session cost items.
class EditSessionSheet {
  static Future<void> show(
    BuildContext pageContext, {
    required FitnessBuddiesRepository repo,
    required SupabaseClient client,
    required Map<String, dynamic> session,
    VoidCallback? onSessionUpdated,
  }) async {
    final actorUserId = AuthService.instance.currentUser?.id;
    if (actorUserId == null) return;

    final startsAt = DateTime.parse(session['starts_at'].toString()).toLocal();
    final endsAt = DateTime.parse(session['ends_at'].toString()).toLocal();
    DateTime editStart = startsAt;
    DateTime editEnd = endsAt;
    int editCapacity = (session['capacity'] as num?)?.toInt() ?? 5;
    final placeNameCtrl = TextEditingController(
      text: session['place_name']?.toString() ?? '',
    );
    final noteCtrl = TextEditingController(
      text: session['note']?.toString() ?? '',
    );
    final sessionId = session['id'].toString();
    final groupId = session['group_id']?.toString() ?? '';
    final costItems = <Map<String, dynamic>>[];
    try {
      final loaded = await repo.listSessionCostItems(sessionId);
      for (final it in loaded) {
        costItems.add(Map<String, dynamic>.from(it));
      }
    } catch (_) {}
    final confirmedCount = (session['confirmed_count'] as num?)?.toInt() ?? 0;
    final pendingCount = (session['pending_count'] as num?)?.toInt() ?? 0;
    final hasBookings = confirmedCount > 0 || pendingCount > 0;

    // Phase 15: load group positions, field layout, and session owner_position_id
    List<Map<String, dynamic>> groupPositions = [];
    String? fieldLayout;
    FieldStyle fieldStyle = FieldStyle.fallback;
    bool ownerAutoJoin = true;
    String? editOwnerPositionId = session['owner_position_id']?.toString();
    Map<String, int> takenCounts = {};
    try {
      final results = await Future.wait<dynamic>([
        client
            .from('fitness_groups')
            .select('owner_auto_join, sport:sports(field_layout, field_style)')
            .eq('id', groupId)
            .maybeSingle(),
        repo.listGroupPositions(groupId, activeOnly: true),
        repo.listSessionPositionAvailability([sessionId]),
      ]);
      final gRow = results[0] as Map<String, dynamic>?;
      ownerAutoJoin = gRow?['owner_auto_join'] != false;
      final sport = gRow?['sport'];
      final rawLayout = sport is Map ? sport['field_layout']?.toString() : null;
      if (sport is Map) {
        fieldStyle = FieldStyle.fromJson(sport['field_style']);
      }
      if (rawLayout == 'single' || rawLayout == 'double') {
        fieldLayout = rawLayout;
      }
      groupPositions = results[1] as List<Map<String, dynamic>>;
      final takenList = results[2] as List<Map<String, dynamic>>;
      for (final t in takenList) {
        final pid = t['position_id']?.toString() ?? '';
        final count = (t['taken_count'] as num?)?.toInt() ?? 0;
        if (pid.isNotEmpty) takenCounts[pid] = count;
      }
      if (ownerAutoJoin &&
          groupPositions.isNotEmpty &&
          editOwnerPositionId == null) {
        editOwnerPositionId = groupPositions.first['id']?.toString();
      }
    } catch (_) {}
    if (!pageContext.mounted) return;

    await showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      backgroundColor: NeumorphicTheme.baseColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          top: false,
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
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4DAE3),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.white,
                              offset: Offset(0, 1),
                              blurRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        NeumorphicContainer(
                          width: 40,
                          height: 40,
                          shape: BoxShape.circle,
                          depth: 3,
                          blur: 6,
                          child: const Icon(
                            Icons.edit_calendar_rounded,
                            color: NeumorphicTheme.primaryBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'แก้ไขรอบนัด',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: NeumorphicTheme.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    NeumorphicContainer(
                      borderRadius: 16,
                      depth: 3,
                      blur: 6,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('เวลาเริ่ม'),
                        subtitle: Text(formatThaiBuddhistDateTime(editStart)),
                        trailing: const Icon(
                          Icons.calendar_today,
                          color: NeumorphicTheme.primaryBlue,
                        ),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: ctx,
                            initialDate: editStart,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 1),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (date != null) {
                            final time = TimeOfDay.fromDateTime(editStart);
                            setSheetState(
                              () => editStart = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    NeumorphicContainer(
                      borderRadius: 16,
                      depth: 3,
                      blur: 6,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('เวลาสิ้นสุด'),
                        subtitle: Text(formatThaiBuddhistDateTime(editEnd)),
                        trailing: const Icon(
                          Icons.calendar_today,
                          color: NeumorphicTheme.primaryBlue,
                        ),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: ctx,
                            initialDate: editEnd,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 1),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (date != null) {
                            final time = TimeOfDay.fromDateTime(editEnd);
                            setSheetState(
                              () => editEnd = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    NeumorphicContainer(
                      borderRadius: 18,
                      depth: 4,
                      blur: 8,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('จำนวนผู้เข้าร่วมสูงสุดในรอบนี้'),
                              Text('$editCapacity คน'),
                            ],
                          ),
                          Slider(
                            value: editCapacity.toDouble(),
                            min: 1,
                            max: 30,
                            divisions: 29,
                            label: '$editCapacity',
                            activeColor: NeumorphicTheme.primaryBlue,
                            onChanged: (value) => setSheetState(
                              () => editCapacity = value.toInt(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    NeumorphicInsetBox(
                      height: null,
                      borderRadius: 14,
                      child: TextField(
                        controller: placeNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'สถานที่',
                          filled: true,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    if (ownerAutoJoin &&
                        groupPositions.isNotEmpty &&
                        fieldLayout != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          NeumorphicContainer(
                            width: 36,
                            height: 36,
                            shape: BoxShape.circle,
                            depth: 3,
                            blur: 6,
                            child: const Icon(
                              Icons.person_pin_circle_rounded,
                              size: 18,
                              color: NeumorphicTheme.primaryBlue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'ตำแหน่งของผู้ดูแลก๊วนในรอบนี้',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'แตะเพื่อเปลี่ยนตำแหน่งของเจ้าของก๊วนบนสนามจำลอง',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      NeumorphicContainer(
                        borderRadius: 18,
                        depth: 3,
                        blur: 6,
                        padding: const EdgeInsets.all(8),
                        child: PositionLineupView(
                          layout: fieldLayout,
                          fieldStyle: fieldStyle,
                          positions: groupPositions,
                          takenCounts: takenCounts,
                          selectedPositionId: editOwnerPositionId,
                          onPositionSelected: (posId) {
                            setSheetState(() => editOwnerPositionId = posId);
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: groupPositions.map((pos) {
                          final posId = pos['id']?.toString() ?? '';
                          final label = pos['label']?.toString() ?? '';
                          final isSelected = editOwnerPositionId == posId;
                          final color = parseHexColor(pos['color']?.toString());
                          final slots = (pos['slots'] as num?)?.toInt() ?? 1;
                          final taken = takenCounts[posId] ?? 0;
                          final isCurrentOwnerPos =
                              session['owner_position_id']?.toString() == posId;
                          final availableSlots = isCurrentOwnerPos
                              ? slots
                              : (slots - taken);
                          final isFull = availableSlots <= 0;

                          return ChoiceChip(
                            selected: isSelected,
                            avatar: CircleAvatar(
                              backgroundColor: isFull ? Colors.grey : color,
                              radius: 8,
                            ),
                            label: Text(
                              '$label (${isFull ? 'เต็ม' : 'ว่าง $availableSlots'})',
                            ),
                            selectedColor: NeumorphicTheme.primaryBlue
                                .withValues(alpha: 0.18),
                            onSelected: isFull && !isSelected
                                ? null
                                : (_) => setSheetState(
                                    () => editOwnerPositionId = posId,
                                  ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    NeumorphicContainer(
                      borderRadius: 20,
                      depth: 4,
                      blur: 8,
                      padding: const EdgeInsets.all(16),
                      child: SessionCostEditor(
                        sheetContext: ctx,
                        groupId: groupId,
                        costItems: costItems,
                        sessionHours: () {
                          return editEnd.difference(editStart).inMinutes / 60.0;
                        },
                        refresh: () => setSheetState(() {}),
                        repo: repo,
                      ),
                    ),
                    const SizedBox(height: 12),
                    NeumorphicInsetBox(
                      height: null,
                      borderRadius: 14,
                      child: TextField(
                        controller: noteCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'หมายเหตุ',
                          filled: true,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: NeumorphicVerifyButton(
                        onPressed: () async {
                          if (editEnd.isBefore(editStart) ||
                              editEnd.isAtSameMomentAs(editStart)) {
                            showFloatingManagementError(
                              ctx,
                              'เวลาสิ้นสุดต้องมาหลังเวลาเริ่ม',
                            );
                            return;
                          }
                          if (hasBookings) {
                            final confirmed = await showDialog<bool?>(
                              context: ctx,
                              builder: (dctx) => AlertDialog(
                                title: const Text('ยืนยันการแก้ไขรอบนัด'),
                                content: Text(
                                  'รอบนี้มีผู้จองแล้ว '
                                  '$confirmedCount คนยืนยัน'
                                  '${pendingCount > 0 ? ' · รออนุมัติ $pendingCount คน' : ''}'
                                  '\n\nหากแก้ไขค่าใช้จ่ายจะมีผลต่อรอบนี้ '
                                  'แต่ไม่กระทบการจองที่มีอยู่แล้ว '
                                  'ดำเนินการต่อ?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dctx, false),
                                    child: const Text('ยกเลิก'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(dctx, true),
                                    child: const Text('ดำเนินการต่อ'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                          }
                          try {
                            await repo.updateSession(
                              sessionId: sessionId,
                              actorUserId: actorUserId,
                              capacity: editCapacity,
                              startsAt: editStart,
                              endsAt: editEnd,
                              placeName: placeNameCtrl.text.trim().isEmpty
                                  ? null
                                  : placeNameCtrl.text.trim(),
                              note: noteCtrl.text.trim().isEmpty
                                  ? null
                                  : noteCtrl.text.trim(),
                              ownerPositionId:
                                  ownerAutoJoin && groupPositions.isNotEmpty
                                  ? editOwnerPositionId
                                  : null,
                              costItems: List<Map<String, dynamic>>.from(
                                costItems,
                              ),
                            );
                            if (!pageContext.mounted) return;
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              const SnackBar(content: Text('อัปเดตรอบนัดแล้ว')),
                            );
                            Navigator.pop(ctx);
                            onSessionUpdated?.call();
                          } catch (e) {
                            if (!ctx.mounted) return;
                            showFloatingManagementError(
                              ctx,
                              'อัปเดตไม่สำเร็จ: ${mapManagementError(e, sessionContext: true)}',
                            );
                          }
                        },
                        text: 'บันทึก',
                        height: 52,
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
    );
  }
}
