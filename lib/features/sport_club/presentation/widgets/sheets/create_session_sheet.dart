import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/position_lineup.dart';
import 'package:sheserved/shared/widgets/thai_buddhist_date_picker.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/cost/session_cost_editor.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/sport_club_error_mapper.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';

/// Bottom sheet for creating a new session (รอบนัด) in a group,
/// including owner position selection and per-session cost items.
class CreateSessionSheet {
  static Future<void> show(
    BuildContext pageContext, {
    required FitnessBuddiesRepository repo,
    required SupabaseClient client,
    required String groupId,
    Future<void>? refreshFuture,
    VoidCallback? onSessionCreated,
  }) async {
    final actorUserId = AuthService.instance.currentUser?.id;
    if (actorUserId == null) return;

    final now = DateTime.now();
    // ปัดขึ้นครึ่งชั่วโมงถัดไป
    final roundedStart = roundUpToNearest(now.add(const Duration(minutes: 15)));
    DateTime selectedDate = DateTime(
      roundedStart.year,
      roundedStart.month,
      roundedStart.day,
    );
    TimeOfDay startTime = TimeOfDay(
      hour: roundedStart.hour,
      minute: roundedStart.minute,
    );
    TimeOfDay endTime = TimeOfDay(
      hour: (roundedStart.add(const Duration(hours: 1))).hour,
      minute: roundedStart.minute,
    );
    final noteCtrl = TextEditingController();
    int capacity = 5;
    final costItems = <Map<String, dynamic>>[];
    String? errorText;
    bool submitting = false;
    bool waitingForRefresh = refreshFuture != null;
    var refreshListenerAttached = false;

    // Phase 15: load group positions, field layout, and owner auto join state
    List<Map<String, dynamic>> groupPositions = [];
    String? fieldLayout;
    FieldStyle fieldStyle = FieldStyle.fallback;
    bool ownerAutoJoin = true;
    String? selectedOwnerPositionId;
    try {
      final results = await Future.wait<dynamic>([
        client
            .from('fitness_groups')
            .select('owner_auto_join, sport:sports(field_layout, field_style)')
            .eq('id', groupId)
            .maybeSingle(),
        repo.listGroupPositions(groupId, activeOnly: true),
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
      if (ownerAutoJoin && groupPositions.isNotEmpty) {
        selectedOwnerPositionId = groupPositions.first['id']?.toString();
      }
    } catch (_) {}
    if (!pageContext.mounted) return;

    await showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (refreshFuture != null && !refreshListenerAttached) {
              refreshListenerAttached = true;
              refreshFuture.then(
                (_) {
                  if (!ctx.mounted) return;
                  setModalState(() => waitingForRefresh = false);
                },
                onError: (Object error, StackTrace stackTrace) {
                  if (!ctx.mounted) return;
                  setModalState(() => waitingForRefresh = false);
                },
              );
            }

            Future<void> pickStartTime() async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: startTime,
              );
              if (picked == null) return;

              final previousStart = dateTimeAt(selectedDate, startTime);
              final previousEnd = endDateTimeAt(
                selectedDate,
                startTime,
                endTime,
              );
              final proposedStart = dateTimeAt(selectedDate, picked);
              final earliest = roundUpToNearest(
                DateTime.now().add(const Duration(minutes: 15)),
              );
              final actualStart = proposedStart.isBefore(earliest)
                  ? earliest
                  : proposedStart;
              DateTime actualEnd;
              if (actualStart != proposedStart) {
                var proposedEnd = dateTimeAt(selectedDate, endTime);
                if (!proposedEnd.isAfter(proposedStart)) {
                  proposedEnd = proposedEnd.add(const Duration(days: 1));
                }
                final duration = proposedEnd.difference(proposedStart);
                actualEnd = actualStart.add(
                  duration.isNegative || duration == Duration.zero
                      ? const Duration(hours: 1)
                      : duration,
                );
              } else {
                final shift = actualStart.difference(previousStart);
                actualEnd = previousEnd.add(shift);
              }
              if (!actualEnd.isAfter(actualStart)) {
                actualEnd = actualStart.add(const Duration(hours: 1));
              }

              setModalState(() {
                selectedDate = DateTime(
                  actualStart.year,
                  actualStart.month,
                  actualStart.day,
                );
                startTime = TimeOfDay.fromDateTime(actualStart);
                endTime = TimeOfDay.fromDateTime(actualEnd);
              });
            }

            Future<void> pickEndTime() async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: endTime,
              );
              if (picked != null) {
                final proposedEnd = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  picked.hour,
                  picked.minute,
                );
                final currentStart = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  startTime.hour,
                  startTime.minute,
                );
                if (!proposedEnd.isAfter(currentStart)) {
                  final actualEnd = currentStart.add(const Duration(hours: 1));
                  setModalState(
                    () => endTime = TimeOfDay.fromDateTime(actualEnd),
                  );
                } else {
                  setModalState(() => endTime = picked);
                }
              }
            }

            Future<void> submit() async {
              if (waitingForRefresh) return;
              setModalState(() => errorText = null);
              var startsAt = dateTimeAt(selectedDate, startTime);
              var endsAt = endDateTimeAt(selectedDate, startTime, endTime);
              final earliest = roundUpToNearest(
                DateTime.now().add(const Duration(minutes: 15)),
              );
              if (startsAt.isBefore(earliest)) {
                final delta = earliest.difference(startsAt);
                startsAt = earliest;
                endsAt = endsAt.add(delta);
                setModalState(() {
                  selectedDate = DateTime(
                    startsAt.year,
                    startsAt.month,
                    startsAt.day,
                  );
                  startTime = TimeOfDay.fromDateTime(startsAt);
                  endTime = TimeOfDay.fromDateTime(endsAt);
                });
              }
              if (!endsAt.isAfter(startsAt)) {
                endsAt = startsAt.add(const Duration(hours: 1));
                setModalState(() => endTime = TimeOfDay.fromDateTime(endsAt));
              }
              if (capacity < 1 || capacity > 30) {
                setModalState(
                  () => errorText = 'จำนวนผู้เข้าร่วมต้องอยู่ระหว่าง 1–30 คน',
                );
                return;
              }
              if (ownerAutoJoin &&
                  groupPositions.isNotEmpty &&
                  selectedOwnerPositionId == null) {
                setModalState(
                  () => errorText =
                      'กรุณาเลือกตำแหน่งของเจ้าของก๊วนสำหรับรอบนัดนี้',
                );
                return;
              }
              setModalState(() => submitting = true);
              try {
                await repo.createSession(
                  groupId: groupId,
                  actorUserId: actorUserId,
                  capacity: capacity,
                  startsAt: startsAt,
                  endsAt: endsAt,
                  placeName: null,
                  note: noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim(),
                  ownerPositionId: ownerAutoJoin && groupPositions.isNotEmpty
                      ? selectedOwnerPositionId
                      : null,
                  costItems: List<Map<String, dynamic>>.from(costItems),
                );
                if (!pageContext.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  const SnackBar(content: Text('สร้างรอบนัดสำเร็จ')),
                );
                onSessionCreated?.call();
              } catch (e) {
                setModalState(() => submitting = false);
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(
                    content: Text('บันทึกไม่สำเร็จ: ${mapManagementError(e)}'),
                  ),
                );
              }
            }

            final content = Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
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
                      'สร้างรอบนัด',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ThaiBuddhistDatePickerField(
                      value: selectedDate,
                      label: 'วันที่',
                      onDateSelected: (d) {
                        var nextStart = dateTimeAt(d, startTime);
                        var nextEnd = endDateTimeAt(d, startTime, endTime);
                        final earliest = roundUpToNearest(
                          DateTime.now().add(const Duration(minutes: 15)),
                        );
                        if (nextStart.isBefore(earliest)) {
                          final delta = earliest.difference(nextStart);
                          nextStart = earliest;
                          nextEnd = nextEnd.add(delta);
                        }
                        setModalState(() {
                          selectedDate = DateTime(
                            nextStart.year,
                            nextStart.month,
                            nextStart.day,
                          );
                          startTime = TimeOfDay.fromDateTime(nextStart);
                          endTime = TimeOfDay.fromDateTime(nextEnd);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickStartTime,
                            icon: const Icon(Icons.schedule),
                            label: Text('เริ่ม ${startTime.format(ctx)} น.'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickEndTime,
                            icon: const Icon(Icons.timer_off_outlined),
                            label: Text('สิ้นสุด ${endTime.format(ctx)} น.'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('จำนวนผู้เข้าร่วมสูงสุดในรอบนี้'),
                        Text('$capacity คน'),
                      ],
                    ),
                    Slider(
                      value: capacity.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: '$capacity',
                      onChanged: (value) =>
                          setModalState(() => capacity = value.toInt()),
                    ),
                    const SizedBox(height: 12),
                    if (ownerAutoJoin &&
                        groupPositions.isNotEmpty &&
                        fieldLayout != null) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.person_pin_circle_rounded,
                              size: 16,
                              color: AppColors.primaryDark,
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
                        'เนื่องจากเปิด "เข้าร่วมทุกรอบอัตโนมัติ" กรุณาเลือกตำแหน่งของเจ้าของก๊วนบนสนามจำลอง',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      PositionLineupView(
                        layout: fieldLayout,
                        fieldStyle: fieldStyle,
                        positions: groupPositions,
                        selectedPositionId: selectedOwnerPositionId,
                        onPositionSelected: (posId) {
                          setModalState(() => selectedOwnerPositionId = posId);
                        },
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: groupPositions.map((pos) {
                          final posId = pos['id']?.toString() ?? '';
                          final label = pos['label']?.toString() ?? '';
                          final isSelected = selectedOwnerPositionId == posId;
                          final color = parseHexColor(pos['color']?.toString());
                          return ChoiceChip(
                            selected: isSelected,
                            avatar: CircleAvatar(
                              backgroundColor: color,
                              radius: 8,
                            ),
                            label: Text(label),
                            selectedColor: AppColors.primary.withValues(
                              alpha: 0.25,
                            ),
                            onSelected: (_) => setModalState(
                              () => selectedOwnerPositionId = posId,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SessionCostEditor(
                      sheetContext: ctx,
                      groupId: groupId,
                      costItems: costItems,
                      sessionHours: () {
                        final s = dateTimeAt(selectedDate, startTime);
                        final e = endDateTimeAt(
                          selectedDate,
                          startTime,
                          endTime,
                        );
                        return e.difference(s).inMinutes / 60.0;
                      },
                      refresh: () => setModalState(() {}),
                      repo: repo,
                    ),

                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ (ไม่บังคับ)',
                      ),
                      maxLines: 2,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: submitting || waitingForRefresh
                            ? null
                            : submit,
                        icon: submitting || waitingForRefresh
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          waitingForRefresh
                              ? 'กำลังรีเฟรชรายการก๊วน...'
                              : 'บันทึกรอบนัด',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );

            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                child: content,
              ),
            );
          },
        );
      },
    );
  }
}
