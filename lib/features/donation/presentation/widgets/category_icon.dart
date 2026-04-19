import 'package:flutter/material.dart';
import '../../../../core/constants/app_text_styles.dart';

/// ปุ่มไอคอนหมวดหมู่แบบวงกลมพร้อมชื่อด้านล่าง
class CategoryIcon extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color? labelColor;
  final VoidCallback onTap;

  const CategoryIcon({
    super.key,
    required this.label,
    required this.icon,
    this.iconColor = const Color(0xFF76A5A5),
    this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 76,
              height: 32, // บังคับความสูงคงที่สำหรับ 2 บรรทัดพอดี
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                strutStyle: const StrutStyle(
                  fontSize: 11,
                  height: 1.2,
                  forceStrutHeight: true,
                ),
                style: AppTextStyles.caption.copyWith(
                  color: labelColor ?? Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  height: 1.2,
                  letterSpacing: -0.3, // บีบตัวอักษรลงนิดหน่อยให้พอดียิ่งขึ้น
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
