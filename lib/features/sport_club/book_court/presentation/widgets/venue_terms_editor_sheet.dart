import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

/// Owner editor for venue usage terms. Publishing always creates a new
/// active version (older versions stay for existing booking snapshots), so
/// this sheet only submits a draft — the caller runs `publish_sports_venue_terms`
/// and shows the returned version.
class VenueTermsEditorSheet {
  static Future<({String text, int cutoffMinutes})?> show(
    BuildContext context, {
    String? currentText,
    int? currentCutoffMinutes,
  }) {
    return showModalBottomSheet<({String text, int cutoffMinutes})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _VenueTermsEditorSheetBody(
        currentText: currentText,
        currentCutoffMinutes: currentCutoffMinutes,
      ),
    );
  }
}

class _VenueTermsEditorSheetBody extends StatefulWidget {
  final String? currentText;
  final int? currentCutoffMinutes;

  const _VenueTermsEditorSheetBody({
    this.currentText,
    this.currentCutoffMinutes,
  });

  @override
  State<_VenueTermsEditorSheetBody> createState() =>
      _VenueTermsEditorSheetBodyState();
}

class _VenueTermsEditorSheetBodyState
    extends State<_VenueTermsEditorSheetBody> {
  late final _terms = TextEditingController(text: widget.currentText ?? '');
  late final _cutoff = TextEditingController(
    text: (widget.currentCutoffMinutes ?? 60).toString(),
  );

  @override
  void dispose() {
    _terms.dispose();
    _cutoff.dispose();
    super.dispose();
  }

  /// Cutoff must be an explicit non-negative integer — a malformed or
  /// empty value blocks submission instead of silently falling back.
  int? get _cutoffValue {
    final raw = _cutoff.text.trim();
    if (raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  bool get _valid => _terms.text.trim().isNotEmpty && _cutoffValue != null;

  void _submit() {
    final cutoff = _cutoffValue;
    if (!_valid || cutoff == null) return;
    Navigator.pop(context, (text: _terms.text.trim(), cutoffMinutes: cutoff));
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
                'เงื่อนไขการใช้สนาม',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'การบันทึกจะเผยแพร่เวอร์ชันใหม่ — ผู้จองต้องยอมรับเวอร์ชันล่าสุดก่อนจอง',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _terms,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'เงื่อนไขการใช้สนาม',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cutoff,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'ยกเลิกล่วงหน้าได้ไม่เกิน (นาที)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_cutoff.text.trim().isNotEmpty && _cutoffValue == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'กรุณากรอกจำนวนนาทีเป็นตัวเลขจำนวนเต็มที่ไม่ติดลบ',
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
                  child: const Text('เผยแพร่เวอร์ชันใหม่'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
