import 'package:flutter/material.dart';

/// ค่าคอนฟิกและข้อสังเกตการใช้งาน Neumorphic UI Design System
///
/// ============================================================================
/// [ข้อสังเกตสำคัญสำหรับ Developer / ผู้ใช้งาน Widget ชุดนี้]
/// ============================================================================
/// 1. **สีพื้นหลังต้องตรงกัน (Background Matching):**
///    - Neumorphic อาศัยการหลอกสายตาด้วยเงาสองทิศทาง (แสงขาวสว่างจากบนซ้าย + เงามืดจากล่างขวา)
///    - สีของ Scaffold, Background หรือ Parent container **ต้องเป็นสีเดียวกับ [baseColor]**
///      (ค่าเริ่มต้นคือ `#E7EBF0`) หากใช้บนพื้นหลังสีขาวล้วนหรือสีดำ เงาจะดูลอยและไม่เนียน
///    - **คำแนะนำ:** ให้ตั้งค่า `scaffoldBackgroundColor: NeumorphicTheme.baseColor` ในหน้าจอ
///      หรือครอบหน้าจอด้วย `Container(color: NeumorphicTheme.baseColor)`
///
/// 2. **เงาร่องลึกแบบ Inset Shadow (True Sunken Illusion):**
///    - Flutter ไม่มี CSS `box-shadow: inset` ตรงๆ ใน `BoxDecoration`
///    - เราจึงสร้าง [NeumorphicInsetPainter] และ [NeumorphicInsetBox] ที่ใช้ `clipRRect`
///      วาดเงามืดตกกระทบจากบน-ซ้าย (`rgba(163,177,198, 0.90)`) และแสงสะท้อนขอบล่าง-ขวา
///    - **จุดสำคัญมาก (Gotcha):** ใน Flutter หากแอปมีการตั้งค่า Global `inputDecorationTheme`
///      เช่น `fillColor: Colors.white` ตัว `TextField` จะดึงค่าสีขาวมาเททับระนาบ Canvas อัตโนมัติ
///      ดังนั้นในช่องกรอก [NeumorphicInputField] จะต้องตั้งค่า `filled: true` และ `fillColor: Colors.transparent` เสมอ!
///
/// 3. **ปุ่ม Verify OTP เป็น Vibrant Gradient:**
///    - เพื่อให้ปุ่ม Call-to-Action เด่นชัด ในดีไซน์ต้นฉบับจะใช้ปุ่มสีฟ้าไล่เฉด (Cyan-Blue Gradient)
///      พร้อมเงาสะท้อนเรืองแสงสีฟ้า (Glow Shadow) แทนการใช้เงาปูนแบบ Neumorphic ปกติ
///
/// 4. **การปรับเปลี่ยนสี (Customization):**
///    - หากต้องการปรับธีมให้เข้มขึ้นหรือสว่างขึ้น สามารถสร้าง instance `NeumorphicThemeData`
///      ส่งผ่าน constructor หรือตั้งค่าคงที่ได้
/// ============================================================================
class NeumorphicTheme {
  NeumorphicTheme._();

  /// สีพื้นหลัก Neumorphic (#E7EBF0 ตาม CSS ในต้นฉบับ)
  static const Color baseColor = Color(0xFFE7EBF0);

  /// เงามืดล่างขวา (rgba(163, 177, 198, 0.65))
  static const Color shadowDark = Color.fromRGBO(163, 177, 198, 0.65);

  /// เงาสว่างบนซ้าย (rgba(255, 255, 255, 0.95))
  static const Color shadowLight = Color.fromRGBO(255, 255, 255, 0.95);

  /// เงากลางสำหรับชิ้นส่วนขนาดเล็ก (rgba(163, 177, 198, 0.45))
  static const Color shadowSmallDark = Color.fromRGBO(163, 177, 198, 0.45);

  /// เงาสว่างสำหรับชิ้นส่วนขนาดเล็ก
  static const Color shadowSmallLight = Color.fromRGBO(255, 255, 255, 0.90);

  /// สีขอบเรืองแสงเมื่อ Focus ช่อง OTP (Cyan / Sky Blue)
  static const Color accentCyan = Color(0xFF38BDF8);

  /// สี Primary ฟ้าเข้มสำหรับ Gradient
  static const Color primaryBlue = Color(0xFF2563EB);

  /// สีข้อความหัวข้อหลัก (Dark Slate)
  static const Color textPrimary = Color(0xFF1E293B);

  /// สีข้อความรอง (Slate Grey)
  static const Color textSecondary = Color(0xFF64748B);

  /// Gradient สีฟ้าสำหรับปุ่ม Verify OTP ตามรูปเป๊ะๆ
  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF38BDF8), // Cyan ฟ้าสว่าง
      Color(0xFF2563EB), // Royal Blue ฟ้าน้ำเงิน
    ],
  );

  /// เงาคู่สไตล์ Neumorphic Card ตาม CSS:
  /// `20px 20px 40px rgba(163,177,198,.65), -20px -20px 40px rgba(255,255,255,.95)`
  static List<BoxShadow> cardShadows({
    double distance = 20,
    double blur = 40,
    double darkOpacity = 0.65,
    double lightOpacity = 0.95,
  }) {
    return [
      BoxShadow(
        color: Color.fromRGBO(163, 177, 198, darkOpacity),
        offset: Offset(distance, distance),
        blurRadius: blur,
      ),
      BoxShadow(
        color: Color.fromRGBO(255, 255, 255, lightOpacity),
        offset: Offset(-distance, -distance),
        blurRadius: blur,
      ),
    ];
  }

  /// เงาคู่สำหรับชิ้นส่วนขนาดเล็ก เช่น ช่อง OTP หรือ Badge
  static List<BoxShadow> smallShadows({
    double distance = 6,
    double blur = 12,
  }) {
    return [
      BoxShadow(
        color: shadowSmallDark,
        offset: Offset(distance, distance),
        blurRadius: blur,
      ),
      BoxShadow(
        color: shadowSmallLight,
        offset: Offset(-distance, -distance),
        blurRadius: blur,
      ),
    ];
  }

  /// เงาสะท้อนเรืองแสงสีฟ้าสำหรับปุ่มและช่อง Active
  static List<BoxShadow> glowShadows({
    Color color = accentCyan,
    double blur = 16,
    double spread = 0,
    Offset offset = const Offset(0, 6),
  }) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.35),
        offset: offset,
        blurRadius: blur,
        spreadRadius: spread,
      ),
    ];
  }
}
