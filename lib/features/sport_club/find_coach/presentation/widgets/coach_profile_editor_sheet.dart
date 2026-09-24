import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/coach_models.dart';

/// Coach profile draft returned by [CoachProfileEditorSheet.show].
typedef CoachProfileDraft =
    ({
      String displayName,
      String? bio,
      double? hourlyRate,
      String teachingMode,
    });

/// Onboarding/edit sheet for the caller's coach profile. New profiles are
/// submitted with status 'pending' and appear publicly only after admin
/// approval (enforced by `upsert_coach_profile`).
class CoachProfileEditorSheet {
  static Future<CoachProfileDraft?> show(
    BuildContext context, {
    CoachSummary? existing,
  }) {
    return showModalBottomSheet<CoachProfileDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) =>
          _CoachProfileEditorSheetBody(existing: existing),
    );
  }
}

class _CoachProfileEditorSheetBody extends StatefulWidget {
  final CoachSummary? existing;
  const _CoachProfileEditorSheetBody({this.existing});

  @override
  State<_CoachProfileEditorSheetBody> createState() =>
      _CoachProfileEditorSheetBodyState();
}

class _CoachProfileEditorSheetBodyState
    extends State<_CoachProfileEditorSheetBody> {
  late final _displayName = TextEditingController(
    text: widget.existing?.displayName ?? '',
  );
  late final _bio = TextEditingController(text: widget.existing?.bio ?? '');
  late final _rate = TextEditingController(
    text: widget.existing?.hourlyRate?.toStringAsFixed(0) ?? '',
  );
  late String _teachingMode = switch (widget.existing?.teachingMode) {
    TeachingMode.online => 'online',
    TeachingMode.both => 'both',
    _ => 'onsite',
  };

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _rate.dispose();
    super.dispose();
  }

  bool get _valid => _displayName.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
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
                isNew ? 'สมัครเป็นโค้ช' : 'แก้ไขโปรไฟล์โค้ช',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isNew
                    ? 'โปรไฟล์จะแสดงในหน้าค้นหาหลังทีมงานอนุมัติ'
                    : 'การแก้ไขไม่กระทบคำขอจองที่ยืนยันแล้ว',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _displayName,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'ชื่อที่แสดง *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bio,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'แนะนำตัว',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ค่าสอนต่อชั่วโมง (บาท)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'รูปแบบการสอน',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'onsite', label: Text('ออนไซต์')),
                  ButtonSegment(value: 'online', label: Text('ออนไลน์')),
                  ButtonSegment(value: 'both', label: Text('ทั้งสอง')),
                ],
                selected: {_teachingMode},
                onSelectionChanged: (sel) =>
                    setState(() => _teachingMode = sel.first),
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
                      ? () => Navigator.pop(context, (
                          displayName: _displayName.text.trim(),
                          bio: _bio.text.trim().isEmpty
                              ? null
                              : _bio.text.trim(),
                          hourlyRate: double.tryParse(_rate.text.trim()),
                          teachingMode: _teachingMode,
                        ))
                      : null,
                  child: Text(isNew ? 'สมัครเป็นโค้ช' : 'บันทึก'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
