import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

/// Owner editor for the venue-level unit label (Phase 21.7.19). Two modes:
/// "ตามประเภทกีฬา" resolves the label from the reference sport's catalog row
/// (generic สนาม when nothing is selected) and "กำหนดเอง" stores a 1–40 char
/// override. Returns `({override, referenceSportId})` — both are written
/// verbatim by `set_sports_venue_unit_label`.
class VenueUnitLabelEditorDialog {
  static Future<({String? override, String? referenceSportId})?> show(
    BuildContext context, {
    required Map<String, String> sports,
    required Map<String, String> suggestions,
    String? currentOverride,
    String? currentReferenceSportId,
  }) {
    return GlassDialog.show<({String? override, String? referenceSportId})>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => _VenueUnitLabelEditorDialogBody(
        sports: sports,
        suggestions: suggestions,
        currentOverride: currentOverride,
        currentReferenceSportId: currentReferenceSportId,
      ),
    );
  }
}

class _VenueUnitLabelEditorDialogBody extends StatefulWidget {
  /// sport_id → display name for the venue's sports.
  final Map<String, String> sports;

  /// sport_id → suggested venue label from the th catalog (missing → สนาม).
  final Map<String, String> suggestions;
  final String? currentOverride;
  final String? currentReferenceSportId;

  const _VenueUnitLabelEditorDialogBody({
    required this.sports,
    required this.suggestions,
    this.currentOverride,
    this.currentReferenceSportId,
  });

  @override
  State<_VenueUnitLabelEditorDialogBody> createState() =>
      _VenueUnitLabelEditorDialogBodyState();
}

class _VenueUnitLabelEditorDialogBodyState
    extends State<_VenueUnitLabelEditorDialogBody> {
  static const _generic = 'สนาม';

  late bool _custom = widget.currentOverride != null;
  late final _text = TextEditingController(text: widget.currentOverride ?? '');
  late String? _reference = _initialReference();
  final ScrollController _scrollController = ScrollController();

  String? _initialReference() {
    final current = widget.currentReferenceSportId;
    if (current != null && widget.sports.containsKey(current)) return current;
    if (widget.sports.length == 1) return widget.sports.keys.first;
    return null;
  }

  @override
  void dispose() {
    _text.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Preview of the label that will resolve once saved.
  String get _preview {
    if (_custom) {
      final text = _text.text.trim();
      return text.isEmpty ? '—' : text;
    }
    if (_reference == null) return _generic;
    return widget.suggestions[_reference] ?? _generic;
  }

  bool get _valid =>
      !_custom ||
      (_text.text.trim().isNotEmpty && _text.text.trim().length <= 40);

  void _submit() {
    if (!_valid) return;
    Navigator.pop(context, (
      override: _custom ? _text.text.trim() : null,
      referenceSportId: _reference,
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
                        'เรียกสถานที่นี้ว่า',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'คำที่ผู้ใช้เห็นสำหรับสถานที่ เช่น สนาม, ยิม, ฟิตเนส, สตูดิโอ',
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
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('ตามประเภทกีฬา'),
                            ),
                            ButtonSegment(value: true, label: Text('กำหนดเอง')),
                          ],
                          selected: {_custom},
                          onSelectionChanged: (s) =>
                              setState(() => _custom = s.first),
                        ),
                        const SizedBox(height: 12),
                        if (!_custom) ...[
                          DropdownButtonFormField<String?>(
                            key: const ValueKey('venue-label-reference'),
                            isExpanded: true,
                            initialValue: _reference,
                            decoration: const InputDecoration(
                              labelText: 'กีฬาอ้างอิง',
                              helperText: 'ชื่อสถานที่จะตามกีฬาที่เลือก',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('ไม่เลือก — ใช้คำกลาง "สนาม"'),
                              ),
                              for (final entry in widget.sports.entries)
                                DropdownMenuItem<String?>(
                                  value: entry.key,
                                  child: Text(
                                    '${entry.value} → '
                                    '${widget.suggestions[entry.key] ?? _generic}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() => _reference = v),
                          ),
                          if (widget.sports.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'ยังไม่มีกีฬา — จะใช้คำกลาง "$_generic" '
                                'จนกว่าจะตั้งค่ากีฬา',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                        ] else ...[
                          TextField(
                            key: const ValueKey('venue-label-custom'),
                            controller: _text,
                            maxLength: 40,
                            decoration: const InputDecoration(
                              counterText: '',
                              labelText: 'ชื่อเรียกสถานที่',
                              hintText: 'เช่น สนาม, ยิม, ฟิตเนส, สตูดิโอ, ห้อง',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'ตัวอย่างที่ผู้ใช้จะเห็น: "$_preview"',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
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
                    label: 'บันทึก',
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
