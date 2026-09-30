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
  final ClosedEndedConfig? initialConfig;
  final Future<List<String>>? recentOptionsFuture;

  const ClosedEndedConfigDialog({
    super.key,
    this.initialConfig,
    this.recentOptionsFuture,
  });

  /// Convenience helper — resolves with the config or null when cancelled.
  static Future<ClosedEndedConfig?> show(
    BuildContext context, {
    ClosedEndedConfig? initialConfig,
    Future<List<String>>? recentOptionsFuture,
  }) {
    return showDialog<ClosedEndedConfig>(
      context: context,
      builder: (_) => ClosedEndedConfigDialog(
        initialConfig: initialConfig,
        recentOptionsFuture: recentOptionsFuture,
      ),
    );
  }

  @override
  State<ClosedEndedConfigDialog> createState() =>
      _ClosedEndedConfigDialogState();
}

class _ClosedEndedConfigDialogState extends State<ClosedEndedConfigDialog> {
  ClosedEndedType _type = ClosedEndedType.quantitative;
  int _scaleLevels = 5;
  final List<TextEditingController> _optionControllers = [];
  String? _errorText;
  final ScrollController _optionsScrollController = ScrollController();
  List<String> _recentOptions = const [];

  @override
  void initState() {
    super.initState();
    final initialConfig = widget.initialConfig;
    if (initialConfig != null) {
      _type = initialConfig.type;
      _scaleLevels = initialConfig.scaleLevels ?? _scaleLevels;
      _optionControllers.addAll(
        (initialConfig.options ?? const <String>[]).map(
          (option) => TextEditingController(text: option),
        ),
      );
    }
    while (_optionControllers.length < ClosedEndedConfig.minOptions) {
      _optionControllers.add(TextEditingController());
    }
    _loadRecentOptions();
  }

  Future<void> _loadRecentOptions() async {
    final recentOptionsFuture = widget.recentOptionsFuture;
    if (recentOptionsFuture == null) return;
    try {
      final recentOptions = await recentOptionsFuture;
      if (!mounted) return;
      setState(() => _recentOptions = recentOptions);
    } catch (_) {}
  }

  String _normalizeOption(String value) => value.trim().toLowerCase();

  List<String> get _visibleRecentOptions {
    final currentOptions = _optionControllers
        .map((controller) => _normalizeOption(controller.text))
        .where((option) => option.isNotEmpty)
        .toSet();
    final seen = <String>{};
    return _recentOptions
        .map((option) => option.trim())
        .where((option) {
          final normalized = _normalizeOption(option);
          return normalized.isNotEmpty &&
              !currentOptions.contains(normalized) &&
              seen.add(normalized);
        })
        .take(5)
        .toList();
  }

  @override
  void dispose() {
    for (final c in _optionControllers) {
      c.dispose();
    }
    _optionsScrollController.dispose();
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= ClosedEndedConfig.maxOptions) return;
    setState(() {
      _optionControllers.add(TextEditingController());
      _errorText = null;
    });
  }

  void _useRecentOption(String option) {
    final normalized = _normalizeOption(option);
    if (_optionControllers.any(
      (controller) => _normalizeOption(controller.text) == normalized,
    )) {
      return;
    }

    final emptyIndex = _optionControllers.indexWhere(
      (controller) => controller.text.trim().isEmpty,
    );
    if (emptyIndex == -1 &&
        _optionControllers.length >= ClosedEndedConfig.maxOptions) {
      setState(
        () => _errorText =
            'เพิ่มคำตอบได้สูงสุด ${ClosedEndedConfig.maxOptions} ข้อ',
      );
      return;
    }

    setState(() {
      if (emptyIndex == -1) {
        _optionControllers.add(TextEditingController(text: option));
      } else {
        _optionControllers[emptyIndex].value = TextEditingValue(
          text: option,
          selection: TextSelection.collapsed(offset: option.length),
        );
      }
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

  Widget _buildOptionsFooter() {
    final visibleRecentOptions = _visibleRecentOptions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _optionControllers.length < ClosedEndedConfig.maxOptions
                ? _addOption
                : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('เพิ่มคำตอบ'),
          ),
        ),
        if (visibleRecentOptions.isNotEmpty) ...[
          const SizedBox(height: 4),
          const Text(
            'ตัวเลือกที่ใช้ล่าสุด',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: visibleRecentOptions.map((option) {
              return ActionChip(
                key: ValueKey(
                  'closed-ended-recent-option-${_normalizeOption(option)}',
                ),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: Text(
                    option,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onPressed: () => _useRecentOption(option),
              );
            }).toList(),
          ),
        ],
      ],
    );
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
    final mediaQuery = MediaQuery.of(context);
    final maxDialogHeight =
        (mediaQuery.size.height - mediaQuery.viewInsets.bottom - 48)
            .clamp(0.0, mediaQuery.size.height)
            .toDouble();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      // แตะพื้นที่ว่างใน dialog เพื่อซ่อนแป้นพิมพ์ (TextField/ปุ่มยังจัดการแตะของตัวเอง)
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxDialogHeight),
          child: Padding(
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
                        selectedColor: AppColors.primary.withValues(
                          alpha: 0.15,
                        ),
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Scrollbar(
                      key: const ValueKey('closed-ended-option-scrollbar'),
                      controller: _optionsScrollController,
                      thumbVisibility: true,
                      child: ReorderableListView.builder(
                        key: const ValueKey('closed-ended-option-fields-list'),
                        scrollController: _optionsScrollController,
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: _optionControllers.length,
                        onReorder: _reorder,
                        footer: _buildOptionsFooter(),
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
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onChanged: (_) =>
                                        setState(() => _errorText = null),
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
      ),
    );
  }
}
