import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../data/book_court_models.dart';

/// Owner editor for a single court: name, unit label, type, price, approval
/// mode, indoor flag. Returns a draft map the caller passes to
/// `upsert_sports_venue_court`.
class OwnerCourtEditorDialog {
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    VenueCourt? court,
    required String sportId,
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

  /// venue_sport choices (id → display name) shown as a dropdown when the
  /// venue offers more than one sport. Null = fixed [sportId].
  final Map<String, String>? sportChoices;

  const _OwnerCourtEditorDialogBody({
    this.court,
    required this.sportId,
    this.sportChoices,
  });

  @override
  State<_OwnerCourtEditorDialogBody> createState() =>
      _OwnerCourtEditorDialogBodyState();
}

class _OwnerCourtEditorDialogBodyState
    extends State<_OwnerCourtEditorDialogBody> {
  late final _name = TextEditingController(text: widget.court?.name ?? '');
  late final _unitLabel = TextEditingController(
    text: widget.court?.unitLabel ?? '',
  );
  late final _price = TextEditingController(
    text: widget.court?.priceAmount?.toStringAsFixed(0) ?? '',
  );
  late final _capacity = TextEditingController(
    text: (widget.court?.capacity ?? 1).toString(),
  );
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

  @override
  void dispose() {
    _name.dispose();
    _unitLabel.dispose();
    _price.dispose();
    _capacity.dispose();
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
    if (parsed == null || parsed < 0) return -1;
    return parsed;
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _capacityValue != null &&
      _priceValue != -1 &&
      _sportId != null;

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
                    editing ? 'แก้ไขสนาม' : 'เพิ่มสนาม',
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
                              for (final entry
                                  in widget.sportChoices!.entries)
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
                                'กีฬาเดิมถูกเอาออกจากสนามแล้ว — กรุณาเลือกกีฬาใหม่',
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
                            labelText: 'ชื่อสนาม/คอร์ท *',
                            hintText: 'เช่น คอร์ท 1, สนาม A',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _unitLabel,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อเรียกหน่วย',
                            helperText:
                                'เว้นว่างเพื่อใช้ค่าเริ่มต้นตามกีฬา (เช่น คอร์ท, สนาม, โต๊ะ)',
                            border: OutlineInputBorder(),
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
                                  labelText: 'ราคา (บาท)',
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
                                onChanged: (v) => setState(
                                  () => _pricingUnit = v ?? 'hour',
                                ),
                              ),
                            ),
                          ],
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
                          title: const Text('สนามในร่ม'),
                          value: _indoor,
                          onChanged: (v) => setState(() => _indoor = v),
                        ),
                        if (editing)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('เปิดใช้งานคอร์ท'),
                            subtitle: const Text(
                              'คอร์ทที่ปิดจะไม่รับการจองใหม่',
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
                    label: editing ? 'บันทึก' : 'เพิ่มสนาม',
                    isFilled: true,
                    fillColor: AppColors.primaryDark,
                    onTap: _valid
                        ? () => Navigator.pop(context, {
                            'name': _name.text.trim(),
                            'unit_label': _unitLabel.text.trim(),
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
