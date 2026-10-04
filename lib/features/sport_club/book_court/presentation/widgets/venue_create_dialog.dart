import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

/// Create-venue dialog (Phase 21.7.19). Captures the venue name plus the
/// venue-level unit label mode — generic สนาม or a custom 1–40 char label.
/// The sport-derived mode is intentionally absent here: a new venue has no
/// `sports_venue_sports` rows yet, so a reference sport can only be picked
/// later in the sports editor / manage page.
class VenueCreateDialog {
  static Future<({String name, String? venueUnitLabelOverride})?> show(
    BuildContext context,
  ) {
    return GlassDialog.show<({String name, String? venueUnitLabelOverride})>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => const _VenueCreateDialogBody(),
    );
  }
}

class _VenueCreateDialogBody extends StatefulWidget {
  const _VenueCreateDialogBody();

  @override
  State<_VenueCreateDialogBody> createState() => _VenueCreateDialogBodyState();
}

class _VenueCreateDialogBodyState extends State<_VenueCreateDialogBody> {
  bool _custom = false;
  final _name = TextEditingController();
  final _label = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      (!_custom ||
          (_label.text.trim().isNotEmpty && _label.text.trim().length <= 40));

  void _submit() {
    if (!_valid) return;
    Navigator.pop(
      context,
      (
        name: _name.text.trim(),
        venueUnitLabelOverride: _custom ? _label.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
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
                        'สร้างสถานที่ใหม่',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ตั้งชื่อแล้วค่อยกรอกรายละเอียดที่เหลือในหน้าจัดการ',
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
            LitGlassSurface.frosted(
              borderRadius: 14,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _name,
                      maxLength: 120,
                      autofocus: true,
                      decoration: const InputDecoration(
                        counterText: '',
                        labelText: 'ชื่อสถานที่ *',
                        hintText: 'เช่น สนามฟุตบอล ABC, ยิม XYZ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'เรียกสถานที่นี้ว่า',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('คำกลาง "สนาม"'),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('กำหนดเอง'),
                        ),
                      ],
                      selected: {_custom},
                      onSelectionChanged: (s) =>
                          setState(() => _custom = s.first),
                    ),
                    if (_custom)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: _label,
                          maxLength: 40,
                          decoration: const InputDecoration(
                            counterText: '',
                            labelText: 'ชื่อเรียกสถานที่ *',
                            hintText:
                                'เช่น สนาม, ยิม, ฟิตเนส, สตูดิโอ, ห้อง',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'เลือกกีฬาในภายหลังเพื่อให้ชื่อตามประเภทกีฬาได้ '
                          '(เช่น ยิม, สระว่ายน้ำ, สตูดิโอ)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
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
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GlassActionButton(
                    label: 'สร้าง',
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
