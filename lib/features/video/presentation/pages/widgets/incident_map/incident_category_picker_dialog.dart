import 'package:flutter/material.dart';
import 'package:sheserved/features/donation/models/donation_models.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

/// Phase 22 — dialog เลือกประเภทเหตุของโหมดแผนที่เกิดเหตุ
///
/// ใช้แทน bottom sheet ตัวกรองยอดนิยมเมื่อกด "เปลี่ยนประเภทเหตุ" ในโหมดแผนที่:
/// โหมดแผนที่แสดงทีละหมวดเสมอ จึงเป็นรายการปุ่มให้เลือกหมวดเดียว แล้วสลับหมวด
/// ของแผนที่ทันที — **ไม่**แตะ draft/ตัวกรองที่ commit ของ Phase 20
///
/// - รายการมาจากตารางจริง (`donation_categories` where `is_emergency = true`
///   เรียง `display_order asc`) — ลำดับเดียวกับ [TrendingCategoryFilterSheet]
///   เพราะผู้เรียกส่ง `_emergencyCategories` ชุดเดียวกันมา
/// - UI ใช้ glass layer (`lib/shared/widgets/glass`)
class IncidentCategoryPickerDialog {
  /// สีส้มเดียวกับป้าย "ยอดนิยม"/ปุ่มตัวกรอง/หมุดในโหมดแผนที่
  static const Color _accent = Color(0xFFFF6B35);

  /// คืนหมวดที่ผู้ใช้เลือก หรือ `null` เมื่อปิด dialog (รวมแตะฉากหลัง)
  static Future<DonationCategory?> show(
    BuildContext context, {
    required List<DonationCategory> categories,
    String? currentCategoryId,
  }) {
    return GlassDialog.show<DonationCategory>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      panelAccentColor: _accent,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'เปลี่ยนประเภทเหตุ',
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
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                categories.isEmpty
                    ? 'ยังโหลดรายการประเภทเหตุไม่ได้ — กรุณาลองใหม่'
                    : 'เลือกประเภทเหตุที่จะแสดงบนแผนที่',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final category in categories) ...[
                          _categoryButton(
                            dialogContext,
                            category,
                            category.id == currentCategoryId,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// ปุ่มหมวดหนึ่งรายการ — หมวดที่กำลังแสดงอยู่ใช้สไตล์ filled + ไอคอนแผนที่
  /// เพื่อให้เห็นว่าปัจจุบันแผนที่แสดงหมวดไหน
  static Widget _categoryButton(
    BuildContext dialogContext,
    DonationCategory category,
    bool isCurrent,
  ) {
    return GlassActionButton(
      label: category.name,
      isFilled: isCurrent,
      fillColor: _accent,
      onTap: () => Navigator.of(dialogContext).pop(category),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent) ...[
            const Icon(Icons.map_outlined, size: 15, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              category.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'SukhumvitSet',
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: isCurrent ? 1.0 : 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
