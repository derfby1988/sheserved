import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../data/book_court_models.dart';

/// Editor for a [VenueEvidencePolicy] — shared by the venue-level card and
/// the per-court 'custom' override. Returns the edited policy, `null` when
/// dismissed, or [VenueEvidencePolicyDialog.disabled] sentinel semantics via
/// [PolicyEditResult.disable] when the owner turns the feature off.
///
/// Provider verification (`auto_verify`) is deliberately not editable here:
/// it requires the admin-authorised verify scope plus an enabled provider,
/// and is configured in the admin console instead.
class VenueEvidencePolicyDialog {
  /// Returned when the owner picks "ปิดใช้งาน" — the caller sends
  /// `p_policy = NULL` (venue) or `p_mode = 'off'` (court).
  static const disable = Object();

  static Future<Object?> show(
    BuildContext context, {
    VenueEvidencePolicy? initial,
    required bool canDisable,
    bool venueHasReleaseRule = false,

    /// `auto_verify` is offered only when the venue's admin-set verify
    /// scope is not 'disabled' AND at least one provider is enabled —
    /// even then the server re-validates (`VERIFY_NOT_ENABLED`).
    bool allowAutoVerify = false,
  }) {
    return GlassDialog.show<Object>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => _VenueEvidencePolicyDialogBody(
        initial: initial,
        canDisable: canDisable,
        venueHasReleaseRule: venueHasReleaseRule,
        allowAutoVerify: allowAutoVerify,
      ),
    );
  }
}

class _RequirementDraft {
  final TextEditingController key;
  final TextEditingController label;
  final TextEditingController note;
  String kind; // 'document' | 'payment_slip'
  String stage; // 'preapproval' | 'booking'
  String reviewMode; // 'owner_review' | 'auto_verify' (slips only)
  bool required;

  _RequirementDraft({
    required this.key,
    required this.label,
    required this.note,
    this.kind = 'document',
    this.stage = 'booking',
    this.reviewMode = 'owner_review',
    this.required = true,
  });

  factory _RequirementDraft.from(EvidenceRequirement r) => _RequirementDraft(
    key: TextEditingController(text: r.key),
    label: TextEditingController(text: r.label),
    note: TextEditingController(text: r.note ?? ''),
    kind: r.kind,
    stage: r.stage,
    reviewMode: r.reviewMode,
    required: r.required,
  );

  static _RequirementDraft blank(int index) => _RequirementDraft(
    key: TextEditingController(text: 'req_$index'),
    label: TextEditingController(),
    note: TextEditingController(),
  );

  void dispose() {
    key.dispose();
    label.dispose();
    note.dispose();
  }
}

class _VenueEvidencePolicyDialogBody extends StatefulWidget {
  final VenueEvidencePolicy? initial;
  final bool canDisable;

  /// Whether the venue (or, for a court override, its effective rule) has a
  /// recurring release configured — release-based deadline modes need it.
  final bool venueHasReleaseRule;

  /// Admin gate for the `auto_verify` review mode — never shown otherwise.
  final bool allowAutoVerify;

  const _VenueEvidencePolicyDialogBody({
    this.initial,
    required this.canDisable,
    required this.venueHasReleaseRule,
    required this.allowAutoVerify,
  });

  @override
  State<_VenueEvidencePolicyDialogBody> createState() =>
      _VenueEvidencePolicyDialogBodyState();
}

