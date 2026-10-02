import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/shared/widgets/thai_address_picker/glass_date_time_picker.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';
import 'package:uuid/uuid.dart';

import '../../../data/coach_models.dart';
import '../coach_labels.dart';

/// Result payload of [CoachOfferingEditorDialog].
typedef CoachOfferingDraft =
    ({
      String? id,
      String offeringType,
      String title,
      String? description,
      String? sportId,
      List<String> learnerLevels,
      String teachingMode,
      String? locationId,
      String? locationLabel,
      double? price,
      String pricingUnit,
      int? capacity,
      int minEnrollment,
      int enrollmentCutoffHours,
      int cancellationCutoffHours,
      String scheduleNoResponse,
      bool autoConfirm,
      bool allowPartialEnrollment,
    });

/// Create/edit a class/course/1:1 product — custom-content GlassDialog.
class CoachOfferingEditorDialog extends StatefulWidget {
  final CoachOffering? existing;
  final List<CoachTeachingLocation> locations;
  final List<({String id, String name})> sports;

  const CoachOfferingEditorDialog({
    super.key,
    this.existing,
    this.locations = const [],
    this.sports = const [],
  });

  static Future<CoachOfferingDraft?> show(
    BuildContext context, {
    CoachOffering? existing,
    List<CoachTeachingLocation> locations = const [],
    List<({String id, String name})> sports = const [],
  }) {
    return GlassDialog.show<CoachOfferingDraft>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachOfferingEditorDialog(
        existing: existing,
        locations: locations,
        sports: sports,
      ),
    );
  }

  @override
  State<CoachOfferingEditorDialog> createState() =>
      _CoachOfferingEditorDialogState();
}

