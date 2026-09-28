import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';
import 'package:uuid/uuid.dart';

import '../../../data/coach_models.dart';
import '../coach_labels.dart';

/// Profile draft returned by [CoachProfileEditorDialog.show].
typedef CoachProfileDialogDraft =
    ({
      String displayName,
      String? bio,
      String? experience,
      double? hourlyRate,
      String teachingMode,
      bool acceptingStudents,
    });

/// Coach profile editor — GlassDialog with the general-information
/// section of the profile (name, bio, experience, rate, teaching mode).
class CoachProfileEditorDialog extends StatefulWidget {
  final CoachSummary? existing;

  const CoachProfileEditorDialog({super.key, this.existing});

  static Future<CoachProfileDialogDraft?> show(
    BuildContext context, {
    CoachSummary? existing,
  }) {
    return GlassDialog.show<CoachProfileDialogDraft>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachProfileEditorDialog(existing: existing),
    );
  }

  @override
  State<CoachProfileEditorDialog> createState() =>
      _CoachProfileEditorDialogState();
}

class _CoachProfileEditorDialogState
    extends State<CoachProfileEditorDialog> {
  late final _displayName = TextEditingController(
    text: widget.existing?.displayName ?? '',
  );
  late final _bio = TextEditingController(
    text: widget.existing?.bio ?? '',
  );
  late final _experience = TextEditingController(
    text: widget.existing?.experience ?? '',
  );
  late final _rate = TextEditingController(
    text: widget.existing?.hourlyRate?.toStringAsFixed(0) ?? '',
  );
  late TeachingMode _mode =
      widget.existing?.teachingMode ?? TeachingMode.onsite;
  late bool _accepting = widget.existing?.acceptingStudents ?? true;

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _experience.dispose();
    _rate.dispose();
    super.dispose();
  }

  bool get _valid => _displayName.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: MediaQuery.of(context).size.height * 0.84,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.badge_outlined,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isNew ? 'สมัครเป็นโค้ช' : 'แก้ไขโปรไฟล์',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        isNew
                            ? 'โปรไฟล์จะแสดงหลังทีมงานอนุมัติ'
                            : 'การแก้ไขไม่กระทบนัดที่ยืนยันแล้ว',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
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
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (ctrl, hint, lines, numeric) in [
                      (_displayName, 'ชื่อที่แสดง *', 1, false),
                      (_bio, 'แนะนำตัว', 3, false),
                      (_experience, 'ประสบการณ์ (เช่น เคยแข่ง/สอนมากี่ปี)', 2, false),
                      (_rate, 'ค่าสอนต่อชั่วโมง (บาท)', 1, true),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: LitGlassSurface.frosted(
                          borderRadius: 12,
                          child: TextField(
                            controller: ctrl,
                            maxLines: lines,
                            keyboardType: numeric
                                ? TextInputType.number
                                : TextInputType.text,
                            decoration: InputDecoration(
                              hintText: hint,
                              hintStyle: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade500,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.all(12),
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 4,
                        bottom: 6,
                      ),
                      child: Text(
                        'รูปแบบการสอน',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final m in TeachingMode.values)
                          GestureDetector(
                            onTap: () => setState(() => _mode = m),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _mode == m
                                    ? AppColors.primary.withValues(
                                        alpha: 0.3,
                                      )
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _mode == m
                                      ? AppColors.primary
                                      : Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Text(
                                CoachLabels.mode(m),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _mode == m
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LitGlassSurface.frosted(
                      borderRadius: 12,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'เปิดรับผู้เรียนใหม่',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  Text(
                                    'ปิดชั่วคราวเมื่อไม่รับงานเพิ่ม',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _accepting,
                              activeThumbColor: AppColors.primaryDark,
                              onChanged: (v) =>
                                  setState(() => _accepting = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GlassActionButton(
                    label: isNew ? 'สร้างโปรไฟล์' : 'บันทึก',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: _valid
                        ? () => Navigator.of(context).pop((
                            displayName: _displayName.text.trim(),
                            bio: _bio.text.trim().isEmpty
                                ? null
                                : _bio.text.trim(),
                            experience: _experience.text.trim().isEmpty
                                ? null
                                : _experience.text.trim(),
                            hourlyRate: double.tryParse(
                              _rate.text.trim(),
                            ),
                            teachingMode: switch (_mode) {
                              TeachingMode.online => 'online',
                              TeachingMode.both => 'both',
                              _ => 'onsite',
                            },
                            acceptingStudents: _accepting,
                          ))
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
}

/// Sports editor — which sports the coach teaches, at which learner
/// levels, with free-form specialties. Replace-all list.
class CoachSportsEditorDialog extends StatefulWidget {
  final List<CoachSportRow> items;

  /// `sports` come from the shared approved-sports catalog.
  final List<Map<String, dynamic>> sports;

  const CoachSportsEditorDialog({
    super.key,
    required this.items,
    required this.sports,
  });

  static Future<List<CoachSportRow>?> show(
    BuildContext context, {
    required List<CoachSportRow> items,
    required List<Map<String, dynamic>> sports,
  }) {
    return GlassDialog.show<List<CoachSportRow>>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachSportsEditorDialog(
        items: items,
        sports: sports,
      ),
    );
  }

  @override
  State<CoachSportsEditorDialog> createState() =>
      _CoachSportsEditorDialogState();
}

class _CoachSportsEditorDialogState
    extends State<CoachSportsEditorDialog> {
  late final List<CoachSportRow> _items = [...widget.items];

  String _sportName(String id) {
    for (final s in widget.sports) {
      if (s['id']?.toString() == id) {
        return s['name_th']?.toString() ??
            s['name']?.toString() ??
            'กีฬา';
      }
    }
    return 'กีฬา';
  }

  Future<void> _addOrEdit(int index) async {
    final existing = index < 0 ? null : _items[index];
    final result = await _SportRowDialog.show(
      context,
      sports: widget.sports
          .where(
            (s) => existing != null &&
                    s['id']?.toString() == existing.sportId
                ? true
                : !_items.any((i) => i.sportId == s['id']?.toString()),
          )
          .toList(),
      existing: existing,
      nameResolver: _sportName,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index < 0) {
        _items.add(result);
      } else {
        _items[index] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.sports_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'กีฬาและระดับผู้เรียน',
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
              child: _items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'ยังไม่มีกีฬา — เพิ่มกีฬาที่คุณสอนอย่างน้อย 1 รายการ',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: LitGlassSurface.frosted(
                            borderRadius: 12,
                            child: ListTile(
                              dense: true,
                              title: Text(
                                _sportName(item.sportId),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              subtitle: Text(
                                [
                                  item.skillLevels
                                      .map(CoachLabels.level)
                                      .join(', '),
                                  if (item.specialties.isNotEmpty)
                                    item.specialties.join(', '),
                                ].where((s) => s.isNotEmpty).join(' · '),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 17,
                                    ),
                                    color: const Color(0xFF475569),
                                    onPressed: () => _addOrEdit(i),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 17,
                                    ),
                                    color: Colors.red.shade400,
                                    onPressed: () => setState(
                                      () => _items.removeAt(i),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: '+ เพิ่มกีฬา',
                    onTap: widget.sports.isEmpty ? null : () => _addOrEdit(-1),
                  ),
                ),
                const SizedBox(width: 10),
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
                    fillColor: AppColors.primary,
                    onTap: () => Navigator.of(context).pop(_items),
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

class _SportRowDialog extends StatefulWidget {
  final List<Map<String, dynamic>> sports;
  final CoachSportRow? existing;
  final String Function(String id) nameResolver;

  const _SportRowDialog({
    required this.sports,
    this.existing,
    required this.nameResolver,
  });

  static Future<CoachSportRow?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> sports,
    required String Function(String id) nameResolver,
    CoachSportRow? existing,
  }) {
    return GlassDialog.show<CoachSportRow>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => _SportRowDialog(
        sports: sports,
        existing: existing,
        nameResolver: nameResolver,
      ),
    );
  }

  @override
  State<_SportRowDialog> createState() => _SportRowDialogState();
}

class _SportRowDialogState extends State<_SportRowDialog> {
  static const _levelOptions = [
    'beginner',
    'intermediate',
    'advanced',
    'pro',
  ];

  String? _sportId;
  late final Set<String> _levels = {...?widget.existing?.skillLevels};
  late final _specialties = TextEditingController(
    text: widget.existing?.specialties.join(', ') ?? '',
  );

  @override
  void initState() {
    super.initState();
    _sportId = widget.existing?.sportId ??
        (widget.sports.isNotEmpty
            ? widget.sports.first['id']?.toString()
            : null);
  }

  @override
  void dispose() {
    _specialties.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _sportId != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'กีฬาที่สอน',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in widget.sports)
                    _pickChip(
                      s['name_th']?.toString() ??
                          s['name']?.toString() ??
                          'กีฬา',
                      _sportId == s['id']?.toString(),
                      () => setState(
                        () => _sportId = s['id']?.toString(),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'ระดับผู้เรียนที่รับ',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final l in _levelOptions)
                    _pickChip(
                      CoachLabels.level(l),
                      _levels.contains(l),
                      () => setState(
                        () => _levels.contains(l)
                            ? _levels.remove(l)
                            : _levels.add(l),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LitGlassSurface.frosted(
                borderRadius: 12,
                child: TextField(
                  controller: _specialties,
                  decoration: InputDecoration(
                    hintText:
                        'จุดเด่น/สายเฉพาะทาง (คั่นด้วยจุลภาค เช่น เสิร์ฟ, เกมรับ)',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(height: 14),
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
                    child: GlassActionButton(
                      label: 'บันทึก',
                      isFilled: true,
                      fillColor: AppColors.primary,
                      onTap: valid
                          ? () => Navigator.of(context).pop(
                              CoachSportRow(
                                sportId: _sportId ?? const Uuid().v4(),
                                skillLevels: _levels.toList(),
                                specialties: _specialties.text
                                    .split(',')
                                    .map((e) => e.trim())
                                    .where((e) => e.isNotEmpty)
                                    .toList(),
                              ),
                            )
                          : null,
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

  Widget _pickChip(String label, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
}
