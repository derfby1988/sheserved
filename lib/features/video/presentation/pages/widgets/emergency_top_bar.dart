import 'package:flutter/material.dart';
import 'floating_back_button.dart';
import 'trending_category_filter_button.dart';

/// แถวบนสุดของหน้าเหตุการณ์สด: ปุ่มย้อนกลับ (ซ้าย) + เครื่องมือวิดีโอ + ปุ่ม
/// ตัวกรองประเภทเหตุของกล่องยอดนิยม + action ฝั่งขวา (ชิดขวา)
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

  /// Phase 22 — action ฝั่งขวา เช่น ปุ่มปิดวงกลมใน map-playback context.
  /// `trailingLabel` เป็นข้อความ/semantics; [trailingIcon] เลือกปุ่มวงกลม
  /// แทนป้ายข้อความ
  final String? trailingLabel;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;

  /// ปุ่มประเภทเหตุที่กำลังแสดงบนแผนที่ — แตะเพื่อเปิด category picker
  /// แทนปุ่มเปลี่ยนประเภทแยก; null = ไม่แสดง
  final String? categoryLabel;
  final VoidCallback? onCategoryLabelTap;

  const EmergencyTopBar({
    super.key,
    required this.onBackTap,
    this.backButtonVisible = true,
    this.videoControls,
    this.showCategoryFilter = false,
    this.selectedCategoryCount = 0,
    this.onCategoryFilterTap,
    this.trailingLabel,
    this.trailingIcon,
    this.onTrailingTap,
    this.categoryLabel,
    this.onCategoryLabelTap,
  });

  @override
  Widget build(BuildContext context) {
    final showTrailing =
        trailingLabel != null && trailingLabel!.isNotEmpty && onTrailingTap != null;
    final showCategoryLabel = categoryLabel != null && categoryLabel!.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FloatingBackButton(visible: backButtonVisible, onTap: onBackTap),
        if (videoControls != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: videoControls),
          ),
        ] else if (showCategoryLabel) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _TopBarCategoryChip(
                label: categoryLabel!,
                onTap: onCategoryLabelTap,
              ),
            ),
          ),
        ] else
          const Spacer(),
        // ปุ่มตัวกรองเป็นอิสระจาก action ฝั่งขวา; caller ซ่อน filter ใน
        // map-playback context และเปิดกลับเมื่อคืน Emergency ปกติ (§22.14)
        if (showCategoryFilter && onCategoryFilterTap != null) ...[
          const SizedBox(width: 8),
          TrendingCategoryFilterButton(
            selectedCount: selectedCategoryCount,
            onTap: onCategoryFilterTap!,
          ),
        ],
        if (showTrailing) ...[
          const SizedBox(width: 8),
          if (trailingIcon != null)
            Semantics(
              button: true,
              label: trailingLabel,
              child: FloatingBackButton(
                icon: trailingIcon!,
                onTap: onTrailingTap!,
              ),
            )
          else
            Flexible(
              child: _TopBarTextPill(
                label: trailingLabel!,
                onTap: onTrailingTap!,
              ),
            ),
        ],
      ],
    );
  }
}

/// ปุ่มสถานการณ์ปัจจุบันบนแผนที่ — แตะเพื่อเปิด category picker (§22.3.4)
class _TopBarCategoryChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _TopBarCategoryChip({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      container: enabled,
      button: enabled,
      enabled: enabled,
      excludeSemantics: enabled,
      label: enabled ? 'เปลี่ยนประเภทเหตุ: $label' : label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(21),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined, size: 15, color: Colors.white70),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 17,
                    color: Colors.white70,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