class _VenueEvidencePolicyDialogBodyState
    extends State<_VenueEvidencePolicyDialogBody> {
  late final List<_RequirementDraft> _requirements = [
    for (final r in widget.initial?.requirements ?? const <EvidenceRequirement>[])
      _RequirementDraft.from(r),
  ];
  late String _deadlineMode =
      widget.initial?.deadlineMode ?? 'per_booking';
  late final TextEditingController _minutes = TextEditingController(
    text: (widget.initial?.minutes ?? 60).toString(),
  );
  late TimeOfDay _deadlineTime = _parseTime(widget.initial?.deadlineTime);
  late bool _ownerApprovalDeadline =
      widget.initial?.ownerApprovalDeadlineEnabled ?? false;
  late final TextEditingController _grace = TextEditingController(
    text: (widget.initial?.minGraceMinutes ?? 0).toString(),
  );
  late final TextEditingController _decisionMinutes =
      TextEditingController(
    text: (widget.initial?.ownerDecisionMinutes ?? 1440).toString(),
  );
  late final TextEditingController _maxHolds = TextEditingController(
    text: (widget.initial?.maxHoldsPerUser ?? 5).toString(),
  );
  late final TextEditingController _destination = TextEditingController(
    text: widget.initial?.paymentDestination ?? '',
  );

  static TimeOfDay _parseTime(String? hhmm) {
    final parts = (hhmm ?? '23:59').split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 23,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 59 : 59,
    );
  }

  @override
  void dispose() {
    for (final r in _requirements) {
      r.dispose();
    }
    _minutes.dispose();
    _grace.dispose();
    _decisionMinutes.dispose();
    _maxHolds.dispose();
    _destination.dispose();
    super.dispose();
  }

  /// Mirrors `sports_venue_evidence_requirements_valid` so obvious shape
  /// problems are caught before the RPC round-trip.
  String? get _validationError {
    if (_requirements.isEmpty || _requirements.length > 10) {
      return 'กำหนดหลักฐาน 1–10 รายการ';
    }
    final keys = <String>{};
    var anyRequired = false;
    for (final r in _requirements) {
      final key = r.key.text.trim();
      final label = r.label.text.trim();
      if (key.isEmpty || key.length > 40 || label.isEmpty || label.length > 60) {
        return 'กรุณากรอก key (≤40 ตัว) และชื่อหลักฐาน (≤60 ตัว) ให้ครบ';
      }
      if (!RegExp(r'^[a-z0-9_\-]+$').hasMatch(key)) {
        return 'key ใช้ได้เฉพาะตัวพิมพ์เล็ก ตัวเลข _ และ -';
      }
      if (!keys.add(key)) return 'key "$key" ซ้ำกัน';
      // Server rule: payment slips always live in the payment stage.
      if (r.kind == 'payment_slip' && r.stage != 'payment') {
        return 'สลิปชำระเงินต้องอยู่ขั้นชำระเงิน';
      }
      if (r.required) anyRequired = true;
    }
    if (!anyRequired) return 'ต้องมีหลักฐานที่บังคับอย่างน้อย 1 รายการ';

    if (_deadlineMode == 'release_day_time') {
      if (!widget.venueHasReleaseRule) {
        return 'โหมดตามเวลาวันเปิดรอบต้องตั้งรอบเปิดรับจองของสถานที่ก่อน';
      }
    } else {
      final minutes = int.tryParse(_minutes.text.trim());
      if (minutes == null || minutes < 1 || minutes > 43200) {
        return 'เวลาส่งหลักฐานต้องเป็น 1–43200 นาที';
      }
    }
    final grace = int.tryParse(_grace.text.trim());
    if (grace == null || grace < 0 || grace > 10080) {
      return 'ช่วงผ่อนผันต้องเป็น 0–10080 นาที';
    }
    final decision = int.tryParse(_decisionMinutes.text.trim());
    if (decision == null || decision < 1 || decision > 43200) {
      return 'เวลาตัดสินของเจ้าของต้องเป็น 1–43200 นาที';
    }
    final holds = int.tryParse(_maxHolds.text.trim());
    if (holds == null || holds < 1 || holds > 100) {
      return 'จำนวน hold สูงสุดต่อผู้ใช้ต้องเป็น 1–100';
    }
    final needsSlip = _requirements.any(
      (r) => r.kind == 'payment_slip' && r.required,
    );
    if (needsSlip && _destination.text.trim().isEmpty) {
      return 'กรุณาระบุช่องทางรับชำระเงินสำหรับสลิป';
    }
    return null;
  }

  bool get _valid => _validationError == null;

  VenueEvidencePolicy get _policy => VenueEvidencePolicy(
    requirements: [
      for (final r in _requirements)
        EvidenceRequirement(
          key: r.key.text.trim(),
          label: r.label.text.trim(),
          kind: r.kind,
          // Slips are forced to the payment stage server-side; documents
          // keep their chosen stage.
          stage: r.kind == 'payment_slip' ? 'payment' : r.stage,
          reviewMode: r.reviewMode,
          required: r.required,
          note: r.note.text.trim().isEmpty ? null : r.note.text.trim(),
        ),
    ],
    deadlineMode: _deadlineMode,
    minutes: _deadlineMode == 'release_day_time'
        ? null
        : int.tryParse(_minutes.text.trim()),
    deadlineTime: _deadlineMode == 'release_day_time'
        ? '${_deadlineTime.hour.toString().padLeft(2, '0')}:${_deadlineTime.minute.toString().padLeft(2, '0')}'
        : null,
    ownerApprovalDeadlineEnabled: _ownerApprovalDeadline,
    minGraceMinutes: int.tryParse(_grace.text.trim()) ?? 0,
    ownerDecisionMinutes: int.tryParse(_decisionMinutes.text.trim()) ?? 1440,
    maxHoldsPerUser: int.tryParse(_maxHolds.text.trim()) ?? 5,
    paymentDestination: _destination.text.trim().isEmpty
        ? null
        : _destination.text.trim(),
  );

  void _addRequirement() {
    if (_requirements.length >= 10) return;
    setState(() {
      _requirements.add(_RequirementDraft.blank(_requirements.length + 1));
    });
  }

  void _removeRequirement(int index) {
    final draft = _requirements.removeAt(index);
    draft.dispose();
    setState(() {});
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDeadlineTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _deadlineTime,
    );
    if (picked != null && mounted) {
      setState(() => _deadlineTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _validationError;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 440,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'หลักฐานการจอง',
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
              child: LitGlassSurface.frosted(
                borderRadius: 14,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'รายการหลักฐาน',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      for (var i = 0; i < _requirements.length; i++)
                        _requirementCard(i),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _requirements.length >= 10
                              ? null
                              : _addRequirement,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('เพิ่มหลักฐาน'),
                        ),
                      ),
                      const Divider(height: 20),
                      const Text(
                        'กำหนดเวลาส่งหลักฐาน',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _deadlineMode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'นับเวลาจาก',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'per_booking',
                            child: Text('นับจากเวลาจอง (ต่อรายการ)'),
                          ),
                          DropdownMenuItem(
                            value: 'after_release',
                            child: Text('นับจากเวลาเปิดรอบจอง'),
                          ),
                          DropdownMenuItem(
                            value: 'release_day_time',
                            child: Text('เวลาคงที่ของวันเปิดรอบ'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _deadlineMode = v);
                          }
                        },
                      ),
                      if (_deadlineMode != 'release_day_time')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextField(
                            controller: _minutes,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'ภายใน (นาที)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton(
                            onPressed: _pickDeadlineTime,
                            child: Text(
                              'กำหนดส่งภายใน ${_fmtTime(_deadlineTime)} '
                              'ของวันเปิดรอบ',
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text(
                          'กำหนดเวลาอนุมัติเบื้องต้นของเจ้าของ',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          'สำหรับรายการแบบรออนุมัติ — หมดเวลาก่อนตอบจะหมดอายุ',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        value: _ownerApprovalDeadline,
                        onChanged: (v) =>
                            setState(() => _ownerApprovalDeadline = v),
                      ),
                      TextField(
                        controller: _grace,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'ผ่อนผันหลังหมดเวลา (นาที)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _decisionMinutes,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'เจ้าของต้องตัดสินภายใน (นาที)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _maxHolds,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'จำนวนการจองค้างหลักฐานสูงสุด/ผู้ใช้',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _destination,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          counterText: '',
                          labelText: 'ช่องทางรับชำระเงิน',
                          hintText: 'เช่น พร้อมเพย์ 081-xxx / บัญชีธนาคาร',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            error,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.canDisable)
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(VenueEvidencePolicyDialog.disable),
                    child: Text(
                      'ปิดใช้งาน',
                      style: TextStyle(color: Colors.red.shade300),
                    ),
                  ),
                const Spacer(),
                GlassActionButton(
                  label: 'ยกเลิก',
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GlassActionButton(
                    label: 'บันทึก',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: _valid
                        ? () => Navigator.of(context).pop(_policy)
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

  Widget _requirementCard(int index) {
    final r = _requirements[index];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: r.key,
                  decoration: const InputDecoration(
                    labelText: 'key (อังกฤษ)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: r.label,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อที่แสดง *',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'ลบรายการ',
                onPressed: () => _removeRequirement(index),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: r.kind,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'ประเภท',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'document',
                      child: Text('เอกสารทั่วไป'),
                    ),
                    DropdownMenuItem(
                      value: 'payment_slip',
                      child: Text('สลิปชำระเงิน'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      r.kind = v;
                      // Server rule: slips always sit in the payment stage.
                      r.stage = v == 'payment_slip' ? 'payment' : 'booking';
                      r.reviewMode = 'owner_review';
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: r.kind == 'payment_slip'
                    ? const InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'ขั้นตอน',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        child: Text('ชำระเงิน'),
                      )
                    : DropdownButtonFormField<String>(
                        initialValue: r.stage,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'ขั้นตอน',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'preapproval',
                            child: Text('ก่อนอนุมัติ'),
                          ),
                          DropdownMenuItem(
                            value: 'booking',
                            child: Text('หลังจอง'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => r.stage = v);
                        },
                      ),
              ),
            ],
          ),
          if (r.kind == 'payment_slip')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DropdownButtonFormField<String>(
                initialValue: r.reviewMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'วิธีตรวจสลิป',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'owner_review',
                    child: Text('เจ้าของตรวจเอง'),
                  ),
                  if (widget.allowAutoVerify)
                    const DropdownMenuItem(
                      value: 'auto_verify',
                      child: Text('ตรวจอัตโนมัติ'),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => r.reviewMode = v);
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DropdownButtonFormField<String>(
                initialValue: r.reviewMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'วิธีตรวจเอกสาร',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'owner_review',
                    child: Text('เจ้าของตรวจเอง'),
                  ),
                  DropdownMenuItem(
                    value: 'auto',
                    child: Text('อนุมัติอัตโนมัติเมื่อครบกำหนด'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => r.reviewMode = v);
                },
              ),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('บังคับส่ง', style: TextStyle(fontSize: 13)),
            value: r.required,
            onChanged: (v) => setState(() => r.required = v ?? true),
          ),
          TextField(
            controller: r.note,
            decoration: const InputDecoration(
              labelText: 'หมายเหตุถึงผู้จอง (ไม่บังคับ)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
