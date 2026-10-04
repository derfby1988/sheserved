import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../domain/court_booking_release_schedule.dart';

/// Owner editor for the venue-level recurring booking release
/// (Phase 21.7.18). Returns `cleared: true` to remove the rule; otherwise
/// selected weekdays share one venue-local release time.
class VenueReleaseEditorDialog {
  static Future<
    ({bool cleared, List<int> daysOfWeek, String time, int windowDays})?
  >
  show(
    BuildContext context, {
    List<int>? currentDaysOfWeek,
    int? currentDayOfWeek,
    String? currentTime,
    int? currentWindowDays,
  }) {
    return GlassDialog.show<
      ({bool cleared, List<int> daysOfWeek, String time, int windowDays})
    >(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => _VenueReleaseEditorDialogBody(
        currentDaysOfWeek: currentDaysOfWeek,
        currentDayOfWeek: currentDayOfWeek,
        currentTime: currentTime,
        currentWindowDays: currentWindowDays,
      ),
    );
  }
}

class _VenueReleaseEditorDialogBody extends StatefulWidget {
  final List<int>? currentDaysOfWeek;
  final int? currentDayOfWeek;
  final String? currentTime;
  final int? currentWindowDays;

  const _VenueReleaseEditorDialogBody({
    this.currentDaysOfWeek,
    this.currentDayOfWeek,
    this.currentTime,
    this.currentWindowDays,
  });

  @override
  State<_VenueReleaseEditorDialogBody> createState() =>
      _VenueReleaseEditorDialogBodyState();
}

