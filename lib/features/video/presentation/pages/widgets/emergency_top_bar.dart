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

  const EmergencyTopBar({
    super.key,
    required this.onBackTap,
    this.backButtonVisible = true,
    this.videoControls,
    this.showCategoryFilter = false,
    this.selectedCategoryCount = 0,
    this.onCategoryFilterTap,
  });

  @override
  Widget build(BuildContext context) {
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
        if (showCategoryFilter && onCategoryFilterTap != null) ...[
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
