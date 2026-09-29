import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import 'glass_dialog.dart';
import 'glass_primitives.dart';

/// ชื่อเดือน/วันในภาษาไทย — ชุดเดียวกับ `ThaiDateUtils` ใน
/// `lib/shared/widgets/thai_buddhist_date_picker.dart` แต่เก็บไว้ในชั้น glass
/// เพื่อไม่ให้ระบบ glass ต้องพึ่ง widget ของระบบ neumorphic
const _thaiMonthsFull = [
  'มกราคม',
  'กุมภาพันธ์',
  'มีนาคม',
  'เมษายน',
  'พฤษภาคม',
  'มิถุนายน',
  'กรกฎาคม',
  'สิงหาคม',
  'กันยายน',
  'ตุลาคม',
  'พฤศจิกายน',
  'ธันวาคม',
];

/// ปฏิทินไทยเริ่มสัปดาห์ที่วันอาทิตย์
const _thaiWeekdaysShort = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

const _pickerFont = 'SukhumvitSet';

/// ตัวเลือกวันที่แบบ Glass — ใช้แทน `showDatePicker` ของ Material
///
/// **พฤติกรรมเทียบเท่า Material (ผู้เรียกไม่ต้องแก้ logic):**
/// - คืน `DateTime` ที่ตัดเวลาออกแล้ว (เที่ยงคืน) หรือ `null` เมื่อผู้ใช้ยกเลิก
/// - เลือกได้เฉพาะวันในช่วง `firstDate..lastDate` (วันนอกช่วงกดไม่ได้)
/// - ค่าเริ่มต้นถูก clamp เข้าในช่วงเสมอ (Material ใช้ assert แทน)
/// - เปิดที่เดือนของ `initialDate` นำทางเดือนได้จนสุดช่วง และแตะหัวเรื่องเพื่อ
///   สลับไปเลือกปี พ.ศ. (เหมือนโหมด year ของ Material)
class GlassDatePicker {
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    String title = 'เลือกวันที่',
    Color accentColor = AppColors.primary,
  }) {
    return GlassDialog.show<DateTime>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      backdropBlur: 6,
      panelBorderRadius: 24,
      panelBlurSigma: 18,
      panelFillOpacity: 0.10,
      panelAccentColor: accentColor,
      panelAccentStrength: 0.12,
      panelGlowOpacity: 0.14,
      panelRimWidth: 2.4,
      panelShadowOpacity: 0.30,
      contentPadding: EdgeInsets.zero,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      builder: (_) => _GlassDatePicker(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        title: title,
        accentColor: accentColor,
      ),
    );
  }
}

/// ตัวเลือกเวลาแบบ Glass (ล้อชั่วโมง/นาที) — ใช้แทน `showTimePicker`
///
/// คืน `TimeOfDay` หรือ `null` เมื่อผู้ใช้ยกเลิก โดยคงความละเอียดระดับนาที
/// เท่ากับ Material (00–23 ชั่วโมง, 00–59 นาที)
class GlassTimePicker {
  static Future<TimeOfDay?> show(
    BuildContext context, {
    required TimeOfDay initialTime,
    String title = 'เลือกเวลา',
    Color accentColor = AppColors.primary,
  }) {
    return GlassDialog.show<TimeOfDay>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      backdropBlur: 6,
      panelBorderRadius: 24,
      panelBlurSigma: 18,
      panelFillOpacity: 0.10,
      panelAccentColor: accentColor,
      panelAccentStrength: 0.12,
      panelGlowOpacity: 0.14,
      panelRimWidth: 2.4,
      panelShadowOpacity: 0.30,
      contentPadding: EdgeInsets.zero,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      builder: (_) => _GlassTimePicker(
        initialTime: initialTime,
        title: title,
        accentColor: accentColor,
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _pad2(int value) => value.toString().padLeft(2, '0');

TextStyle _whiteText({
  required double size,
  FontWeight weight = FontWeight.w600,
  double alpha = 1,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: _pickerFont,
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  color: Colors.white.withValues(alpha: alpha),
);

/// หัวเรื่องของ picker: ไอคอน + ชื่อ + ค่าที่เลือกอยู่
class _PickerHeader extends StatelessWidget {
  const _PickerHeader({
    required this.icon,
    required this.title,
    required this.value,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: accentColor.withValues(alpha: 0.9)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _whiteText(size: 16, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(value, style: _whiteText(size: 12.5, alpha: 0.7)),
            ],
          ),
        ),
      ],
    );
  }
}

/// แถวปุ่มยกเลิก/ยืนยัน ตามแบบเดียวกับ `GlassConfirmDialog`
class _PickerActions extends StatelessWidget {
  const _PickerActions({required this.accentColor, required this.onConfirm});

