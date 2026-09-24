import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../domain/find_coach_filter.dart';

/// Advanced filter sheet for Find Coach: skill level, max rate, teaching
/// mode, specialties, verified/available toggles. Returns the applied
/// [FindCoachFilter] or null when cancelled.
class CoachFilterSheet {
  static const skillLevels = <String, String>{
    'beginner': 'เริ่มต้น',
    'intermediate': 'ระดับกลาง',
    'advanced': 'ขั้นสูง',
    'pro': 'อาชีพ',
  };

  static Future<FindCoachFilter?> show(
    BuildContext context, {
    required FindCoachFilter current,
    List<String> specialtyOptions = const [],
  }) {
    return showModalBottomSheet<FindCoachFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _CoachFilterSheetBody(
        current: current,
        specialtyOptions: specialtyOptions,
      ),
    );
  }
}

class _CoachFilterSheetBody extends StatefulWidget {
  final FindCoachFilter current;
  final List<String> specialtyOptions;

  const _CoachFilterSheetBody({
    required this.current,
    required this.specialtyOptions,
  });

  @override
  State<_CoachFilterSheetBody> createState() => _CoachFilterSheetBodyState();
}

class _CoachFilterSheetBodyState extends State<_CoachFilterSheetBody> {
  late String? _skillLevel = widget.current.skillLevel;
  late final _maxRate = TextEditingController(
    text: widget.current.maxHourlyRate?.toStringAsFixed(0) ?? '',
  );
  late String? _teachingMode = widget.current.teachingMode;
  late bool _verifiedOnly = widget.current.verifiedOnly;
  late bool _availableOnly = widget.current.availableOnly;
  late List<String> _specialties = [...widget.current.specialties];
  final _specialtyController = TextEditingController();

  @override
  void dispose() {
    _maxRate.dispose();
    _specialtyController.dispose();
    super.dispose();
  }

  void _addSpecialty([String? value]) {
    final label = (value ?? _specialtyController.text).trim();
    if (label.isEmpty || _specialties.contains(label)) return;
    _specialtyController.clear();
    setState(() => _specialties.add(label));
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
              const Text(
                'ตัวกรองโค้ช',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),

              const Text(
                'ระดับผู้เล่น',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in CoachFilterSheet.skillLevels.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _skillLevel == entry.key,
                      onSelected: (sel) => setState(
                        () => _skillLevel = sel ? entry.key : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              const Text(
                'รูปแบบการสอน',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final (mode, label) in [
                    ('onsite', 'ออนไซต์'),
                    ('online', 'ออนไลน์'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _teachingMode == mode,
                      onSelected: (sel) => setState(
                        () => _teachingMode = sel ? mode : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _maxRate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ราคาต่อชั่วโมงสูงสุด (บาท)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('เฉพาะโค้ชที่ยืนยันตัวตน'),
                value: _verifiedOnly,
                onChanged: (v) => setState(() => _verifiedOnly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('มีตารางว่าง'),
                value: _availableOnly,
                onChanged: (v) => setState(() => _availableOnly = v),
              ),
              const SizedBox(height: 8),

              const Text(
                'ความเชี่ยวชาญ',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final spec in _specialties)
                    InputChip(
                      label: Text(spec),
                      onDeleted: () =>
                          setState(() => _specialties.remove(spec)),
                    ),
                ],
              ),
              if (widget.specialtyOptions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final spec in widget.specialtyOptions)
                      FilterChip(
                        label: Text(spec),
                        selected: _specialties.contains(spec),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _specialties.add(spec);
                          } else {
                            _specialties.remove(spec);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _specialtyController,
                      decoration: const InputDecoration(
                        hintText: 'เช่น วิ่ง, สมาธิ, ฟื้นฟู',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: _addSpecialty,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _addSpecialty,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    tooltip: 'เพิ่มความเชี่ยวชาญ',
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _skillLevel = null;
                      _teachingMode = null;
                      _maxRate.clear();
                      _verifiedOnly = false;
                      _availableOnly = false;
                      _specialties = [];
                    }),
                    child: const Text('ล้างทั้งหมด'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                    ),
                    onPressed: () => Navigator.pop(
                      context,
                      FindCoachFilter(
                        skillLevel: _skillLevel,
                        specialties: _specialties,
                        maxHourlyRate: double.tryParse(_maxRate.text.trim()),
                        verifiedOnly: _verifiedOnly,
                        availableOnly: _availableOnly,
                        teachingMode: _teachingMode,
                      ),
                    ),
                    child: const Text('ใช้ตัวกรอง'),
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