class _VenueReleaseEditorDialogBodyState
    extends State<_VenueReleaseEditorDialogBody> {
  late bool _enabled =
      (widget.currentDaysOfWeek?.isNotEmpty ?? false) ||
      widget.currentDayOfWeek != null;
  late final Set<int> _selectedDays = _initialDays().toSet();
  late TimeOfDay _time = _parse(widget.currentTime);
  late final _window = TextEditingController(
    text: (widget.currentWindowDays ?? 7).toString(),
  );
  final ScrollController _scrollController = ScrollController();

  List<int> _initialDays() {
    final currentDays = widget.currentDaysOfWeek;
    if (currentDays != null &&
        CourtBookingReleaseSchedule.minimumWindowDays(currentDays) != null) {
      return CourtBookingReleaseSchedule.sortedDays(currentDays);
    }
    final legacyDay = widget.currentDayOfWeek;
    if (legacyDay != null && legacyDay >= 0 && legacyDay <= 6) {
      return [legacyDay];
    }
    return [1];
  }

  static TimeOfDay _parse(String? hhmm) {
    final parts = (hhmm ?? '09:00').split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  @override
  void dispose() {
    _window.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int? get _minimumWindowDays =>
      CourtBookingReleaseSchedule.minimumWindowDays(_selectedDays);

  List<int> get _windowPresets {
    final minimum = _minimumWindowDays;
    return {?minimum, 7, 14, 30, 60, 90}.toList()..sort();
  }

  int? get _windowValue {
    final parsed = int.tryParse(_window.text.trim());
    final minimum = _minimumWindowDays;
    if (parsed == null ||
        minimum == null ||
        parsed < minimum ||
        parsed > CourtBookingReleaseSchedule.maxWindowDays) {
      return null;
    }
    return parsed;
  }

  String? get _windowError {
    if (_window.text.trim().isEmpty) return null;
    if (_selectedDays.isEmpty) return 'เลือกอย่างน้อยหนึ่งวัน';
    final parsed = int.tryParse(_window.text.trim());
    if (parsed == null) return 'กรุณากรอกจำนวนวันเป็นตัวเลข';
    if (parsed > CourtBookingReleaseSchedule.maxWindowDays) {
      return 'ไม่เกิน ${CourtBookingReleaseSchedule.maxWindowDays} วัน';
    }
    final minimum = _minimumWindowDays;
    if (minimum == null) return 'เลือกวันเปิดรอบให้ถูกต้อง';
    return parsed < minimum ? 'อย่างน้อย $minimum วัน' : null;
  }

  bool get _valid =>
      !_enabled || (_selectedDays.isNotEmpty && _windowValue != null);

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _submit() {
    if (!_valid) return;
    final days = CourtBookingReleaseSchedule.sortedDays(_selectedDays);
    if (!_enabled) {
      Navigator.pop(context, (
        cleared: true,
        daysOfWeek: days,
        time: _formatTime(_time),
        windowDays: _windowValue ?? 7,
      ));
      return;
    }
    Navigator.pop(context, (
      cleared: false,
      daysOfWeek: days,
      time: _formatTime(_time),
      windowDays: _windowValue!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 400,
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'รอบเปิดรับจองล่วงหน้า',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ใช้กับทุกรายการที่ตั้ง "ตามสถานที่" · เวลาอิงเขตเวลาของสถานที่',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: LitGlassSurface.frosted(
                borderRadius: 14,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('จำกัดการจองล่วงหน้า'),
                          subtitle: Text(
                            _enabled
                                ? 'เปิดรอบตามวันที่เลือกและเวลาเดียวกัน'
                                : 'ไม่จำกัดจำนวนวันล่วงหน้า — ไม่ต้องรอรอบเปิดจอง',
                            style: const TextStyle(fontSize: 12),
                          ),
                          value: _enabled,
                          onChanged: (v) => setState(() => _enabled = v),
                        ),
                        if (_enabled) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'วันที่เปิดรอบ',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'เลือกได้หลายวัน โดยใช้เวลาเดียวกัน',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              FilterChip(
                                key: const ValueKey('venue-release-all-days'),
                                label: const Text('ทุกวัน'),
                                selected: _selectedDays.length == 7,
                                onSelected: (_) => setState(
                                  () => _selectedDays.addAll(
                                    CourtBookingReleaseSchedule
                                        .weekdayLabels
                                        .keys,
                                  ),
                                ),
                              ),
                              for (final entry
                                  in CourtBookingReleaseSchedule
                                      .weekdayLabels
                                      .entries)
                                FilterChip(
                                  key: ValueKey(
                                    'venue-release-day-${entry.key}',
                                  ),
                                  label: Text(entry.value),
                                  selected: _selectedDays.contains(entry.key),
                                  onSelected: (selected) => setState(() {
                                    if (selected) {
                                      _selectedDays.add(entry.key);
                                    } else {
                                      _selectedDays.remove(entry.key);
                                    }
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'รอบ: ${CourtBookingReleaseSchedule.describeDays(_selectedDays)} เวลา ${_formatTime(_time)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              key: const ValueKey('venue-release-time'),
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _time,
                                );
                                if (picked != null && mounted) {
                                  setState(() => _time = picked);
                                }
                              },
                              child: Text(
                                'เวลาเดียวกันทุกวันที่เลือก · ${_formatTime(_time)}',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'แต่ละรอบเปิดสล็อตล่วงหน้า (วัน)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: [
                              for (final days in _windowPresets)
                                ChoiceChip(
                                  label: Text('$days'),
                                  selected: _windowValue == days,
                                  onSelected: (_) =>
                                      setState(() => _window.text = '$days'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const ValueKey('venue-release-window'),
                            controller: _window,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'จำนวนวันล่วงหน้า',
                              helperText: _minimumWindowDays == null
                                  ? 'เลือกอย่างน้อยหนึ่งวัน'
                                  : 'ขั้นต่ำ $_minimumWindowDays วัน · เช่น 7 = เปิดสล็อตใน 7 วันถัดไป',
                              errorText: _windowError,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: 'ยกเลิก',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GlassActionButton(
                    label: _enabled ? 'บันทึกรอบเปิดจอง' : 'ปิดการจำกัด',
                    isFilled: true,
                    fillColor: AppColors.primaryDark,
                    onTap: _valid ? _submit : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
