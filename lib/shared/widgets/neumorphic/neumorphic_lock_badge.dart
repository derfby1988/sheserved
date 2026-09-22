import 'package:flutter/material.dart';
import 'neumorphic_theme.dart';

/// ไอคอนแม่กุญแจในกรอบวงกลมสไตล์ Neumorphic ตามดีไซน์ส่วนบนของการ์ด OTP
///
/// **ข้อสังเกตสำหรับผู้ใช้งาน (Developer Note):**
/// - ใช้วงกลมสไตล์นูน (Raised Circle) ซ้อนเงาสองชั้นบนพื้น `#E7EBF0`
/// - ตัวแม่กุญแจเป็นสีทอง (Amber/Gold gradient) พร้อมรูกุญแจตรงกลางเหมือนในรูปต้นฉบับ
class NeumorphicLockBadge extends StatelessWidget {
  final double size;
  final double iconSize;

  const NeumorphicLockBadge({
    super.key,
    this.size = 80.0,
    this.iconSize = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: NeumorphicTheme.baseColor,
        shape: BoxShape.circle,
        boxShadow: [
          // เงามืดล่างขวา
          BoxShadow(
            color: NeumorphicTheme.shadowDark.withValues(alpha: 0.5),
            offset: const Offset(8, 8),
            blurRadius: 18,
          ),
          // เงาสว่างบนซ้าย
          BoxShadow(
            color: NeumorphicTheme.shadowLight,
            offset: const Offset(-8, -8),
            blurRadius: 18,
          ),
        ],
      ),
      child: Center(child: _buildGoldLock(iconSize)),
    );
  }

  /// สร้างรูปแม่กุญแจสีทองที่มีแสงสะท้อนและรูกุญแจเหมือนในรูปต้นฉบับ
  Widget _buildGoldLock(double size) {
    final bodyWidth = size * 0.72;
    final bodyHeight = size * 0.58;
    final shackleRadius = size * 0.28;
    final shackleStroke = size * 0.12;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ห่วงแม่กุญแจ (Shackle) ด้านบน
          // วาดเป็นวงแหวน gradient สองชั้นแทน Border หลายสี
          // (BoxDecoration ไม่รองรับ borderRadius กับ border ที่สีไม่เท่ากัน)
          Positioned(
            top: size * 0.08,
            child: Container(
              width: shackleRadius * 2,
              height: shackleRadius * 2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(shackleRadius),
                  topRight: Radius.circular(shackleRadius),
                ),
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFFC48E2E),
                    Color(0xFFE5B350),
                    Color(0xFFE5B350),
                  ],
                  stops: [0.0, 0.35, 1.0],
                ),
              ),
              padding: EdgeInsets.only(
                top: shackleStroke,
                left: shackleStroke,
                right: shackleStroke,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: NeumorphicTheme.baseColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(shackleRadius - shackleStroke),
                    topRight: Radius.circular(shackleRadius - shackleStroke),
                  ),
                ),
              ),
            ),
          ),

          // ตัวแม่กุญแจสีทอง (Lock Body) ด้านล่าง
          Positioned(
            bottom: size * 0.10,
            child: Container(
              width: bodyWidth,
              height: bodyHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFDF7D), // ทองสว่างสะท้อนแสง
                    Color(0xFFF5B027), // ทองกลาง
                    Color(0xFFD48B10), // ทองเข้ม
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF996515).withValues(alpha: 0.35),
                    offset: const Offset(0, 3),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Center(
                // รูกุญแจ (Keyhole)
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: size * 0.11,
                      height: size * 0.11,
                      decoration: const BoxDecoration(
                        color: Color(0xFF5A3D0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: size * 0.065,
                      height: size * 0.11,
                      decoration: const BoxDecoration(
                        color: Color(0xFF5A3D0B),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(2),
                          bottomRight: Radius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
