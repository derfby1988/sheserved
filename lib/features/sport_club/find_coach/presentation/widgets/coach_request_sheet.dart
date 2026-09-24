import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/coach_models.dart';

/// Request draft returned by [CoachRequestSheet.show].
typedef CoachRequestDraft =
    ({
      String sportId,
      TeachingMode teachingMode,
      DateTime startsAt,
      DateTime endsAt,
      String? message,
    });

/// Bottom sheet for composing a coach booking request: sport, teaching
/// mode (limited to what the coach offers), slot and message. Returns the
/// draft; the caller invokes `create_coach_booking_request`.
class CoachRequestSheet {
  static Future<CoachRequestDraft?> show(
    BuildContext context, {
    required CoachSummary coach,
    required List<Map<String, dynamic>> sports,
    String? preferredSportId,
  }) {
    return showModalBottomSheet<CoachRequestDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _CoachRequestSheetBody(
        coach: coach,
        sports: sports,
        preferredSportId: preferredSportId,
      ),
    );
  }
}

class _CoachRequestSheetBody extends StatefulWidget {
  final CoachSummary coach;
  final List<Map<String, dynamic>> sports;
  final String? preferredSportId;

  const _CoachRequestSheetBody({
    required this.coach,
    required this.sports,
    this.preferredSportId,
  });

  @override
  State<_CoachRequestSheetBody> createState() =>
      _CoachRequestSheetBodyState();
}

class _CoachRequestSheetBodyState extends State<_CoachRequestSheetBody> {
  late String? _sportId =
      widget.preferredSportId != null &&
          widget.coach.sportIds.contains(widget.preferredSportId)
      ? widget.preferredSportId
      : (widget.coach.sportIds.isNotEmpty
            ? widget.coach.sportIds.first
            : null);
  late TeachingMode _mode = widget.coach.teachingMode == TeachingMode.online
      ? TeachingMode.online
      : TeachingMode.onsite;
  late DateTime _date = DateTime.now();
  TimeOfDay? _start;
  int _hours = 1;
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  bool get _valid => _sportId != null && _start != null;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _start ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _start = picked);
  }

  @override
  Widget build(BuildContext context) {
    final coach = widget.coach;
    final coachSports = widget.sports
        .where((s) => coach.sportIds.contains(s['id']?.toString()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
              const SizedBox(height: 16),
              Text(
                'ขอนัดกับ ${coach.displayName}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (coach.hourlyRate != null)
                Text(
                  '${coach.hourlyRate!.toStringAsFixed(0)} บาท/ชั่วโมง',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
              const SizedBox(height: 16),

              if (coachSports.length > 1) ...[
                const Text(
                  'กีฬา',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final sport in coachSports)
                      ChoiceChip(
                        label: Text(
                          sport['name_th']?.toString() ??
                              sport['name']?.toString() ??
                              '',
                        ),
                        selected: _sportId == sport['id']?.toString(),
                        onSelected: (sel) => setState(
                          () => _sportId = sel
                              ? sport['id']?.toString()
                              : _sportId,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              if (coach.teachingMode == TeachingMode.both) ...[
                const Text(
                  'รูปแบบการสอน',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SegmentedButton<TeachingMode>(
                  segments: const [
                    ButtonSegment(
                      value: TeachingMode.onsite,
                      label: Text('ออนไซต์'),
                    ),
                    ButtonSegment(
                      value: TeachingMode.online,
                      label: Text('ออนไลน์'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (sel) =>
                      setState(() => _mode = sel.first),
                ),
                const SizedBox(height: 12),
              ],

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(
                        '${_date.day}/${_date.month}/${_date.year + 543}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickStart,
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(
                        _start == null
                            ? 'เวลาเริ่ม'
                            : _start!.format(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final h in [1, 2, 3])
                    ChoiceChip(
                      label: Text('$h ชม.'),
                      selected: _hours == h,
                      onSelected: (sel) =>
                          setState(() => _hours = sel ? h : _hours),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'ข้อความถึงโค้ช (ไม่บังคับ)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _valid
                      ? () {
                          final start = DateTime(
                            _date.year,
                            _date.month,
                            _date.day,
                            _start!.hour,
                            _start!.minute,
                          );
                          Navigator.pop(context, (
                            sportId: _sportId!,
                            teachingMode: _mode,
                            startsAt: start,
                            endsAt: start.add(Duration(hours: _hours)),
                            message: _message.text.trim().isEmpty
                                ? null
                                : _message.text.trim(),
                          ));
                        }
                      : null,
                  child: const Text('ส่งคำขอ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
