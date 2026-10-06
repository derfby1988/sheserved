import 'dart:ui';
import 'package:flutter/material.dart';

/// Phase 20: ปุ่มเปิดตัวกรองประเภทเหตุของกล่องยอดนิยม
///
/// ย้ายจาก header ของ [TrendingPanelWidget] มาเป็นปุ่มชิดขวาในแถวบนสุด
/// (แถวเดียวกับปุ่มย้อนกลับ) — ขนาด/สไตล์เดียวกับ `FloatingBackButton` เพื่อให้
/// แถวบนสุดดูเป็นชุดเดียวกัน และยังบอกจำนวนหมวดที่กรองอยู่ด้วย badge
class TrendingCategoryFilterButton extends StatelessWidget {
  /// จำนวนหมวดที่ commit ไว้ (0 = ไม่ได้กรอง)
  final int selectedCount;
  final VoidCallback onTap;

  const TrendingCategoryFilterButton({
    super.key,
    required this.selectedCount,
    required this.onTap,
  });

  static const Color _activeColor = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    final bool active = selectedCount > 0;
    return Tooltip(
      message: 'กรองตามประเภทเหตุ',
      child: Semantics(
        button: true,
        label: active
            ? 'กรองตามประเภทเหตุ อยู่ระหว่างกรอง $selectedCount ประเภท'
            : 'กรองตามประเภทเหตุ',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: active
                        ? _activeColor.withValues(alpha: 0.28)
                        : Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active
                          ? _activeColor.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.tune,
                        size: 18,
                        color: active ? Colors.white : Colors.white70,
                      ),
                      if (active)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 14),
                            height: 14,
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: const BoxDecoration(
                              color: _activeColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '$selectedCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
