import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/glass/glass_date_time_picker.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/coach_models.dart';

/// Request draft returned by [CoachRequestSheet.show].
typedef CoachRequestDraft = ({
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
      backgroundColor: NeumorphicTheme.baseColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
  State<_CoachRequestSheetBody> createState() => _CoachRequestSheetBodyState();
}

class _CoachRequestSheetBodyState extends State<_CoachRequestSheetBody> {
  late String? _sportId =
      widget.preferredSportId != null &&
          widget.coach.sportIds.contains(widget.preferredSportId)
      ? widget.preferredSportId
      : (widget.coach.sportIds.isNotEmpty ? widget.coach.sportIds.first : null);
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
    final picked = await GlassDatePicker.show(
      context,
      initialDate: _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStart() async {
    final picked = await GlassTimePicker.show(
      context,
      initialTime: _start ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _start = picked);
  }

  void _submit() {
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
      message: _message.text.trim().isEmpty ? null : _message.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final coach = widget.coach;
    final coachSports = widget.sports
        .where((s) => coach.sportIds.contains(s['id']?.toString()))
        .toList();
    return NeumorphicFormSheetShell(
      title: 'ขอนัดกับ ${coach.displayName}',
      icon: Icons.send_rounded,
      subtitle: coach.hourlyRate == null
          ? null
          : '${coach.hourlyRate!.toStringAsFixed(0)} บาท/ชั่วโมง',
      onClose: () => Navigator.pop(context),
      footer: SizedBox(
        width: double.infinity,
        child: NeumorphicVerifyButton(
          onPressed: _valid ? _submit : null,
          isEnabled: _valid,
          text: 'ส่งคำขอ',
          height: 52,
          icon: const Icon(Icons.send_rounded, color: Colors.white),
        ),
      ),
      children: [
        if (coachSports.length > 1) ...[
          const Text('กีฬา', style: NeumorphicTheme.sectionLabel),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sport in coachSports)
                NeumorphicChoiceChip(
                  label:
                      sport['name_th']?.toString() ??
                      sport['name']?.toString() ??
                      '',
                  selected: _sportId == sport['id']?.toString(),
                  onSelected: (sel) => setState(
                    () => _sportId = sel ? sport['id']?.toString() : _sportId,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],

        if (coach.teachingMode == TeachingMode.both) ...[
          const Text('รูปแบบการสอน', style: NeumorphicTheme.sectionLabel),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (mode, label) in [
                (TeachingMode.onsite, 'ออนไซต์'),
                (TeachingMode.online, 'ออนไลน์'),
              ])
                NeumorphicChoiceChip(
                  label: label,
                  selected: _mode == mode,
                  onSelected: (sel) =>
                      setState(() => _mode = sel ? mode : _mode),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],

        const Text('วันและเวลา', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: NeumorphicPillButton(
                text: '${_date.day}/${_date.month}/${_date.year + 543}',
                icon: Icons.calendar_today_rounded,
                active: true,
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: NeumorphicPillButton(
                text: _start == null ? 'เวลาเริ่ม' : _start!.format(context),
                icon: Icons.schedule_rounded,
                active: _start != null,
                onPressed: _pickStart,
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),
        const Text('ระยะเวลา', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final h in [1, 2, 3])
              NeumorphicChoiceChip(
                label: '$h ชม.',
                selected: _hours == h,
                onSelected: (sel) => setState(() => _hours = sel ? h : _hours),
              ),
          ],
        ),

        const SizedBox(height: 18),
        NeumorphicInsetBox(
          height: null,
          borderRadius: 14,
          child: TextField(
            controller: _message,
            maxLength: 500,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'ข้อความถึงโค้ช (ไม่บังคับ)',
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              counterStyle: TextStyle(
                fontSize: 10.5,
                color: NeumorphicTheme.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