class _CoachOfferingEditorDialogState
    extends State<CoachOfferingEditorDialog> {
  static const _levelOptions = [
    'beginner',
    'intermediate',
    'advanced',
    'pro',
  ];
  static const _unitOptions = [
    CoachPricingUnit.perHour,
    CoachPricingUnit.perSession,
    CoachPricingUnit.perPerson,
    CoachPricingUnit.perGroup,
    CoachPricingUnit.package,
  ];
  static const _cutoffOptions = [1, 6, 12, 24, 48, 72];

  late CoachOfferingType _type;
  late final _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final Set<String> _levels = {
    ...?widget.existing?.learnerLevels,
  };
  late TeachingMode _mode =
      widget.existing?.teachingMode ?? TeachingMode.onsite;
  String? _sportId;
  CoachTeachingLocation? _location;
  late final _customLocation = TextEditingController(
    text: widget.existing != null && widget.existing!.locationId == null
        ? (widget.existing!.locationLabel ?? '')
        : '',
  );
  late final _price = TextEditingController(
    text: widget.existing?.price == null
        ? ''
        : widget.existing!.price!.toStringAsFixed(0),
  );
  late CoachPricingUnit _unit =
      widget.existing?.pricingUnit ?? CoachPricingUnit.perHour;
  late final _capacity = TextEditingController(
    text: widget.existing?.capacity?.toString() ?? '',
  );
  late final _minEnrollment = TextEditingController(
    text: (widget.existing?.minEnrollment ?? 0) > 0
        ? widget.existing!.minEnrollment.toString()
        : '',
  );
  late int _enrollmentCutoff =
      widget.existing?.enrollmentCutoffHours ?? 24;
  late int _cancelCutoff =
      widget.existing?.cancellationCutoffHours ?? 24;
  late String _noResponse =
      widget.existing?.scheduleNoResponse ?? 'cancel';
  late bool _autoConfirm = widget.existing?.autoConfirm ?? false;
  late bool _allowPartial =
      widget.existing?.allowPartialEnrollment ?? true;

  @override
  void initState() {
    super.initState();
    _type = widget.existing?.type ?? CoachOfferingType.groupClass;
    _sportId = widget.existing?.sportId;
    final locId = widget.existing?.locationId;
    if (locId != null) {
      for (final l in widget.locations) {
        if (l.id == locId) _location = l;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _description,
      _customLocation,
      _price,
      _capacity,
      _minEnrollment,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid {
    if (_title.text.trim().isEmpty) return false;
    final priceText = _price.text.trim();
    if (priceText.isNotEmpty && double.tryParse(priceText) == null) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 460,
        maxHeight: MediaQuery.of(context).size.height * 0.86,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.edit_note_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    existing == null
                        ? 'สร้างรายการใหม่'
                        : 'แก้ไข ${existing.title}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('ประเภท'),
                    _segWrap([
                      for (final t in CoachOfferingType.values)
                        _chip(
                          CoachLabels.offeringType(t),
                          _type == t,
                          () => setState(() => _type = t),
                        ),
                    ]),
                    _sectionLabel('ข้อมูลรายการ'),
                    _fieldTile(
                      child: TextField(
                        controller: _title,
                        decoration: _decoration('ชื่อรายการ *'),
                        style: _fieldStyle,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    _fieldTile(
                      child: TextField(
                        controller: _description,
                        maxLines: 3,
                        maxLength: 600,
                        decoration: _decoration('รายละเอียด (ไม่บังคับ)'),
                        style: _fieldStyle,
                      ),
                    ),
                    if (widget.sports.isNotEmpty) ...[
                      _sectionLabel('กีฬา'),
                      _segWrap([
                        for (final s in widget.sports)
                          _chip(
                            s.name,
                            _sportId == s.id,
                            () => setState(
                              () =>
                                  _sportId = _sportId == s.id ? null : s.id,
                            ),
                          ),
                      ]),
                    ],
                    _sectionLabel('ระดับผู้เรียนที่เหมาะ'),
                    _segWrap([
                      for (final l in _levelOptions)
                        _chip(
                          CoachLabels.level(l),
                          _levels.contains(l),
                          () => setState(
                            () => _levels.contains(l)
                                ? _levels.remove(l)
                                : _levels.add(l),
                          ),
                        ),
                    ]),
                    _sectionLabel('รูปแบบการสอน'),
                    _segWrap([
                      for (final m in TeachingMode.values)
                        _chip(
                          CoachLabels.mode(m),
                          _mode == m,
                          () => setState(() => _mode = m),
                        ),
                    ]),
                    _sectionLabel('สถานที่'),
                    if (widget.locations.isNotEmpty)
                      _segWrap([
                        for (final l in widget.locations)
                          _chip(
                            l.name,
                            _location?.id == l.id,
                            () => setState(
                              () => _location =
                                  _location?.id == l.id ? null : l,
                            ),
                          ),
                      ]),
                    _fieldTile(
                      child: TextField(
                        controller: _customLocation,
                        decoration: _decoration(
                          widget.locations.isEmpty
                              ? 'สถานที่ / รายละเอียด (เช่น Zoom link ภายหลัง)'
                              : 'หรือระบุสถานที่เอง',
                        ),
                        style: _fieldStyle,
                      ),
                    ),
                    _sectionLabel('ราคาและที่นั่ง'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _fieldTile(
                            child: TextField(
                              controller: _price,
                              keyboardType: TextInputType.number,
                              decoration: _decoration('ราคา (฿)'),
                              style: _fieldStyle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: _fieldTile(
                            child: DropdownButtonFormField<
                              CoachPricingUnit
                            >(
                              initialValue: _unit,
                              isExpanded: true,
                              decoration:
                                  _decoration('หน่วยราคา'),
                              dropdownColor: Colors.white,
                              style: _fieldStyle,
                              items: [
                                for (final u in _unitOptions)
                                  DropdownMenuItem(
                                    value: u,
                                    child: Text(
                                      CoachLabels.pricingUnit(u),
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _unit = v ?? _unit),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _fieldTile(
                            child: TextField(
                              controller: _capacity,
                              keyboardType: TextInputType.number,
                              decoration:
                                  _decoration('ที่นั่งต่อรอบ'),
                              style: _fieldStyle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _fieldTile(
                            child: TextField(
                              controller: _minEnrollment,
                              keyboardType: TextInputType.number,
                              decoration: _decoration('ขั้นต่ำที่เปิด'),
                              style: _fieldStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
                    _sectionLabel('เวลาปิดรับสมัคร (ชม. ก่อนรอบแรก)'),
                    _segWrap([
                      for (final h in _cutoffOptions)
                        _chip(
                          '$h ชม.',
                          _enrollmentCutoff == h,
                          () => setState(() => _enrollmentCutoff = h),
                        ),
                    ]),
                    _sectionLabel('ยกเลิกได้ถึง (ชม. ก่อนรอบแรก)'),
                    _segWrap([
                      for (final h in _cutoffOptions)
                        _chip(
                          '$h ชม.',
                          _cancelCutoff == h,
                          () => setState(() => _cancelCutoff = h),
                        ),
                    ]),
                    _sectionLabel('เมื่อผู้เรียนไม่ตอบการเลื่อนตาราง'),
                    _segWrap([
                      _chip(
                        'ยกเลิกรอบนั้น',
                        _noResponse == 'cancel',
                        () => setState(() => _noResponse = 'cancel'),
                      ),
                      _chip(
                        'คงรอบเดิมไว้',
                        _noResponse == 'keep',
                        () => setState(() => _noResponse = 'keep'),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    _toggleRow(
                      'ยืนยันการสมัครอัตโนมัติ',
                      'ปิด = ผู้เรียนส่งคำขอแล้วรอคุณอนุมัติ',
                      _autoConfirm,
                      (v) => setState(() => _autoConfirm = v),
                    ),
                    _toggleRow(
                      'อนุญาตเลือกเฉพาะบางรอบ',
                      'ปิด = สมัครได้ทั้งหลักสูตรเท่านั้น',
                      _allowPartial,
                      (v) => setState(() => _allowPartial = v),
                    ),
                  ],
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
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GlassActionButton(
                    label: 'บันทึก',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: _valid ? _save : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    Navigator.of(context).pop((
      id: widget.existing?.id,
      offeringType: switch (_type) {
        CoachOfferingType.oneOnOne => 'one_on_one',
        CoachOfferingType.course => 'course',
        _ => 'group_class',
      },
      title: _title.text.trim(),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      sportId: _sportId,
      learnerLevels: _levels.toList(),
      teachingMode: switch (_mode) {
        TeachingMode.online => 'online',
        TeachingMode.both => 'both',
        _ => 'onsite',
      },
      locationId: _location?.id,
      locationLabel: _location != null
          ? _location!.name
          : (_customLocation.text.trim().isEmpty
              ? null
              : _customLocation.text.trim()),
      price: double.tryParse(_price.text.trim()),
      pricingUnit: switch (_unit) {
        CoachPricingUnit.perPerson => 'per_person',
        CoachPricingUnit.perGroup => 'per_group',
        CoachPricingUnit.perSession => 'per_session',
        CoachPricingUnit.package => 'package',
        _ => 'per_hour',
      },
      capacity: int.tryParse(_capacity.text.trim()),
      minEnrollment: int.tryParse(_minEnrollment.text.trim()) ?? 0,
      enrollmentCutoffHours: _enrollmentCutoff,
      cancellationCutoffHours: _cancelCutoff,
      scheduleNoResponse: _noResponse,
      autoConfirm: _autoConfirm,
      allowPartialEnrollment: _allowPartial,
    ));
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
    border: InputBorder.none,
    counterText: '',
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 12,
    ),
  );

  static const _fieldStyle = TextStyle(
    fontSize: 13,
    color: Color(0xFF1E293B),
  );

  Widget _fieldTile({required Widget child}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: LitGlassSurface.frosted(borderRadius: 12, child: child),
  );

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    ),
  );

  Widget _segWrap(List<Widget> children) =>
      Wrap(spacing: 6, runSpacing: 6, children: children);

  Widget _chip(String label, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      );

  Widget _toggleRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: LitGlassSurface.frosted(
          borderRadius: 12,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  activeThumbColor: AppColors.primaryDark,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
      );
}

/// Session row draft used by [CoachSessionsEditorDialog].
class CoachSessionDraft {
  final String? id;
  DateTime startsAt;
  DateTime endsAt;
  int? capacity;
  double? price;
  String? locationLabel;

  CoachSessionDraft({
    this.id,
    required this.startsAt,
    required this.endsAt,
    this.capacity,
    this.price,
    this.locationLabel,
  });

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    if (capacity != null) 'capacity': capacity,
    if (price != null) 'price': price,
    if (locationLabel != null && locationLabel!.isNotEmpty)
      'location_label': locationLabel,
  };
}

/// Edits the session list of a class/course offering — replace-all editor
/// matching `set_coach_offering_sessions`.
class CoachSessionsEditorDialog extends StatefulWidget {
  final CoachOffering offering;

  const CoachSessionsEditorDialog({super.key, required this.offering});

  /// Pops with the edited session list (still in-memory — the caller
  /// persists through `setOfferingSessions`).
  static Future<List<CoachSessionDraft>?> show(
    BuildContext context, {
    required CoachOffering offering,
  }) {
    return GlassDialog.show<List<CoachSessionDraft>>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachSessionsEditorDialog(offering: offering),
    );
  }

  @override
  State<CoachSessionsEditorDialog> createState() =>
      _CoachSessionsEditorDialogState();
}

class _CoachSessionsEditorDialogState
    extends State<CoachSessionsEditorDialog> {
  late List<CoachSessionDraft> _drafts;

  @override
  void initState() {
    super.initState();
    _drafts = [
      for (final s in widget.offering.sessions)
        CoachSessionDraft(
          id: s.id,
          startsAt: s.startsAt,
          endsAt: s.endsAt,
          capacity: s.capacity,
          price: s.price,
          locationLabel: s.locationLabel,
        ),
    ];
  }

  Future<void> _editDraft(int index) async {
    final existing = index < 0 ? null : _drafts[index];
    final result = await _SessionTimingDialog.show(
      context,
      startsAt: existing?.startsAt,
      endsAt: existing?.endsAt,
      capacity: existing?.capacity,
      price: existing?.price,
      locationLabel: existing?.locationLabel,
      defaultCapacity: widget.offering.capacity,
      defaultPrice: widget.offering.price,
      defaultLocation: widget.offering.locationLabel,
      timezone: widget.offering.timezone,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index < 0) {
        _drafts.add(result);
      } else {
        _drafts[index] = result;
      }
      _drafts.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.event_note_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'รอบการสอน — ${widget.offering.title}',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: _drafts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'ยังไม่มีรอบการสอน — กดปุ่มด้านล่างเพื่อเพิ่ม',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _drafts.length,
                      itemBuilder: (_, i) {
                        final d = _drafts[i];
                        final isPast =
                            d.startsAt.isBefore(DateTime.now()) &&
                            d.id != null;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: LitGlassSurface.frosted(
                            borderRadius: 12,
                            child: ListTile(
                              dense: true,
                              title: Text(
                                'รอบ ${i + 1} · ${formatThaiSessionRange(d.startsAt.toLocal(), d.endsAt.toLocal())}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (d.locationLabel != null)
                                    d.locationLabel!,
                                  if (d.capacity != null)
                                    'ที่นั่ง ${d.capacity}',
                                  if (d.price != null)
                                    CoachLabels.formatBaht(d.price),
                                ].join(' · '),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    color: const Color(0xFF475569),
                                    onPressed: () => _editDraft(i),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                    ),
                                    color: Colors.red.shade400,
                                    tooltip: isPast
                                        ? 'รอบที่เคยเรียน/ยกเลิกไปแล้ว '
                                          'ถูกเก็บไว้เมื่อบันทึก'
                                        : 'ลบรอบนี้',
                                    onPressed: () => setState(
                                      () => _drafts.removeAt(i),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: '+ เพิ่มรอบ',
                    onTap: () => _editDraft(-1),
                  ),
                ),
                const SizedBox(width: 10),
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
                    label: 'บันทึกรอบการสอน',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: _drafts.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_drafts),
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

class _SessionTimingDialog extends StatefulWidget {
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? capacity;
  final double? price;
  final String? locationLabel;
  final int? defaultCapacity;
  final double? defaultPrice;
  final String? defaultLocation;
  final String timezone;

  const _SessionTimingDialog({
    this.startsAt,
    this.endsAt,
    this.capacity,
    this.price,
    this.locationLabel,
    this.defaultCapacity,
    this.defaultPrice,
    this.defaultLocation,
    required this.timezone,
  });

  static Future<CoachSessionDraft?> show(
    BuildContext context, {
    DateTime? startsAt,
    DateTime? endsAt,
    int? capacity,
    double? price,
    String? locationLabel,
    int? defaultCapacity,
    double? defaultPrice,
    String? defaultLocation,
    String timezone = 'Asia/Bangkok',
  }) {
    return GlassDialog.show<CoachSessionDraft>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => _SessionTimingDialog(
        startsAt: startsAt,
        endsAt: endsAt,
        capacity: capacity,
        price: price,
        locationLabel: locationLabel,
        defaultCapacity: defaultCapacity,
        defaultPrice: defaultPrice,
        defaultLocation: defaultLocation,
        timezone: timezone,
      ),
    );
  }

  @override
  State<_SessionTimingDialog> createState() => _SessionTimingDialogState();
}

class _SessionTimingDialogState extends State<_SessionTimingDialog> {
  late DateTime _start;
  late DateTime _end;
  late final _capacity = TextEditingController(
    text: widget.capacity?.toString() ??
        widget.defaultCapacity?.toString() ??
        '',
  );
  late final _price = TextEditingController(
    text: (widget.price ?? widget.defaultPrice)?.toStringAsFixed(0) ?? '',
  );
  late final _location = TextEditingController(
    text: widget.locationLabel ?? widget.defaultLocation ?? '',
  );

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final base = widget.startsAt ??
        DateTime(now.year, now.month, now.day + 1, 9);
    _start = base;
    _end = widget.endsAt ?? base.add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _capacity.dispose();
    _price.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isStart) async {
    final initial = isStart ? _start : _end;
    final date = await GlassDatePicker.show(
      context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await GlassTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      final picked = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _start = picked;
        if (!_end.isAfter(_start)) {
          _end = _start.add(const Duration(hours: 1));
        }
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final valid = _end.isAfter(_start);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'รอบการสอน (${widget.timezone})',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              _timeRow('เริ่ม', _start, () => _pick(true)),
              _timeRow('สิ้นสุด', _end, () => _pick(false)),
              if (!valid)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่ม',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.red.shade300,
                    ),
                  ),
                ),
              _numField(_capacity, 'ที่นั่ง (เว้นว่าง = ไม่จำกัด)'),
              _numField(_price, 'ราคารอบนี้ (฿)'),
              _numField(_location, 'สถานที่ (ไม่บังคับ)', numeric: false),
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
                    child: GlassActionButton(
                      label: 'บันทึกรอบ',
                      isFilled: true,
                      fillColor: AppColors.primary,
                      onTap: valid
                          ? () => Navigator.of(context).pop(
                              CoachSessionDraft(
                                startsAt: _start,
                                endsAt: _end,
                                capacity: int.tryParse(
                                  _capacity.text.trim(),
                                ),
                                price: double.tryParse(
                                  _price.text.trim(),
                                ),
                                locationLabel:
                                    _location.text.trim().isEmpty
                                    ? null
                                    : _location.text.trim(),
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeRow(String label, DateTime value, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: LitGlassSurface.frosted(
          borderRadius: 12,
          child: ListTile(
            dense: true,
            onTap: onTap,
            leading: const Icon(
              Icons.schedule_rounded,
              size: 18,
              color: Color(0xFF475569),
            ),
            title: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            subtitle: Text(
              formatThaiBuddhistDateTime(value),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF94A3B8),
            ),
          ),
        ),
      );

  Widget _numField(
    TextEditingController c,
    String hint, {
    bool numeric = true,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: LitGlassSurface.frosted(
          borderRadius: 12,
          child: TextField(
            controller: c,
            keyboardType:
                numeric ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade500,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      );
}

/// 1:1 slot editor — create a new slot or move an unbooked one.
class CoachSlotEditorDialog extends StatefulWidget {
  final CoachSlot? existing;
  final String timezone;

  const CoachSlotEditorDialog({
    super.key,
    this.existing,
    this.timezone = 'Asia/Bangkok',
  });

  /// Pops with `({DateTime startsAt, DateTime endsAt, bool publish})`.
  static Future<({DateTime startsAt, DateTime endsAt, bool publish})?>
      show(
    BuildContext context, {
    CoachSlot? existing,
    String timezone = 'Asia/Bangkok',
  }) {
    return GlassDialog.show<
      ({DateTime startsAt, DateTime endsAt, bool publish})
    >(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachSlotEditorDialog(
        existing: existing,
        timezone: timezone,
      ),
    );
  }

  @override
  State<CoachSlotEditorDialog> createState() =>
      _CoachSlotEditorDialogState();
}

class _CoachSlotEditorDialogState extends State<CoachSlotEditorDialog> {
  late DateTime _start;
  late DateTime _end;
  bool _publish = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = widget.existing?.startsAt ??
        DateTime(now.year, now.month, now.day + 1, 9);
    _end = widget.existing?.endsAt ??
        _start.add(const Duration(hours: 1));
    _publish = widget.existing?.status == CoachSlotStatus.published;
  }

  Future<void> _pick(bool isStart) async {
    final initial = isStart ? _start : _end;
    final date = await GlassDatePicker.show(
      context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await GlassTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      final picked = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _start = picked;
        if (!_end.isAfter(_start)) {
          _end = _start.add(const Duration(hours: 1));
        }
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final valid = _end.isAfter(_start);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null
                  ? 'สร้างช่วงเวลา 1:1'
                  : 'ย้ายช่วงเวลา 1:1',
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'เขตเวลา ${widget.timezone} · slot ที่มีการจองแล้วย้ายไม่ได้',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            for (final (label, value, isStart) in [
              ('เริ่ม', _start, true),
              ('สิ้นสุด', _end, false),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LitGlassSurface.frosted(
                  borderRadius: 12,
                  child: ListTile(
                    dense: true,
                    onTap: () => _pick(isStart),
                    leading: const Icon(
                      Icons.schedule_rounded,
                      size: 18,
                      color: Color(0xFF475569),
                    ),
                    title: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    subtitle: Text(
                      formatThaiBuddhistDateTime(value),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ),
            if (widget.existing == null ||
                widget.existing!.status == CoachSlotStatus.draft)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _publish = !_publish),
                  child: Row(
                    children: [
                      Icon(
                        _publish
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 20,
                        color: _publish
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'เปิดให้จองทันที (ไม่ติ๊ก = เก็บเป็นแบบร่าง)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
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
                    label: widget.existing == null
                        ? (_publish ? 'สร้างและเปิดจอง' : 'บันทึกแบบร่าง')
                        : 'ย้ายเวลา',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: valid
                        ? () => Navigator.of(context).pop((
                            startsAt: _start,
                            endsAt: _end,
                            publish: _publish,
                          ))
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

/// Weekly availability editor — replace-all windows in coach-local time.
class CoachAvailabilityEditorDialog extends StatefulWidget {
  final List<CoachAvailabilityWindow> windows;

  const CoachAvailabilityEditorDialog({super.key, required this.windows});

  /// Pops with the new window list for `set_coach_availability`.
  static Future<List<Map<String, dynamic>>?> show(
    BuildContext context, {
    required List<CoachAvailabilityWindow> windows,
  }) {
    return GlassDialog.show<List<Map<String, dynamic>>>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachAvailabilityEditorDialog(windows: windows),
    );
  }

  @override
  State<CoachAvailabilityEditorDialog> createState() =>
      _CoachAvailabilityEditorDialogState();
}

class _CoachAvailabilityEditorDialogState
    extends State<CoachAvailabilityEditorDialog> {
  late final List<CoachAvailabilityWindow> _windows = [
    ...widget.windows,
  ];

  Future<void> _add() async {
    final draft = await _AvailabilityWindowDialog.show(context);
    if (draft == null || !mounted) return;
    setState(() {
      _windows.add(draft);
      _windows.sort(
        (a, b) => a.dayOfWeek != b.dayOfWeek
            ? a.dayOfWeek.compareTo(b.dayOfWeek)
            : a.startTime.compareTo(b.startTime),
      );
    });
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
          children: [
            Row(
              children: [
                const Icon(
                  Icons.event_available_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'เวลาว่างประจำสัปดาห์',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ใช้เป็นแนวทางแสดงช่วงเวลา — slot จริงเปิดทีละช่วงในส่วน Availability',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _windows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'ยังไม่มีช่วงเวลา — กดเพิ่มด้านล่าง',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _windows.length,
                      itemBuilder: (_, i) {
                        final w = _windows[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: LitGlassSurface.frosted(
                            borderRadius: 12,
                            child: ListTile(
                              dense: true,
                              title: Text(
                                '${CoachLabels.dayOfWeek(w.dayOfWeek)} '
                                '${w.startTime}–${w.endTime}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                                color: Colors.red.shade400,
                                onPressed: () => setState(
                                  () => _windows.removeAt(i),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: '+ เพิ่มช่วงเวลา',
                    onTap: _add,
                  ),
                ),
                const SizedBox(width: 10),
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
                    label: 'บันทึก',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: () => Navigator.of(context).pop([
                      for (final w in _windows)
                        {
                          'day': w.dayOfWeek,
                          'start': w.startTime,
                          'end': w.endTime,
                        },
                    ]),
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

class _AvailabilityWindowDialog extends StatefulWidget {
  const _AvailabilityWindowDialog();

  static Future<CoachAvailabilityWindow?> show(BuildContext context) {
    return GlassDialog.show<CoachAvailabilityWindow>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => const _AvailabilityWindowDialog(),
    );
  }

  @override
  State<_AvailabilityWindowDialog> createState() =>
      _AvailabilityWindowDialogState();
}

class _AvailabilityWindowDialogState
    extends State<_AvailabilityWindowDialog> {
  int _day = 1;
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 10, minute: 0);

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _valid =>
      _end.hour * 60 + _end.minute > _start.hour * 60 + _start.minute;

  Future<void> _pick(bool isStart) async {
    final picked = await GlassTimePicker.show(
      context,
      initialTime: isStart ? _start : _end,
    );
    if (picked == null || !mounted) return;
    setState(() => isStart ? _start = picked : _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ช่วงเวลาว่าง',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 0; d < 7; d++)
                  GestureDetector(
                    onTap: () => setState(() => _day = d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _day == d
                            ? AppColors.primary.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: _day == d
                              ? AppColors.primary
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        CoachLabels.dayOfWeek(d),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _day == d
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: LitGlassSurface.frosted(
                    borderRadius: 12,
                    child: ListTile(
                      dense: true,
                      onTap: () => _pick(true),
                      title: Text(
                        'เริ่ม',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      subtitle: Text(
                        _fmt(_start),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LitGlassSurface.frosted(
                    borderRadius: 12,
                    child: ListTile(
                      dense: true,
                      onTap: () => _pick(false),
                      title: Text(
                        'สิ้นสุด',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      subtitle: Text(
                        _fmt(_end),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
                  child: GlassActionButton(
                    label: 'เพิ่ม',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: _valid
                        ? () => Navigator.of(context).pop(
                            CoachAvailabilityWindow(
                              dayOfWeek: _day,
                              startTime: _fmt(_start),
                              endTime: _fmt(_end),
                            ),
                          )
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

/// Contacts editor — private channels visible only to coach/admin and
/// learners with a confirmed/completed relationship.
class CoachContactsEditorDialog extends StatefulWidget {
  final CoachContact? contact;

  const CoachContactsEditorDialog({super.key, this.contact});

  /// Pops with `({String? phone, String? lineId, String? facebookUrl})`.
  static Future<({String? phone, String? lineId, String? facebookUrl})?>
      show(BuildContext context, {CoachContact? contact}) {
    return GlassDialog.show<
      ({String? phone, String? lineId, String? facebookUrl})
    >(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachContactsEditorDialog(contact: contact),
    );
  }

  @override
  State<CoachContactsEditorDialog> createState() =>
      _CoachContactsEditorDialogState();
}

class _CoachContactsEditorDialogState
    extends State<CoachContactsEditorDialog> {
  late final _phone =
      TextEditingController(text: widget.contact?.phone ?? '');
  late final _line =
      TextEditingController(text: widget.contact?.lineId ?? '');
  late final _facebook =
      TextEditingController(text: widget.contact?.facebookUrl ?? '');

  @override
  void dispose() {
    _phone.dispose();
    _line.dispose();
    _facebook.dispose();
    super.dispose();
  }

  bool get _valid => [
    _phone.text.trim(),
    _line.text.trim(),
    _facebook.text.trim(),
  ].any((s) => s.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ช่องทางติดต่อ (ส่วนตัว)',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'แสดงเฉพาะผู้เรียนที่มีการนัด/สมัครที่ยืนยันแล้วเท่านั้น',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            for (final (ctrl, hint, icon) in [
              (_phone, 'เบอร์โทรศัพท์', Icons.phone_outlined),
              (_line, 'LINE ID', Icons.chat_bubble_outline_rounded),
              (_facebook, 'Facebook URL', Icons.facebook_rounded),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LitGlassSurface.frosted(
                  borderRadius: 12,
                  child: TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade500,
                      ),
                      prefixIcon: Icon(
                        icon,
                        size: 18,
                        color: const Color(0xFF64748B),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1E293B),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            const SizedBox(height: 8),
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
                    label: 'บันทึก',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: _valid
                        ? () => Navigator.of(context).pop((
                            phone: _phone.text.trim().isEmpty
                                ? null
                                : _phone.text.trim(),
                            lineId: _line.text.trim().isEmpty
                                ? null
                                : _line.text.trim(),
                            facebookUrl: _facebook.text.trim().isEmpty
                                ? null
                                : _facebook.text.trim(),
                          ))
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

/// Teaching locations editor — replace-all list (venue pick happens
/// through a simple name/address form; venue linkage keeps existing ids).
class CoachLocationsEditorDialog extends StatefulWidget {
  final List<CoachTeachingLocation> locations;

  const CoachLocationsEditorDialog({super.key, required this.locations});

  static Future<List<CoachTeachingLocation>?> show(
    BuildContext context, {
    required List<CoachTeachingLocation> locations,
  }) {
    return GlassDialog.show<List<CoachTeachingLocation>>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachLocationsEditorDialog(locations: locations),
    );
  }

  @override
  State<CoachLocationsEditorDialog> createState() =>
      _CoachLocationsEditorDialogState();
}

class _CoachLocationsEditorDialogState
    extends State<CoachLocationsEditorDialog> {
  late final List<CoachTeachingLocation> _items = [
    ...widget.locations,
  ];

  Future<void> _edit(int index) async {
    final existing = index < 0 ? null : _items[index];
    final result = await _LocationFormDialog.show(
      context,
      existing: existing,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index < 0) {
        _items.add(result);
      } else {
        _items[index] = result;
      }
    });
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
          children: [
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'สถานที่สอน',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: _items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'ยังไม่มีสถานที่ — เพิ่มสถานที่ที่สอนประจำ',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final l = _items[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: LitGlassSurface.frosted(
                            borderRadius: 12,
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                l.kind == CoachLocationKind.venue
                                    ? Icons.stadium_outlined
                                    : Icons.place_outlined,
                                size: 18,
                                color: const Color(0xFF475569),
                              ),
                              title: Text(
                                l.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              subtitle: l.address?.isNotEmpty == true
                                  ? Text(
                                      l.address!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 17,
                                    ),
                                    color: const Color(0xFF475569),
                                    onPressed: () => _edit(i),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 17,
                                    ),
                                    color: Colors.red.shade400,
                                    onPressed: () => setState(
                                      () => _items.removeAt(i),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: '+ เพิ่มสถานที่',
                    onTap: () => _edit(-1),
                  ),
                ),
                const SizedBox(width: 10),
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
                    label: 'บันทึก',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: () => Navigator.of(context).pop(_items),
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

class _LocationFormDialog extends StatefulWidget {
  final CoachTeachingLocation? existing;

  const _LocationFormDialog({this.existing});

  static Future<CoachTeachingLocation?> show(
    BuildContext context, {
    CoachTeachingLocation? existing,
  }) {
    return GlassDialog.show<CoachTeachingLocation>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => _LocationFormDialog(existing: existing),
    );
  }

  @override
  State<_LocationFormDialog> createState() => _LocationFormDialogState();
}

class _LocationFormDialogState extends State<_LocationFormDialog> {
  late final _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.address ?? '');

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'สถานที่สอน',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            for (final (ctrl, hint) in [
              (_name, 'ชื่อสถานที่ *'),
              (_address, 'ที่อยู่ / รายละเอียด'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LitGlassSurface.frosted(
                  borderRadius: 12,
                  child: TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1E293B),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            const SizedBox(height: 8),
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
                  child: GlassActionButton(
                    label: 'บันทึก',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: valid
                        ? () => Navigator.of(context).pop(
                            CoachTeachingLocation(
                              id: widget.existing?.id ??
                                  const Uuid().v4(),
                              kind: widget.existing?.kind ??
                                  CoachLocationKind.custom,
                              venueId: widget.existing?.venueId,
                              name: _name.text.trim(),
                              address: _address.text.trim().isEmpty
                                  ? null
                                  : _address.text.trim(),
                              timezone:
                                  widget.existing?.timezone ??
                                  'Asia/Bangkok',
                            ),
                          )
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

/// Certifications editor — replace-all; edited rows drop back to pending
/// review. Document URLs are write-only (originals stay private).
class CoachCertificationsEditorDialog extends StatefulWidget {
  final List<CoachCertification> items;

  const CoachCertificationsEditorDialog({super.key, required this.items});

  static Future<List<CoachCertification>?> show(
    BuildContext context, {
    required List<CoachCertification> items,
  }) {
    return GlassDialog.show<List<CoachCertification>>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) =>
          CoachCertificationsEditorDialog(items: items),
    );
  }

  @override
  State<CoachCertificationsEditorDialog> createState() =>
      _CoachCertificationsEditorDialogState();
}

class _CoachCertificationsEditorDialogState
    extends State<CoachCertificationsEditorDialog> {
  late final List<CoachCertification> _items = [...widget.items];

  Future<void> _edit(int index) async {
    final existing = index < 0 ? null : _items[index];
    final result = await _CertFormDialog.show(
      context,
      existing: existing,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index < 0) {
        _items.add(result);
      } else {
        _items[index] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'ใบรับรองและคุณวุฒิ',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ชื่อและหน่วยงานแสดงสาธารณะเมื่ออนุมัติแล้ว — เอกสารต้นฉบับเป็นส่วนตัว',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'ยังไม่มีใบรับรอง — เพิ่มอย่างน้อย 1 รายการเพื่อส่งตรวจ',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final c = _items[i];
                        final (label, color) = switch (c.status) {
                          CoachCertStatus.approved => (
                            'อนุมัติแล้ว',
                            const Color(0xFF2E7D32),
                          ),
                          CoachCertStatus.rejected => (
                            'ถูกปฏิเสธ',
                            const Color(0xFFC62828),
                          ),
                          _ => ('รอตรวจ', const Color(0xFFEF6C00)),
                        };
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: LitGlassSurface.frosted(
                            borderRadius: 12,
                            child: ListTile(
                              dense: true,
                              title: Text(
                                c.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (c.issuer?.isNotEmpty == true)
                                    c.issuer!,
                                  if (c.issuedYear != null)
                                    'ปี ${c.issuedYear! + 543}',
                                  if (c.rejectionReason?.isNotEmpty ==
                                      true)
                                    'เหตุผล: ${c.rejectionReason}',
                                ].join(' · '),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2.5,
                                        ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(7),
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 17,
                                    ),
                                    color: const Color(0xFF475569),
                                    onPressed: () => _edit(i),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 17,
                                    ),
                                    color: Colors.red.shade400,
                                    onPressed: () => setState(
                                      () => _items.removeAt(i),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: '+ เพิ่มใบรับรอง',
                    onTap: () => _edit(-1),
                  ),
                ),
                const SizedBox(width: 10),
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
                    label: 'บันทึก',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: () => Navigator.of(context).pop(_items),
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

class _CertFormDialog extends StatefulWidget {
  final CoachCertification? existing;

  const _CertFormDialog({this.existing});

  static Future<CoachCertification?> show(
    BuildContext context, {
    CoachCertification? existing,
  }) {
    return GlassDialog.show<CoachCertification>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => _CertFormDialog(existing: existing),
    );
  }

  @override
  State<_CertFormDialog> createState() => _CertFormDialogState();
}

class _CertFormDialogState extends State<_CertFormDialog> {
  late final _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _issuer =
      TextEditingController(text: widget.existing?.issuer ?? '');
  late final _year = TextEditingController(
    text: widget.existing?.issuedYear?.toString() ?? '',
  );
  late final _docUrl = TextEditingController(
    text: widget.existing?.documentUrl ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _issuer.dispose();
    _year.dispose();
    _docUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ใบรับรอง',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              for (final (ctrl, hint, numeric) in [
                (_name, 'ชื่อใบรับรอง *', false),
                (_issuer, 'หน่วยงานที่ออก', false),
                (_year, 'ปีที่ออก (ค.ศ.)', true),
                (_docUrl, 'ลิงก์เอกสาร (ส่วนตัว — เฉพาะ admin เห็น)', false),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LitGlassSurface.frosted(
                    borderRadius: 12,
                    child: TextField(
                      controller: ctrl,
                      keyboardType:
                          numeric ? TextInputType.number : TextInputType.text,
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade500,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
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
                    child: GlassActionButton(
                      label: 'บันทึก',
                      isFilled: true,
                      fillColor: AppColors.primary,
                      onTap: valid
                          ? () => Navigator.of(context).pop(
                              CoachCertification(
                                id: widget.existing?.id ??
                                    const Uuid().v4(),
                                name: _name.text.trim(),
                                issuer: _issuer.text.trim().isEmpty
                                    ? null
                                    : _issuer.text.trim(),
                                issuedYear: int.tryParse(
                                  _year.text.trim(),
                                ),
                                documentUrl:
                                    _docUrl.text.trim().isEmpty
                                    ? null
                                    : _docUrl.text.trim(),
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Coach proposes a new time/location for an enrolled session.
class CoachProposeScheduleChangeDialog extends StatefulWidget {
  final CoachOfferingSession session;
  final String timezone;

  const CoachProposeScheduleChangeDialog({
    super.key,
    required this.session,
    this.timezone = 'Asia/Bangkok',
  });

  /// Pops with `({DateTime newStartsAt, DateTime newEndsAt, String? location, String? reason})`.
  static Future<
    ({
      DateTime newStartsAt,
      DateTime newEndsAt,
      String? location,
      String? reason,
    })?
  >
  show(
    BuildContext context, {
    required CoachOfferingSession session,
    String timezone = 'Asia/Bangkok',
  }) {
    return GlassDialog.show<
      ({
        DateTime newStartsAt,
        DateTime newEndsAt,
        String? location,
        String? reason,
      })
    >(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      panelAccentColor: AppColors.alertGold,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachProposeScheduleChangeDialog(
        session: session,
        timezone: timezone,
      ),
    );
  }

  @override
  State<CoachProposeScheduleChangeDialog> createState() =>
      _CoachProposeScheduleChangeDialogState();
}

class _CoachProposeScheduleChangeDialogState
    extends State<CoachProposeScheduleChangeDialog> {
  late DateTime _start = widget.session.startsAt;
  late DateTime _end = widget.session.endsAt;
  late final _location = TextEditingController(
    text: widget.session.locationLabel ?? '',
  );
  final _reason = TextEditingController();

  @override
  void dispose() {
    _location.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isStart) async {
    final initial = isStart ? _start : _end;
    final date = await GlassDatePicker.show(
      context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await GlassTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      final picked = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _start = picked;
        if (!_end.isAfter(_start)) {
          _end = _start.add(const Duration(hours: 1));
        }
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final valid = _end.isAfter(_start);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'เสนอเปลี่ยนตารางรอบนี้',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              LitGlassSurface.frosted(
                borderRadius: 12,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'เดิม: ${formatThaiSessionRange(widget.session.startsAt.toLocal(), widget.session.endsAt.toLocal())} '
                    '(${widget.timezone}) — ยืนยันแล้ว ${widget.session.confirmedCount} คน',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final (label, value, isStart) in [
                ('เริ่มใหม่', _start, true),
                ('สิ้นสุดใหม่', _end, false),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LitGlassSurface.frosted(
                    borderRadius: 12,
                    child: ListTile(
                      dense: true,
                      onTap: () => _pick(isStart),
                      leading: const Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: Color(0xFF475569),
                      ),
                      title: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      subtitle: Text(
                        formatThaiBuddhistDateTime(value),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LitGlassSurface.frosted(
                  borderRadius: 12,
                  child: TextField(
                    controller: _location,
                    decoration: InputDecoration(
                      hintText: 'สถานที่ใหม่ (ถ้าเปลี่ยน)',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LitGlassSurface.frosted(
                  borderRadius: 12,
                  child: TextField(
                    controller: _reason,
                    maxLines: 2,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: 'เหตุผล (ผู้เรียนจะเห็น)',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      counterStyle: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              Text(
                'ผู้เรียนที่ยืนยันแล้วจะได้รับแจ้งเตือนและเลือกยอมรับ/ปฏิเสธ '
                '— หากไม่ตอบจะใช้นโยบายของรายการ',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
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
                      label: 'ส่งข้อเสนอ',
                      isFilled: true,
                      fillColor: AppColors.primary,
                      onTap: valid
                          ? () => Navigator.of(context).pop((
                              newStartsAt: _start,
                              newEndsAt: _end,
                              location:
                                  _location.text.trim().isEmpty
                                  ? null
                                  : _location.text.trim(),
                              reason: _reason.text.trim().isEmpty
                                  ? null
                                  : _reason.text.trim(),
                            ))
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