  final Color accentColor;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GlassActionButton(
            label: 'ยกเลิก',
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GlassActionButton(
            label: 'ยืนยัน',
            isFilled: true,
            fillColor: accentColor,
            onTap: onConfirm,
          ),
        ),
      ],
    );
  }
}

class _GlassDatePicker extends StatefulWidget {
  const _GlassDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
    required this.accentColor,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final Color accentColor;

  @override
  State<_GlassDatePicker> createState() => _GlassDatePickerState();
}

class _GlassDatePickerState extends State<_GlassDatePicker> {
  late final DateTime _min = _dateOnly(widget.firstDate);
  late final DateTime _max = _dateOnly(widget.lastDate);
  late final DateTime _firstMonth = DateTime(_min.year, _min.month);
  late final DateTime _lastMonth = DateTime(_max.year, _max.month);

  late DateTime _selected = _clampDate(_dateOnly(widget.initialDate));
  late DateTime _month = DateTime(_selected.year, _selected.month);
  bool _yearMode = false;

  DateTime _clampDate(DateTime value) {
    final daysInMonth = DateTime(value.year, value.month + 1, 0).day;
    var result = DateTime(
      value.year,
      value.month,
      value.day.clamp(1, daysInMonth),
    );
    if (result.isBefore(_min)) result = _min;
    if (result.isAfter(_max)) result = _max;
    return result;
  }

  DateTime _clampMonth(DateTime value) {
    final target = DateTime(value.year, value.month);
    if (target.isBefore(_firstMonth)) return _firstMonth;
    if (target.isAfter(_lastMonth)) return _lastMonth;
    return target;
  }

  bool get _canGoPrev => _month.isAfter(_firstMonth);

  bool get _canGoNext => _month.isBefore(_lastMonth);

  void _shiftMonth(int delta) => setState(
    () => _month = _clampMonth(DateTime(_month.year, _month.month + delta)),
  );

  void _selectYear(int year) {
    setState(() {
      _month = _clampMonth(DateTime(year, _month.month));
      _selected = _clampDate(DateTime(year, _selected.month, _selected.day));
      _yearMode = false;
    });
  }

