import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

/// Owner editor for a venue's sport set. Multi-selects from the approved
/// sports catalog and captures an optional `unit_label_override` per sport.
/// Returns the `p_sports` list for `set_sports_venue_sports`:
/// `[{sport_id, unit_label_override}]`.
class VenueSportsEditorSheet {
  static Future<List<Map<String, dynamic>>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> sports,
    required Map<String, String> selectedUnits,
  }) {
    return showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _VenueSportsEditorSheetBody(
        sports: sports,
        selectedUnits: selectedUnits,
      ),
    );
  }
}

class _VenueSportsEditorSheetBody extends StatefulWidget {
  final List<Map<String, dynamic>> sports;
  final Map<String, String> selectedUnits;

  const _VenueSportsEditorSheetBody({
    required this.sports,
    required this.selectedUnits,
  });

  @override
  State<_VenueSportsEditorSheetBody> createState() =>
      _VenueSportsEditorSheetBodyState();
}

class _VenueSportsEditorSheetBodyState
    extends State<_VenueSportsEditorSheetBody> {
  late final Map<String, String> _selected = Map.of(widget.selectedUnits);
  final Map<String, TextEditingController> _unitControllers = {};

  @override
  void initState() {
    super.initState();
    for (final entry in _selected.entries) {
      _unitControllers[entry.key] = TextEditingController(text: entry.value);
    }
  }

  @override
  void dispose() {
    for (final controller in _unitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _sportName(Map<String, dynamic> sport) =>
      sport['name_th']?.toString() ??
      sport['name_en']?.toString() ??
      sport['id']?.toString() ??
      '';

  void _toggle(String sportId, bool selected) {
    setState(() {
      if (selected) {
        _selected[sportId] = _unitControllers[sportId]?.text ?? '';
        _unitControllers.putIfAbsent(sportId, () => TextEditingController());
      } else {
        _selected.remove(sportId);
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
    Navigator.pop(context, draft);
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
                'กีฬาของสนาม',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'เลือกกีฬาที่สนามเปิดให้จอง และกำหนดหน่วยนับได้ตามต้องการ',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              for (final sport in widget.sports)
                _SportRow(
                  name: _sportName(sport),
                  selected: _selected.containsKey(sport['id']?.toString()),
                  unitController:
                      _unitControllers[sport['id']?.toString() ?? ''],
                  onChanged: (value) =>
                      _toggle(sport['id']?.toString() ?? '', value),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                  ),
                  onPressed: _selected.isEmpty ? null : _submit,
                  child: const Text('บันทึก'),
                ),
              ),
            ],
          ),
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
                labelText: 'หน่วยนับ (เช่น คอร์ท, โต๊ะ)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
      ],
    );
  }
}
