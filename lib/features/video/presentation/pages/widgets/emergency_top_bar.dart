import 'package:flutter/material.dart';
import 'floating_back_button.dart';
import 'trending_category_filter_button.dart';

/// แถวบนสุดของหน้าเหตุการณ์สด: ปุ่มย้อนกลับ (ซ้าย) + เครื่องมือวิดีโอ + ปุ่ม
/// ตัวกรองประเภทเหตุของกล่องยอดนิยม (ชิดขวา)
///
/// Layout note: ระหว่างปุ่มย้อนกลับกับปุ่มตัวกรองใช้ [Expanded] + [Align] แทน
/// `Flexible` คู่กับ `Spacer` เพราะ `Flexible` กับ `Spacer` จะแบ่งพื้นที่ว่าง
/// คนละครึ่ง ทำให้เครื่องมือวิดีโอถูกบีบแม้จอกว้าง ส่วน `Expanded` + `Align`
/// ปล่อยให้เครื่องมือคงความกว้างตามเนื้อหา และหดได้เฉพาะเมื่อจอแคบจริง —
/// ตัวเครื่องมือเองมี `SingleChildScrollView` แนวนอนอยู่แล้ว จึงเลื่อนได้
/// โดยไม่ล้นจอ (ทดสอบที่ 320dp)
class EmergencyTopBar extends StatelessWidget {
  final VoidCallback onBackTap;
  final bool backButtonVisible;

  /// เครื่องมือวิดีโอ (แสดงเมื่อวิดีโอพร้อมเล่น) — null = ไม่แสดง
  final Widget? videoControls;

  final bool showCategoryFilter;
  final int selectedCategoryCount;
  final VoidCallback? onCategoryFilterTap;

  /// Phase 22 — action ฝั่งขวาแบบข้อความ ("เลือกเหตุการณ์อื่น" ขณะมี
  /// map-return context หรือ "เปลี่ยนประเภทเหตุ" ในโหมดแผนที่) — เมื่อให้มา
  /// จะ **แทนที่** ปุ่มตัวกรองในตำแหน่งเดียวกัน (§22.1)
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  const EmergencyTopBar({
    super.key,
    required this.onBackTap,
    this.backButtonVisible = true,
    this.videoControls,
    this.showCategoryFilter = false,
    this.selectedCategoryCount = 0,
    this.onCategoryFilterTap,
    this.trailingLabel,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    final showTrailing =
        trailingLabel != null && trailingLabel!.isNotEmpty && onTrailingTap != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FloatingBackButton(visible: backButtonVisible, onTap: onBackTap),
        if (videoControls != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: videoControls),
          ),
        ] else
          const Spacer(),
        if (showTrailing) ...[
          const SizedBox(width: 8),
          _TopBarTextPill(label: trailingLabel!, onTap: onTrailingTap!),
        ] else if (showCategoryFilter && onCategoryFilterTap != null) ...[
          const SizedBox(width: 8),
          TrendingCategoryFilterButton(
            selectedCount: selectedCategoryCount,
            onTap: onCategoryFilterTap!,
          ),
        ],
      ],
    );
  }
}

/// ป้ายข้อความแบบแคปซูลกระจก — ใช้พื้นที่เทียบเท่าปุ่มตัวกรอง (สูง 42)
/// และย่อ/ตัดข้อความได้บนจอแคบ (§22.3.2)
class _TopBarTextPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TopBarTextPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
