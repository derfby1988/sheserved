import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

/// Owner editor dialog for a venue's sport set. Multi-selects from the
/// approved sports catalog and captures an optional `unit_label_override`
/// per sport (resource-level, e.g. "คอร์ท", "โต๊ะ"), plus the venue's
/// unit-label reference sport (Phase 21.7.19). Returns
/// `{'sports': [{sport_id, unit_label_override}], 'referenceSportId': …}`
/// for `set_sports_venue_sports` / `set_sports_venue_unit_label`.
class VenueSportsEditorDialog {
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> sports,
    required Map<String, String> selectedUnits,
    required Map<String, String> venueUnitSuggestions,
    String? referenceSportId,
  }) {
    return GlassDialog.show<Map<String, dynamic>>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => _VenueSportsEditorDialogBody(
        sports: sports,
        selectedUnits: selectedUnits,
        venueUnitSuggestions: venueUnitSuggestions,
        referenceSportId: referenceSportId,
      ),
    );
  }
}

class _VenueSportsEditorDialogBody extends StatefulWidget {
  final List<Map<String, dynamic>> sports;
  final Map<String, String> selectedUnits;

  /// sport_id → suggested venue label from the th catalog (missing → สนาม).
  final Map<String, String> venueUnitSuggestions;
  final String? referenceSportId;

  const _VenueSportsEditorDialogBody({
    required this.sports,
    required this.selectedUnits,
    required this.venueUnitSuggestions,
    this.referenceSportId,
  });

  @override
  State<_VenueSportsEditorDialogBody> createState() =>
      _VenueSportsEditorDialogBodyState();
}

class _VenueSportsEditorDialogBodyState
    extends State<_VenueSportsEditorDialogBody> {
  static const _generic = 'สนาม';

  late final Map<String, String> _selected = Map.of(widget.selectedUnits);
  final Map<String, TextEditingController> _unitControllers = {};
  final ScrollController _scrollController = ScrollController();
  late String? _reference = _initialReference();

  @override
  void initState() {
    super.initState();
    for (final entry in _selected.entries) {
      _unitControllers[entry.key] = TextEditingController(text: entry.value);
    }
  }

  String? _initialReference() {
    final current = widget.referenceSportId;
    if (current != null && _selected.containsKey(current)) return current;
    if (_selected.length == 1) return _selected.keys.first;
    return null;
  }

  @override
  void dispose() {
    for (final controller in _unitControllers.values) {
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  String _sportName(Map<String, dynamic> sport) =>
      sport['name_th']?.toString() ??
      sport['name_en']?.toString() ??
      sport['id']?.toString() ??
      '';

  String _sportNameById(String sportId) {
    for (final sport in widget.sports) {
      if (sport['id']?.toString() == sportId) return _sportName(sport);
    }
    return sportId;
  }

  void _toggle(String sportId, bool selected) {
    setState(() {
      if (selected) {
        _selected[sportId] = _unitControllers[sportId]?.text ?? '';
        _unitControllers.putIfAbsent(sportId, () => TextEditingController());
      } else {
        _selected.remove(sportId);
        // The reference sport must stay a member — dropping it here mirrors
        // the server's auto-clear.
        if (_reference == sportId) _reference = null;
      }
    });
  }

  void _submit() {
    final draft = <Map<String, dynamic>>[
      for (final sportId in _selected.keys)
        {
          'sport_id': sportId,
          'unit_label_override': _unitControllers[sportId]?.text.trim() ?? '',
        },
    ];
    Navigator.pop(context, {
      'sports': draft,
      'referenceSportId': _reference,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'กีฬาของสถานที่',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'เลือกกีฬาที่สถานที่เปิดให้จอง และกำหนดหน่วยนับได้ตามต้องการ',
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
                  child: ListView(
                    controller: _scrollController,
                    shrinkWrap: true,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    children: [
                      for (final sport in widget.sports)
                        _SportRow(
                          name: _sportName(sport),
                          selected:
                              _selected.containsKey(sport['id']?.toString()),
                          unitController:
                              _unitControllers[sport['id']?.toString() ?? ''],
                          onChanged: (value) =>
                              _toggle(sport['id']?.toString() ?? '', value),
                        ),
                      const SizedBox(height: 4),
                      const Divider(height: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'กีฬาอ้างอิงชื่อสถานที่',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ใช้กำหนดว่าเรียกสถานที่นี้ว่าอะไร '
                              '(เช่น สนาม, ยิม, สตูดิโอ) เมื่อเจ้าของไม่ได้ตั้งเอง',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String?>(
                              key: const ValueKey('venue-label-reference'),
                              isExpanded: true,
                              initialValue: _reference,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('ไม่เลือก — ใช้คำกลาง "สนาม"'),
                                ),
                                for (final sportId in _selected.keys)
                                  DropdownMenuItem<String?>(
                                    value: sportId,
                                    child: Text(
                                      '${_sportNameById(sportId)} → '
                                      '${widget.venueUnitSuggestions[sportId] ?? _generic}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _reference = v),
                            ),
                          ],
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
                    onTap: _selected.isEmpty ? null : _submit,
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

class _SportRow extends StatelessWidget {
  final String name;
  final bool selected;
  final TextEditingController? unitController;
  final ValueChanged<bool> onChanged;

  const _SportRow({
    required this.name,
    required this.selected,
    required this.unitController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(name),
          value: selected,
          onChanged: (value) => onChanged(value == true),
        ),
        if (selected && unitController != null)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 8),
            child: TextField(
              controller: unitController,
              maxLength: 20,
              decoration: const InputDecoration(
                isDense: true,
                counterText: '',
                labelText: 'หน่วยที่จองได้ของกีฬานี้ (เช่น คอร์ท, โต๊ะ)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
      ],
    );
  }
}
