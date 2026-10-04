import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

/// Owner editor for the venue-level recurring booking release
/// (Phase 21.7.18). Returns `cleared: true` to remove the rule (advance
/// booking becomes unlimited again); otherwise the weekly release triple.
/// The caller runs `set_sports_venue_booking_release` and reloads before
/// reporting success.
class VenueReleaseEditorDialog {
  static Future<
      ({bool cleared, int dayOfWeek, String time, int windowDays})?> show(
    BuildContext context, {
    int? currentDayOfWeek,
    String? currentTime,
    int? currentWindowDays,
  }) {
    return GlassDialog.show<
        ({bool cleared, int dayOfWeek, String time, int windowDays})>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => _VenueReleaseEditorDialogBody(
        currentDayOfWeek: currentDayOfWeek,
        currentTime: currentTime,
        currentWindowDays: currentWindowDays,
      ),
    );
  }
}

class _VenueReleaseEditorDialogBody extends StatefulWidget {
  final int? currentDayOfWeek;
  final String? currentTime;
  final int? currentWindowDays;

  const _VenueReleaseEditorDialogBody({
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
  static const _weekdayLabels = {
    0: 'อาทิตย์',
    1: 'จันทร์',
    2: 'อังคาร',
    3: 'พุธ',
    4: 'พฤหัสบดี',
    5: 'ศุกร์',
    6: 'เสาร์',
  };

  static const _windowPresets = [7, 14, 30, 60, 90];

  late bool _enabled = widget.currentDayOfWeek != null;
  late int _day = widget.currentDayOfWeek ?? 1;
  late TimeOfDay _time = _parse(widget.currentTime);
  late final _window = TextEditingController(
    text: (widget.currentWindowDays ?? 7).toString(),
  );
  final ScrollController _scrollController = ScrollController();

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

  /// Server requires a window of at least 7 days so every future slot is
  /// covered by at least one release round; there is no product ceiling.
  int? get _windowValue {
    final parsed = int.tryParse(_window.text.trim());
    if (parsed == null || parsed < 7) return null;
    return parsed;
  }

  bool get _valid => !_enabled || _windowValue != null;

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _submit() {
    if (!_valid) return;
    if (!_enabled) {
      Navigator.pop(
        context,
        (cleared: true, dayOfWeek: _day, time: _formatTime(_time),
            windowDays: _windowValue ?? 7),
      );
      return;
    }
    Navigator.pop(
      context,
      (cleared: false, dayOfWeek: _day, time: _formatTime(_time),
          windowDays: _windowValue!),
    );
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
                        'ใช้กับทุกคอร์ทที่ตั้ง "ตามสนาม" — สล็อตที่ยังไม่ถึงรอบจะแสดงแต่จองไม่ได้',
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
                                ? 'เปิดรับจองตามรอบรายสัปดาห์'
                                : 'ไม่จำกัด — จองล่วงหน้าได้ทุกวัน',
                            style: const TextStyle(fontSize: 12),
                          ),
                          value: _enabled,
                          onChanged: (v) => setState(() => _enabled = v),
                        ),
                        if (_enabled) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<int>(
                                  key: const ValueKey(
                                    'venue-release-day',
                                  ),
                                  isExpanded: true,
                                  initialValue: _day,
                                  decoration: const InputDecoration(
                                    labelText: 'เปิดจองทุกวัน',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    for (final entry
                                        in _weekdayLabels.entries)
                                      DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(entry.value),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _day = v);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: OutlinedButton(
                                  key: const ValueKey(
                                    'venue-release-time',
                                  ),
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime: _time,
                                    );
                                    if (picked != null && mounted) {
                                      setState(() => _time = picked);
                                    }
                                  },
                                  child: Text('เวลา ${_formatTime(_time)}'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'จองล่วงหน้าได้ (วัน)',
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
                                  onSelected: (_) => setState(
                                    () => _window.text = '$days',
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const ValueKey('venue-release-window'),
                            controller: _window,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'กำหนดเอง (วัน)',
                              helperText:
                                  'อย่างน้อย 7 วัน — ทุกสล็อตมีรอบเปิดครอบอยู่เสมอ',
                              errorText:
                                  _window.text.trim().isNotEmpty &&
                                          _windowValue == null
                                      ? 'อย่างน้อย 7 วัน'
                                      : null,
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
