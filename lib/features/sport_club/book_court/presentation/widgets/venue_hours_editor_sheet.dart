import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';

/// Owner editor for weekly operating hours.
///
/// Every weekday must be specified explicitly — an open window or closed.
/// Unset days are never auto-filled with a default window, and cross-
/// midnight windows are rejected (bookings do not support cross-day slots).
/// The explicit "เปิด 24 ชั่วโมงทุกวัน" toggle emits 00:00–23:59 for all
/// days; without it, absence of rows is never treated as always-open.
///
/// Returns the `p_hours` list for `set_sports_venue_operating_hours`:
/// `[{day, open, close, closed}]`.
class VenueHoursEditorSheet {
  static Future<List<Map<String, dynamic>>?> show(
    BuildContext context, {
    required List<VenueOperatingHours> current,
  }) {
    return showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _VenueHoursEditorSheetBody(current: current),
    );
  }
}

class _DayHours {
  final int day;
  bool closed;

  /// Explicitly chosen times — null until the owner picks them. A day is
  /// specified only when [closed] is true or both times are set.
  TimeOfDay? open;
  TimeOfDay? close;

  _DayHours({required this.day, this.closed = false, this.open, this.close});

  bool get specified => closed || (open != null && close != null);
}

class _VenueHoursEditorSheetBody extends StatefulWidget {
  final List<VenueOperatingHours> current;

  const _VenueHoursEditorSheetBody({required this.current});

  @override
  State<_VenueHoursEditorSheetBody> createState() =>
      _VenueHoursEditorSheetBodyState();
}

class _VenueHoursEditorSheetBodyState
    extends State<_VenueHoursEditorSheetBody> {
  static const _dayLabels = [
    'อาทิตย์',
    'จันทร์',
    'อังคาร',
    'พุธ',
    'พฤหัสบดี',
    'ศุกร์',
    'เสาร์',
  ];

  late final List<_DayHours> _days;
  late bool _allDay;

  static TimeOfDay? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static bool _isAllDay(List<VenueOperatingHours> current) {
    if (current.length != 7) return false;
    return current.every(
      (h) =>
          !h.isClosed &&
          _parse(h.openTime) == const TimeOfDay(hour: 0, minute: 0) &&
          _parse(h.closeTime) == const TimeOfDay(hour: 23, minute: 59),
    );
  }

  @override
  void initState() {
    super.initState();
    _allDay = _isAllDay(widget.current);
    _days = List.generate(7, (day) {
      final existing = widget.current
          .where((h) => h.dayOfWeek == day)
          .firstOrNull;
      return _DayHours(
        day: day,
        closed: existing?.isClosed ?? false,
        open: _parse(existing?.openTime),
        close: _parse(existing?.closeTime),
      );
    });
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pick(_DayHours day, {required bool isOpen}) async {
    final initial = isOpen
        ? (day.open ?? const TimeOfDay(hour: 9, minute: 0))
        : (day.close ?? const TimeOfDay(hour: 21, minute: 0));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    setState(() {
      if (isOpen) {
        day.open = picked;
      } else {
        day.close = picked;
      }
    });
  }

  bool _invalidRange(_DayHours day) {
    if (day.closed || day.open == null || day.close == null) return false;
    final open = day.open!.hour * 60 + day.open!.minute;
    final close = day.close!.hour * 60 + day.close!.minute;
    return close <= open;
  }

  int get _unspecifiedCount => _days.where((d) => !d.specified).length;

  bool get _valid =>
      _allDay || (_unspecifiedCount == 0 && !_days.any(_invalidRange));

  void _submit() {
    if (!_valid) return;
    if (_allDay) {
      Navigator.pop(context, [
        for (var day = 0; day < 7; day++)
          {'day': day, 'open': '00:00', 'close': '23:59', 'closed': false},
      ]);
      return;
    }
    Navigator.pop(context, [
      for (final day in _days)
        {
          'day': day.day,
          'open': day.closed ? '' : _fmt(day.open!),
          'close': day.closed ? '' : _fmt(day.close!),
          'closed': day.closed,
        },
    ]);
  }

  @override
  Widget build(BuildContext context) {
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
              const Text(
                'เวลาเปิด–ปิด',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'ระบุทุกวันว่าเปิดหรือปิด — ไม่รองรับช่วงเวลาข้ามเที่ยงคืน',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('เปิด 24 ชั่วโมงทุกวัน'),
                value: _allDay,
                onChanged: (v) => setState(() => _allDay = v),
              ),
              if (!_allDay)
                for (final day in _days)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(
                            _dayLabels[day.day],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: day.closed
                              ? Text(
                                  'ปิด',
                                  style: TextStyle(color: Colors.grey.shade500),
                                )
                              : Row(
                                  children: [
                                    _TimeButton(
                                      label: day.open == null
                                          ? '--:--'
                                          : _fmt(day.open!),
                                      onTap: () => _pick(day, isOpen: true),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Text('–'),
                                    ),
                                    _TimeButton(
                                      label: day.close == null
                                          ? '--:--'
                                          : _fmt(day.close!),
                                      onTap: () => _pick(day, isOpen: false),
                                    ),
                                  ],
                                ),
                        ),
                        Switch(
                          value: !day.closed,
                          onChanged: (open) =>
                              setState(() => day.closed = !open),
                        ),
                      ],
                    ),
                  ),
              if (!_allDay && _unspecifiedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'ยังไม่ระบุ $_unspecifiedCount วัน — กรุณาเลือกเวลาหรือปิด',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              if (!_allDay && _days.any(_invalidRange))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'เวลาปิดต้องอยู่หลังเวลาเปิด (ไม่รองรับข้ามเที่ยงคืน)',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                  ),
                  onPressed: _valid ? _submit : null,
                  child: const Text('บันทึก'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TimeButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 32),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}
