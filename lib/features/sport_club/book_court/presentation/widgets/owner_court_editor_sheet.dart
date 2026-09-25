import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';

/// Owner editor for a single court: name, unit label, type, price, approval
/// mode, indoor flag. Returns a draft map the caller passes to
/// `upsert_sports_venue_court`.
class OwnerCourtEditorSheet {
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    VenueCourt? court,
    required String sportId,
    Map<String, String>? sportChoices,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _OwnerCourtEditorSheetBody(
        court: court,
        sportId: sportId,
        sportChoices: sportChoices,
      ),
    );
  }
}

class _OwnerCourtEditorSheetBody extends StatefulWidget {
  final VenueCourt? court;
  final String sportId;

  /// venue_sport choices (id → display name) shown as a dropdown when the
  /// venue offers more than one sport. Null = fixed [sportId].
  final Map<String, String>? sportChoices;

  const _OwnerCourtEditorSheetBody({
    this.court,
    required this.sportId,
    this.sportChoices,
  });

  @override
  State<_OwnerCourtEditorSheetBody> createState() =>
      _OwnerCourtEditorSheetBodyState();
}

class _OwnerCourtEditorSheetBodyState
    extends State<_OwnerCourtEditorSheetBody> {
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
  late String _sportId = _initialSportId();

  String _initialSportId() {
    final preferred = widget.court?.sportId ?? widget.sportId;
    final choices = widget.sportChoices;
    if (choices != null &&
        choices.isNotEmpty &&
        !choices.containsKey(preferred)) {
      return choices.keys.first;
    }
    return preferred;
  }

  late String _pricingUnit = widget.court?.pricingUnit ?? 'hour';
  late String _approvalMode =
      widget.court?.approvalMode == BookingApprovalMode.ownerApproval
      ? 'owner_approval'
      : 'instant';
  late bool _indoor = widget.court?.indoor ?? true;
  late String? _courtType = widget.court?.courtType;

  @override
  void dispose() {
    _name.dispose();
    _unitLabel.dispose();
    _price.dispose();
    _capacity.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final editing = widget.court != null;
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
                editing ? 'แก้ไขสนาม' : 'เพิ่มสนาม',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.sportChoices != null &&
                  widget.sportChoices!.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: widget.sportChoices!.containsKey(_sportId)
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
                      decoration: const InputDecoration(
                        labelText: 'ราคา (บาท)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _pricingUnit,
                      decoration: const InputDecoration(
                        labelText: 'ต่อหน่วย',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'hour', child: Text('ชั่วโมง')),
                        DropdownMenuItem(value: 'session', child: Text('รอบ')),
                        DropdownMenuItem(value: 'match', child: Text('แมตช์')),
                        DropdownMenuItem(value: 'day', child: Text('วัน')),
                      ],
                      onChanged: (v) =>
                          setState(() => _pricingUnit = v ?? 'hour'),
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
                      decoration: const InputDecoration(
                        labelText: 'จำนวนการจองซ้ำได้',
                        helperText: 'ปกติ = 1',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _courtType,
                      decoration: const InputDecoration(
                        labelText: 'ประเภทพื้น',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('-')),
                        DropdownMenuItem(
                          value: 'standard',
                          child: Text('มาตรฐาน'),
                        ),
                        DropdownMenuItem(
                          value: 'synthetic',
                          child: Text('สังเคราะห์'),
                        ),
                        DropdownMenuItem(value: 'grass', child: Text('หญ้า')),
                        DropdownMenuItem(value: 'clay', child: Text('ดิน')),
                        DropdownMenuItem(value: 'hard', child: Text('แข็ง')),
                        DropdownMenuItem(value: 'wood', child: Text('ไม้')),
                      ],
                      onChanged: (v) => setState(() => _courtType = v),
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
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _valid
                      ? () => Navigator.pop(context, {
                          'name': _name.text.trim(),
                          'unit_label': _unitLabel.text.trim(),
                          'sport_id': _sportId,
                          'price_amount': double.tryParse(_price.text.trim()),
                          'pricing_unit': _pricingUnit,
                          'capacity': int.tryParse(_capacity.text.trim()) ?? 1,
                          'court_type': _courtType,
                          'indoor': _indoor,
                          'approval_mode': _approvalMode,
                          if (widget.court != null) 'id': widget.court!.id,
                        })
                      : null,
                  child: Text(editing ? 'บันทึก' : 'เพิ่มสนาม'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
