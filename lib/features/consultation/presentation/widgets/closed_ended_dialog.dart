import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../chat/data/models/closed_ended_config.dart';

/// Phase 6.14 — Expert dialog to define a closed-ended question's answers.
///
/// - เชิงปริมาณ: เลือกจำนวนระดับ 3 / 5 / 10
/// - เชิงคุณภาพ: กรอกตัวเลือก 2–10 ข้อ (เพิ่ม/ลบ/จัดลำดับได้)
///
/// Pops with a validated [ClosedEndedConfig]; cancel pops with null and does
/// not change input mode. Scrollable + keyboard-aware.
class ClosedEndedConfigDialog extends StatefulWidget {
  const ClosedEndedConfigDialog({super.key});

  /// Convenience helper — resolves with the config or null when cancelled.
  static Future<ClosedEndedConfig?> show(BuildContext context) {
    return showDialog<ClosedEndedConfig>(
      context: context,
      builder: (_) => const ClosedEndedConfigDialog(),
    );
  }

  @override
  State<ClosedEndedConfigDialog> createState() =>
      _ClosedEndedConfigDialogState();
}

class _ClosedEndedConfigDialogState extends State<ClosedEndedConfigDialog> {
  ClosedEndedType _type = ClosedEndedType.quantitative;
  int _scaleLevels = 5;
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  String? _errorText;

  @override
  void dispose() {
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= ClosedEndedConfig.maxOptions) return;
    setState(() {
      _optionControllers.add(TextEditingController());
      _errorText = null;
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= ClosedEndedConfig.minOptions) return;
    setState(() {
      _optionControllers.removeAt(index).dispose();
      _errorText = null;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      _optionControllers.insert(
        newIndex,
        _optionControllers.removeAt(oldIndex),
      );
    });
  }

  void _confirm() {
    final config = _type == ClosedEndedType.quantitative
        ? ClosedEndedConfig.quantitative(_scaleLevels)
        : ClosedEndedConfig.qualitative(
            _optionControllers.map((c) => c.text.trim()).toList(),
          );

    final error = config.validate();
    if (error != null) {
      setState(() => _errorText = _thaiError(error));
      return;
    }
    Navigator.of(context).pop(config);
  }

  String _thaiError(String error) {
    if (error.contains('empty')) {
      return 'กรุณากรอกตัวเลือกให้ครบทุกข้อ';
    }
    if (error.contains('duplicate')) {
      return 'ตัวเลือกห้ามซ้ำกัน';
    }
    if (error.contains('80')) {
      return 'ตัวเลือกยาวเกิน ${ClosedEndedConfig.maxLabelLength} ตัวอักษร';
    }
    return 'รูปแบบคำตอบไม่ถูกต้อง';
  }

  @override
  Widget build(BuildContext context) {
    // Dialog จัดการ keyboard inset ให้แล้ว (MediaQuery.viewInsetsOf + insetPadding)
    // จึงไม่ต้องเติม padding ตามความสูงแป้นพิมพ์ซ้ำ — ถ้าเติมซ้ำเนื้อหาจะถูกบีบและบัง
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      // แตะพื้นที่ว่างใน dialog เพื่อซ่อนแป้นพิมพ์ (TextField/ปุ่มยังจัดการแตะของตัวเอง)
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.deepPurple.shade50,
                    child: Icon(
                      Icons.checklist_rtl,
                      size: 28,
                      color: Colors.deepPurple.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'คำถามปลายปิด',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'ผู้ป่วยต้องเลือกคำตอบจากตัวเลือกที่กำหนด',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Answer type selector ──
              SegmentedButton<ClosedEndedType>(
                segments: const [
                  ButtonSegment(
                    value: ClosedEndedType.quantitative,
                    label: Text('เชิงปริมาณ'),
                    icon: Icon(Icons.format_list_numbered, size: 22),
                  ),
                  ButtonSegment(
                    value: ClosedEndedType.qualitative,
                    label: Text('เชิงคุณภาพ'),
                    icon: Icon(Icons.text_fields, size: 22),
                  ),
                ],
                showSelectedIcon: false,
                selected: {_type},
                onSelectionChanged: (selection) => setState(() {
                  _type = selection.first;
                  _errorText = null;
                }),
              ),
              const SizedBox(height: 16),

              if (_type == ClosedEndedType.quantitative) ...[
                const Text(
                  'จำนวนระดับคำตอบ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ClosedEndedConfig.allowedScaleLevels.map((n) {
                    final selected = _scaleLevels == n;
                    return ChoiceChip(
                      label: Text('1–$n'),
                      selected: selected,
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      onSelected: (_) => setState(() => _scaleLevels = n),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
                Text(
                  'ผู้ป่วยจะเห็นปุ่มตัวเลข 1 ถึง $_scaleLevels',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ตัวเลือกคำตอบ',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_optionControllers.length}/${ClosedEndedConfig.maxOptions}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _optionControllers.length,
                  onReorder: _reorder,
                  itemBuilder: (context, index) {
                    return Padding(
                      key: ObjectKey(_optionControllers[index]),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(
                              Icons.drag_indicator,
                              size: 20,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextField(
                              controller: _optionControllers[index],
                              maxLength: ClosedEndedConfig.maxLabelLength,
                              decoration: InputDecoration(
                                hintText: 'ตัวเลือกที่ ${index + 1}',
                                counterText: '',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onChanged: (_) {
                                if (_errorText != null) {
                                  setState(() => _errorText = null);
                                }
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            tooltip: 'ลบตัวเลือก',
                            onPressed:
                                _optionControllers.length >
                                    ClosedEndedConfig.minOptions
                                ? () => _removeOption(index)
                                : null,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed:
                        _optionControllers.length < ClosedEndedConfig.maxOptions
                        ? _addOption
                        : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('เพิ่มคำตอบ'),
                  ),
                ),
              ],

              if (_errorText != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorText!,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              ],
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('ยืนยัน'),
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
