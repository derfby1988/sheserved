import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../data/book_court_models.dart';
import '../../domain/court_booking_release_schedule.dart';

/// Owner editor for a single court: name, unit label, type, price, approval
/// mode, indoor flag. Returns a draft map the caller passes to
/// `upsert_sports_venue_court_with_release_days`.
class OwnerCourtEditorDialog {
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    VenueCourt? court,
    required String sportId,
    List<VenueCourtPriceRule> priceRules = const [],
    Map<String, String>? sportChoices,
  }) {
    return GlassDialog.show<Map<String, dynamic>>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => _OwnerCourtEditorDialogBody(
        court: court,
        sportId: sportId,
        priceRules: priceRules,
        sportChoices: sportChoices,
      ),
    );
  }
}

class _OwnerCourtEditorDialogBody extends StatefulWidget {
  final VenueCourt? court;

  /// Preferred sport — used only when it exists in [sportChoices] (or when
  /// no choices are given). A sport missing from the venue's sport set is
  /// never silently substituted; the owner must pick one explicitly.
  final String sportId;
  final List<VenueCourtPriceRule> priceRules;

  /// venue_sport choices (id → display name) shown as a dropdown when the
  /// venue offers more than one sport. Null = fixed [sportId].
  final Map<String, String>? sportChoices;

  const _OwnerCourtEditorDialogBody({
    this.court,
    required this.sportId,
    this.priceRules = const [],
    this.sportChoices,
  });

  @override
  State<_OwnerCourtEditorDialogBody> createState() =>
      _OwnerCourtEditorDialogBodyState();
}

