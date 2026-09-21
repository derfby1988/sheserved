import 'package:flutter/material.dart';
import 'neumorphic_theme.dart';

/// Container สไตล์ Neumorphic ที่สร้างมิติด้วยเงาสองทิศทาง (Raised / Pressed)
///
/// **ข้อสังเกตสำหรับผู้ใช้งาน (Developer Note):**
/// - พื้นหลังรอบ Container ชิ้นนี้ควรมีสีเดียวกับ [color] (ค่าเริ่มต้น [NeumorphicTheme.baseColor] = `#E7EBF0`)
///   เพื่อให้เอฟเฟกต์เงาสองชั้น (เงาสว่าง + เงามืด) เกิดมิตินูนเนียนตาที่สุด
/// - หากหน้าจอของคุณมีพื้นหลังสีอื่น เช่น ขาวล้วน ให้เปลี่ยนค่า [color] หรือครอบหน้าจอด้วยสี `#E7EBF0`
class NeumorphicContainer extends StatelessWidget {
  final Widget? child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final BoxShape shape;
  final Color color;
  final double depth;
  final double blur;
  final bool isPressed;
  final Border? border;
  final List<BoxShadow>? customShadows;

  const NeumorphicContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 35.0, // ตาม CSS .form-panel { border-radius: 35px; }
    this.shape = BoxShape.rectangle,
    this.color = NeumorphicTheme.baseColor,
    this.depth = 12.0,
    this.blur = 24.0,
    this.isPressed = false,
    this.border,
    this.customShadows,
  });

  @override
  Widget build(BuildContext context) {
    // กรณี shape เป็น circle จะไม่ใช้ borderRadius
    final effectiveBorderRadius =
        shape == BoxShape.circle ? null : BorderRadius.circular(borderRadius);

    List<BoxShadow> shadows;
    if (customShadows != null) {
      shadows = customShadows!;
    } else if (isPressed) {
      // สำหรับสไตล์จม (Pressed): เงาจะกลับทิศและลดรัศมีลง
      shadows = [
        BoxShadow(
          color: NeumorphicTheme.shadowDark.withValues(alpha: 0.35),
          offset: Offset(-depth * 0.5, -depth * 0.5),
          blurRadius: blur * 0.5,
        ),
        BoxShadow(
          color: NeumorphicTheme.shadowLight.withValues(alpha: 0.7),
          offset: Offset(depth * 0.5, depth * 0.5),
          blurRadius: blur * 0.5,
        ),
      ];
    } else {
      // สำหรับสไตล์นูนปกติ (Raised)
      shadows = [
        BoxShadow(
          color: NeumorphicTheme.shadowDark,
          offset: Offset(depth, depth),
          blurRadius: blur,
        ),
        BoxShadow(
          color: NeumorphicTheme.shadowLight,
          offset: Offset(-depth, -depth),
          blurRadius: blur,
        ),
      ];
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        shape: shape,
        borderRadius: effectiveBorderRadius,
        boxShadow: shadows,
        border: border,
        // เพิ่ม gradient เบาๆ หากเป็นสไตล์จมเพื่อหลอกสายตาแทน inset shadow
        gradient: isPressed
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFD9DFE7),
                  color,
                ],
              )
            : null,
      ),
      child: child,
    );
  }
}