  String get _selectedLabel =>
      '${_selected.day} ${_thaiMonthsFull[_selected.month - 1]} '
      'พ.ศ. ${_selected.year + 543}';

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 360,
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PickerHeader(
                icon: Icons.calendar_month_rounded,
                title: widget.title,
                value: _selectedLabel,
                accentColor: widget.accentColor,
              ),
              const SizedBox(height: 16),
              if (_yearMode) _buildYearGrid() else _buildCalendar(),
              const SizedBox(height: 20),
              _PickerActions(
                accentColor: widget.accentColor,
                onConfirm: () => Navigator.of(context).pop(_selected),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    return Column(
      children: [
        Row(
          children: [
            _arrowButton(
              icon: Icons.chevron_left_rounded,
              label: 'เดือนก่อนหน้า',
              enabled: _canGoPrev,
              onTap: () => _shiftMonth(-1),
            ),
            Expanded(
              child: Semantics(
                button: true,
                label: 'เลือกปี พ.ศ.',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _yearMode = true),
                  child: Column(
                    children: [
                      Text(
                        '${_thaiMonthsFull[_month.month - 1]} '
                        '${_month.year + 543}',
                        style: _whiteText(size: 15, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'แตะเพื่อเลือกปี',
                        style: _whiteText(size: 10.5, alpha: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _arrowButton(
              icon: Icons.chevron_right_rounded,
              label: 'เดือนถัดไป',
              enabled: _canGoNext,
              onTap: () => _shiftMonth(1),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final weekday in _thaiWeekdaysShort)
              Expanded(
                child: Center(
                  child: Text(
                    weekday,
                    style: _whiteText(
                      size: 11,
                      weight: FontWeight.w600,
                      alpha: 0.55,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ..._buildDayRows(),
      ],
    );
  }

  Widget _arrowButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GlassIconButton(
        icon: icon,
        semanticsLabel: label,
        onTap: enabled ? onTap : null,
      ),
    );
  }

  List<Widget> _buildDayRows() {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = DateTime(_month.year, _month.month, 1).weekday % 7;
    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _dayCell(DateTime(_month.year, _month.month, day)),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }
    return [
      for (var row = 0; row < cells.length; row += 7)
        Row(
          children: [
            for (var column = row; column < row + 7; column++)
              Expanded(child: SizedBox(height: 44, child: cells[column])),
          ],
        ),
    ];
  }

  Widget _dayCell(DateTime day) {
    final disabled = day.isBefore(_min) || day.isAfter(_max);
    final selected = DateUtils.isSameDay(day, _selected);
    final isToday = DateUtils.isSameDay(day, DateTime.now());
    final label =
        '${day.day} ${_thaiMonthsFull[day.month - 1]} ${day.year + 543}';

    return Semantics(
      button: true,
      enabled: !disabled,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : () => setState(() => _selected = day),
        child: Center(
          child: selected
              ? LitGlassSurface(
                  borderRadius: 12,
                  blurSigma: 0,
                  surfaceColor: widget.accentColor,
                  fillOpacity: 0.5,
                  accentColor: widget.accentColor,
                  accentStrength: 0.35,
                  glowOpacity: 0.32,
                  selected: true,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: _whiteText(size: 14, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                )
              : Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: isToday
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        )
                      : null,
                  child: Text(
                    '${day.day}',
                    style: _whiteText(size: 14, alpha: disabled ? 0.25 : 0.85),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildYearGrid() {
    final years = [for (var year = _max.year; year >= _min.year; year--) year];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GlassIconButton(
              icon: Icons.arrow_back_rounded,
              semanticsLabel: 'กลับไปปฏิทิน',
              onTap: () => setState(() => _yearMode = false),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'เลือกปี พ.ศ.',
                style: _whiteText(size: 15, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 244,
          child: GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1.7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: years.length,
            itemBuilder: (_, index) => _yearCell(years[index]),
          ),
        ),
      ],
    );
  }

  Widget _yearCell(int year) {
    final selected = year == _month.year;
    final label = '${year + 543}';
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectYear(year),
        child: selected
            ? LitGlassSurface(
                borderRadius: 12,
                blurSigma: 0,
                surfaceColor: widget.accentColor,
                fillOpacity: 0.5,
                accentColor: widget.accentColor,
                accentStrength: 0.35,
                glowOpacity: 0.32,
                selected: true,
                child: Center(
                  child: Text(
                    label,
                    style: _whiteText(size: 13, weight: FontWeight.w700),
                  ),
                ),
              )
            : Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                    width: 0.8,
                  ),
                ),
                child: Text(label, style: _whiteText(size: 13, alpha: 0.8)),
              ),
      ),
    );
  }
}

class _GlassTimePicker extends StatefulWidget {
  const _GlassTimePicker({
    required this.initialTime,
    required this.title,
    required this.accentColor,
  });

  final TimeOfDay initialTime;
  final String title;
  final Color accentColor;

  @override
  State<_GlassTimePicker> createState() => _GlassTimePickerState();
}

class _GlassTimePickerState extends State<_GlassTimePicker> {
  late int _hour = widget.initialTime.hour;
  late int _minute = widget.initialTime.minute;
  late final FixedExtentScrollController _hourController =
      FixedExtentScrollController(initialItem: _hour);
  late final FixedExtentScrollController _minuteController =
      FixedExtentScrollController(initialItem: _minute);

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 320,
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PickerHeader(
              icon: Icons.schedule_rounded,
              title: widget.title,
              value: '${_pad2(_hour)}:${_pad2(_minute)} น.',
              accentColor: widget.accentColor,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _wheel(
                    label: 'ชั่วโมง',
                    count: 24,
                    selected: _hour,
                    controller: _hourController,
                    onChanged: (value) => setState(() => _hour = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _wheel(
                    label: 'นาที',
                    count: 60,
                    selected: _minute,
                    controller: _minuteController,
                    onChanged: (value) => setState(() => _minute = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _PickerActions(
              accentColor: widget.accentColor,
              onConfirm: () => Navigator.of(
                context,
              ).pop(TimeOfDay(hour: _hour, minute: _minute)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wheel({
    required String label,
    required int count,
    required int selected,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: _whiteText(size: 11.5, alpha: 0.6, letterSpacing: 0.4),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          value: _pad2(selected),
          container: true,
          child: SizedBox(
            height: 156,
            child: Stack(
              children: [
                Center(
                  child: Container(
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 0.8,
                      ),
                    ),
                  ),
                ),
                ListWheelScrollView.useDelegate(
                  controller: controller,
                  itemExtent: 40,
                  diameterRatio: 1.8,
                  perspective: 0.002,
                  useMagnifier: true,
                  magnification: 1.08,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: onChanged,
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: count,
                    builder: (_, index) => Center(
                      child: Text(
                        _pad2(index),
                        style: _whiteText(
                          size: 17,
                          weight: index == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          alpha: index == selected ? 1 : 0.45,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