class _OwnerCourtEditorDialogBodyState
    extends State<_OwnerCourtEditorDialogBody> {
  late final _name = TextEditingController(text: widget.court?.name ?? '');
  // 21.7.19 — the field edits the raw per-court override, not the resolved
  // label: inherit keeps the venue-sport/sport-default resolution live.
  late String _labelMode = widget.court?.unitLabelOverride != null
      ? 'custom'
      : 'inherit';
  late final _unitLabel = TextEditingController(
    text: widget.court?.unitLabelOverride ?? '',
  );
  late final _price = TextEditingController(
    text: widget.court?.priceAmount?.toStringAsFixed(2) ?? '',
  );
  late final _capacity = TextEditingController(
    text: (widget.court?.capacity ?? 1).toString(),
  );
  late final List<_PriceRuleDraft> _priceRules = [
    for (final rule in widget.priceRules) _PriceRuleDraft.fromRule(rule),
  ];
  final ScrollController _scrollController = ScrollController();

  /// Null until a valid sport is selected — submitting requires one
  /// whenever the venue offers sport choices.
  late String? _sportId = _initialSportId();

  String? _initialSportId() {
    final preferred = widget.court?.sportId ?? widget.sportId;
    final choices = widget.sportChoices;
    if (choices != null && choices.isNotEmpty) {
      return choices.containsKey(preferred) ? preferred : null;
    }
    return preferred;
  }

  late String _pricingUnit = widget.court?.pricingUnit ?? 'hour';
  late String _approvalMode =
      widget.court?.approvalMode == BookingApprovalMode.ownerApproval
      ? 'owner_approval'
      : 'instant';
  late bool _indoor = widget.court?.indoor ?? true;
  late bool _isActive = widget.court?.isActive ?? true;
  late String? _courtType = widget.court?.courtType;

  // 21.7.18 recurring release override. 'inherit' follows the venue rule,
  // 'always_open' books without limit, 'custom' uses selected weekdays.
  late String _releaseMode = widget.court?.bookingReleaseMode ?? 'inherit';
  late final Set<int> _releaseDays = () {
    final days = widget.court?.effectiveBookingReleaseDays ?? const <int>[];
    return days.isNotEmpty ? days.toSet() : {1};
  }();
  late TimeOfDay _releaseTime = _parseReleaseTime(
    widget.court?.bookingReleaseTime,
  );
  late final _releaseWindow = TextEditingController(
    text: (widget.court?.bookingReleaseWindowDays ?? 7).toString(),
  );

  static TimeOfDay _parseReleaseTime(String? hhmm) {
    final parts = (hhmm ?? '09:00').split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  int? get _releaseMinimumWindowDays =>
      CourtBookingReleaseSchedule.minimumWindowDays(_releaseDays);

  int? get _releaseWindowValue {
    final parsed = int.tryParse(_releaseWindow.text.trim());
    final minimum = _releaseMinimumWindowDays;
    if (parsed == null ||
        minimum == null ||
        parsed < minimum ||
        parsed > CourtBookingReleaseSchedule.maxWindowDays) {
      return null;
    }
    return parsed;
  }

  List<int> get _releaseDaysValue => _releaseDays.toList()..sort();

  int? get _releaseDayValue =>
      _releaseDaysValue.isEmpty ? null : _releaseDaysValue.first;

  String? get _releaseWindowError {
    if (_releaseWindow.text.trim().isEmpty) return null;
    if (_releaseDays.isEmpty) return 'เลือกอย่างน้อยหนึ่งวัน';
    final parsed = int.tryParse(_releaseWindow.text.trim());
    if (parsed == null) return 'กรุณากรอกจำนวนวันเป็นตัวเลข';
    if (parsed > CourtBookingReleaseSchedule.maxWindowDays) {
      return 'ไม่เกิน ${CourtBookingReleaseSchedule.maxWindowDays} วัน';
    }
    final minimum = _releaseMinimumWindowDays;
    if (minimum == null) return 'เลือกวันเปิดรอบให้ถูกต้อง';
    return parsed < minimum ? 'อย่างน้อย $minimum วัน' : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _unitLabel.dispose();
    _price.dispose();
    _capacity.dispose();
    _releaseWindow.dispose();
    for (final rule in _priceRules) {
      rule.price.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  int? get _capacityValue {
    final raw = _capacity.text.trim();
    if (raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    // DB constraint: capacity BETWEEN 1 AND 100.
    if (parsed == null || parsed < 1 || parsed > 100) return null;
    return parsed;
  }

  /// Null = valid empty price; -1 = malformed; otherwise the price.
  double? get _priceValue {
    final raw = _price.text.trim();
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw) ||
        parsed == null ||
        parsed < 0 ||
        parsed > 99999999.99) {
      return -1;
    }
    return parsed;
  }

  String? get _priceRulesError {
    if (_priceRules.isEmpty) return null;
    if (_pricingUnit != 'hour') return 'ราคาแยกช่วงเวลาต้องคิดเป็นรายชั่วโมง';
    if (_priceRules.length > 100) return 'กำหนดช่วงราคาได้ไม่เกิน 100 ช่วง';
    for (var i = 0; i < _priceRules.length; i++) {
      final rule = _priceRules[i];
      final rawPrice = rule.price.text.trim();
      final price = double.tryParse(rawPrice);
      if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(rawPrice) ||
          price == null ||
          price > 99999999.99) {
        return 'กรุณากรอกราคา/ชั่วโมงไม่เกิน 2 ตำแหน่ง';
      }
      final start = _minutes(rule.start);
      final end = _minutes(rule.end);
      if (start >= end) return 'เวลาเริ่มต้องน้อยกว่าเวลาสิ้นสุด';
      for (final other in _priceRules.skip(i + 1)) {
        final sameSchedule = rule.dayOfWeek == other.dayOfWeek;
        if (sameSchedule &&
            start < _minutes(other.end) &&
            _minutes(other.start) < end) {
          return 'ช่วงเวลาราคาทับซ้อนกัน';
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> get _priceRulesJson => [
    for (final rule in _priceRules)
      {
        'day_of_week': rule.dayOfWeek,
        'start_time': _formatTime(rule.start),
        'end_time': _formatTime(rule.end),
        'price_per_hour': double.parse(rule.price.text.trim()),
      },
  ];

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _capacityValue != null &&
      _priceValue != -1 &&
      _priceRulesError == null &&
      _sportId != null &&
      (_labelMode != 'custom' || _unitLabel.text.trim().isNotEmpty) &&
      (_releaseMode != 'custom' ||
          (_releaseDays.isNotEmpty && _releaseWindowValue != null));

  int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _pickPriceRuleTime(
    _PriceRuleDraft rule, {
    required bool start,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? rule.start : rule.end,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        rule.start = picked;
      } else {
        rule.end = picked;
      }
    });
  }

  void _addPriceRule() {
    setState(() {
      _priceRules.add(
        _PriceRuleDraft(
          dayOfWeek: null,
          start: const TimeOfDay(hour: 18, minute: 0),
          end: const TimeOfDay(hour: 22, minute: 0),
        ),
      );
    });
  }

  void _removePriceRule(int index) {
    final rule = _priceRules.removeAt(index);
    rule.price.dispose();
    setState(() {});
  }

  static const _weekdayLabels = {
    0: 'อาทิตย์',
    1: 'จันทร์',
    2: 'อังคาร',
    3: 'พุธ',
    4: 'พฤหัสบดี',
    5: 'ศุกร์',
    6: 'เสาร์',
  };

  Widget _priceRuleTile(int index) {
    final rule = _priceRules[index];
    const weekdayLabels = _weekdayLabels;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: rule.dayOfWeek ?? 7,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'วัน',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: 7, child: Text('ทุกวัน')),
                    for (final entry in weekdayLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => setState(
                    () => rule.dayOfWeek = value == 7 ? null : value,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'ลบช่วงราคา',
                onPressed: () => _removePriceRule(index),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickPriceRuleTime(rule, start: true),
                  child: Text('เริ่ม ${_formatTime(rule.start)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickPriceRuleTime(rule, start: false),
                  child: Text('สิ้นสุด ${_formatTime(rule.end)}'),
                ),
              ),
            ],
          ),
          TextField(
            controller: rule.price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'ราคา/ชั่วโมง',
              suffixText: 'บาท',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.court != null;
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
                  child: Text(
                    editing ? 'แก้ไขรายการ' : 'เพิ่มรายการ',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
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
                        if (widget.sportChoices != null &&
                            widget.sportChoices!.isNotEmpty) ...[
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue:
                                _sportId != null &&
                                    widget.sportChoices!.containsKey(_sportId)
                                ? _sportId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'กีฬา',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final entry in widget.sportChoices!.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _sportId = v);
                            },
                          ),
                          if (_sportId == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'กีฬาเดิมถูกเอาออกจากสถานที่แล้ว — กรุณาเลือกกีฬาใหม่',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อรายการ *',
                            hintText: 'เช่น คอร์ท 1, โต๊ะ A, เลน 3',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'ชื่อเรียกหน่วยที่จองได้',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        SegmentedButton<String>(
                          key: const ValueKey('court-unit-label-mode'),
                          segments: const [
                            ButtonSegment(
                              value: 'inherit',
                              label: Text('ตามกีฬา/สถานที่'),
                            ),
                            ButtonSegment(
                              value: 'custom',
                              label: Text('กำหนดเอง'),
                            ),
                          ],
                          selected: {_labelMode},
                          onSelectionChanged: (sel) =>
                              setState(() => _labelMode = sel.first),
                        ),
                        if (_labelMode == 'inherit')
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              widget.court?.unitLabel != null
                                  ? 'ตอนนี้แสดงว่า "${widget.court!.unitLabel}" — เปลี่ยนตามกีฬา/การตั้งค่าสถานที่อัตโนมัติ'
                                  : 'ใช้ค่าจากกีฬาและการตั้งค่าของสถานที่โดยอัตโนมัติ',
                              style: const TextStyle(fontSize: 12),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextField(
                              controller: _unitLabel,
                              maxLength: 20,
                              decoration: const InputDecoration(
                                counterText: '',
                                labelText: 'ชื่อเรียกเฉพาะรายการนี้ *',
                                hintText: 'เช่น คอร์ท, โต๊ะ, เลน',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _price,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: _pricingUnit == 'hour'
                                      ? 'ราคาเริ่มต้น (บาท/ชม.)'
                                      : 'ราคา (บาท)',
                                  errorText: _priceValue == -1
                                      ? 'ราคาไม่ถูกต้อง'
                                      : null,
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _pricingUnit,
                                decoration: const InputDecoration(
                                  labelText: 'ต่อหน่วย',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'hour',
                                    child: Text('ชั่วโมง'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'session',
                                    child: Text('รอบ'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'match',
                                    child: Text('แมตช์'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'day',
                                    child: Text('วัน'),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _pricingUnit = v ?? 'hour'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'ราคาแยกตามวันและเวลา',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _pricingUnit == 'hour'
                              ? _priceValue == null
                                    ? 'กำหนดช่วงเป็นนาทีได้; วันเฉพาะทับกฎทุกวัน และช่วงนอกกฎจะจองไม่ได้ถ้าไม่มีราคาเริ่มต้น'
                                    : 'กำหนดช่วงเป็นนาทีได้; วันเฉพาะทับกฎทุกวัน และช่วงนอกกฎใช้ราคาเริ่มต้น'
                              : 'ต้องเลือกคิดราคาต่อชั่วโมงเพื่อกำหนดราคาแยกช่วงเวลา',
                          style: const TextStyle(fontSize: 12),
                        ),
                        for (var i = 0; i < _priceRules.length; i++)
                          _priceRuleTile(i),
                        if (_priceRulesError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _priceRulesError!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: _pricingUnit == 'hour'
                              ? _addPriceRule
                              : null,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('เพิ่มช่วงราคา'),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _capacity,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'จำนวนการจองซ้ำได้',
                                  helperText: 'ปกติ = 1',
                                  errorText:
                                      _capacity.text.trim().isNotEmpty &&
                                          _capacityValue == null
                                      ? '1–100'
                                      : null,
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _courtType,
                                decoration: const InputDecoration(
                                  labelText: 'ประเภทพื้น',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('-'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'standard',
                                    child: Text('มาตรฐาน'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'synthetic',
                                    child: Text('สังเคราะห์'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'grass',
                                    child: Text('หญ้า'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'clay',
                                    child: Text('ดิน'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'hard',
                                    child: Text('แข็ง'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'wood',
                                    child: Text('ไม้'),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _courtType = v),
                              ),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('ในร่ม'),
                          value: _indoor,
                          onChanged: (v) => setState(() => _indoor = v),
                        ),
                        if (editing)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('เปิดใช้งานรายการ'),
                            subtitle: const Text(
                              'รายการที่ปิดจะไม่รับการจองใหม่',
                            ),
                            value: _isActive,
                            onChanged: (v) => setState(() => _isActive = v),
                          ),
                        const SizedBox(height: 4),
                        const Text(
                          'รูปแบบการจอง',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'instant',
                              label: Text('ยืนยันทันที'),
                              icon: Icon(Icons.bolt_rounded),
                            ),
                            ButtonSegment(
                              value: 'owner_approval',
                              label: Text('รออนุมัติ'),
                              icon: Icon(Icons.hourglass_top_rounded),
                            ),
                          ],
                          selected: {_approvalMode},
                          onSelectionChanged: (sel) =>
                              setState(() => _approvalMode = sel.first),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'รอบเปิดรับจองล่วงหน้า',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'สล็อตที่ยังไม่ถึงรอบเปิดจองจะแสดงแต่เลือกไม่ได้',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        SegmentedButton<String>(
                          key: const ValueKey('court-release-mode'),
                          segments: const [
                            ButtonSegment(
                              value: 'inherit',
                              label: Text('ตามสถานที่'),
                            ),
                            ButtonSegment(
                              value: 'always_open',
                              label: Text('เปิดตลอด'),
                            ),
                            ButtonSegment(
                              value: 'custom',
                              label: Text('กำหนดเอง'),
                            ),
                          ],
                          selected: {_releaseMode},
                          onSelectionChanged: (sel) =>
                              setState(() => _releaseMode = sel.first),
                        ),
                        if (_releaseMode == 'inherit')
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'ใช้รอบเปิดจองของสถานที่ — ถ้าสถานที่ไม่ได้ตั้งไว้ จองล่วงหน้าได้ไม่จำกัด',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        if (_releaseMode == 'always_open')
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'รายการนี้รับจองล่วงหน้าได้ไม่จำกัด ไม่ว่าสถานที่จะตั้งรอบไว้หรือไม่',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        if (_releaseMode == 'custom') ...[
                          const SizedBox(height: 8),
                          const Text(
                            'วันที่เปิดรอบ',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'เลือกได้หลายวัน โดยใช้เวลาเดียวกัน ส่วนวันอื่นใช้รอบของสถานที่',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              FilterChip(
                                key: const ValueKey('court-release-all-days'),
                                label: const Text('ทุกวัน'),
                                selected: _releaseDays.length == 7,
                                onSelected: (_) => setState(
                                  () => _releaseDays.addAll(
                                    CourtBookingReleaseSchedule
                                        .weekdayLabels
                                        .keys,
                                  ),
                                ),
                              ),
                              for (final entry in _weekdayLabels.entries)
                                FilterChip(
                                  key: ValueKey(
                                    'court-release-day-${entry.key}',
                                  ),
                                  label: Text(entry.value),
                                  selected: _releaseDays.contains(entry.key),
                                  onSelected: (selected) => setState(() {
                                    if (selected) {
                                      _releaseDays.add(entry.key);
                                    } else {
                                      _releaseDays.remove(entry.key);
                                    }
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'รอบ: ${CourtBookingReleaseSchedule.describeDays(_releaseDays)} เวลา ${_formatTime(_releaseTime)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _releaseTime,
                                );
                                if (picked != null && mounted) {
                                  setState(() => _releaseTime = picked);
                                }
                              },
                              child: Text(
                                'เวลาเดียวกันทุกวันที่เลือก · ${_formatTime(_releaseTime)}',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _releaseWindow,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'แต่ละรอบเปิดสล็อตล่วงหน้า (วัน)',
                              helperText: _releaseMinimumWindowDays == null
                                  ? 'เลือกอย่างน้อยหนึ่งวัน'
                                  : 'ขั้นต่ำ $_releaseMinimumWindowDays วัน · เช่น 7 = เปิดสล็อตใน 7 วันถัดไป',
                              errorText: _releaseWindowError,
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
                    label: editing ? 'บันทึก' : 'เพิ่มรายการ',
                    isFilled: true,
                    fillColor: AppColors.primaryDark,
                    onTap: _valid
                        ? () => Navigator.pop(context, {
                            'name': _name.text.trim(),
                            // 21.7.19 — 'inherit' sends NULL to clear the
                            // per-court override; 'custom' sends the text.
                            'unit_label_mode': _labelMode,
                            'unit_label': _labelMode == 'custom'
                                ? _unitLabel.text.trim()
                                : null,
                            'sport_id': _sportId,
                            'price_amount': _priceValue == -1
                                ? null
                                : _priceValue,
                            'pricing_unit': _pricingUnit,
                            'capacity': _capacityValue ?? 1,
                            'court_type': _courtType,
                            'indoor': _indoor,
                            'is_active': _isActive,
                            'approval_mode': _approvalMode,
                            'price_rules': _priceRulesJson,
                            // Always explicit so 'ตามสถานที่' clears an old
                            // override server-side (NULL = keep unseen).
                            'booking_release_mode': _releaseMode,
                            'booking_release_day_of_week':
                                _releaseMode == 'custom'
                                ? _releaseDayValue
                                : null,
                            'booking_release_days': _releaseMode == 'custom'
                                ? _releaseDaysValue
                                : null,
                            'booking_release_time': _releaseMode == 'custom'
                                ? _formatTime(_releaseTime)
                                : null,
                            'booking_release_window_days':
                                _releaseMode == 'custom'
                                ? _releaseWindowValue
                                : null,
                            if (widget.court != null) 'id': widget.court!.id,
                          })
                        : null,
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

class _PriceRuleDraft {
  int? dayOfWeek;
  TimeOfDay start;
  TimeOfDay end;
  final TextEditingController price;

  _PriceRuleDraft({
    required this.dayOfWeek,
    required this.start,
    required this.end,
    String priceText = '',
  }) : price = TextEditingController(text: priceText);

  factory _PriceRuleDraft.fromRule(VenueCourtPriceRule rule) {
    TimeOfDay parse(String value) {
      final parts = value.split(':');
      return TimeOfDay(
        hour: int.tryParse(parts.first) ?? 0,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      );
    }

    return _PriceRuleDraft(
      dayOfWeek: rule.dayOfWeek,
      start: parse(rule.startTime),
      end: parse(rule.endTime),
      priceText: rule.pricePerHour.toStringAsFixed(2),
    );
  }
}
