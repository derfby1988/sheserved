import 'package:flutter/material.dart';

/// วาดเงาจมด้านใน (True Inset / Sunken Shadow) เลียนแบบ CSS `box-shadow: inset`
///
/// **หลักการสร้างมิติร่องลึก (Deep Sunken Effect):**
/// 1. สีพื้นร่อง (Base Gradient): ไล่เฉดจากมุมบน-ซ้ายมืด `#D4DAE3` สู่ล่าง-ขวาสว่าง `#EAEFF5`
///    เพื่อให้มวลสารของร่องยุบลงไปในผิวการ์ดอย่างเป็นธรรมชาติ
/// 2. เงาจมมืดตกกระทบจากขอบบน-ซ้าย (Dark Inset Shadow): สีมืด `rgba(163, 177, 198, 0.90)`
/// 3. แสงสะท้อนจมด้านล่าง-ขวา (Light Inset Highlight): สีขาว `rgba(255, 255, 255, 0.95)`
/// 4. ป้องกันปัญหาสีขาวของ `inputDecorationTheme` ทับซ้อนด้วยการใช้พื้นโปร่งใสในช่องกรอก
class NeumorphicInsetPainter extends CustomPainter {
  final double borderRadius;
  final Color? baseColor;
  final Color shadowDark;
  final Color shadowLight;
  final double distance;
  final double blur;
  final BorderSide? border;

  NeumorphicInsetPainter({
    required this.borderRadius,
    this.baseColor,
    this.shadowDark = const Color.fromRGBO(163, 177, 198, 0.90),
    this.shadowLight = const Color.fromRGBO(255, 255, 255, 0.95),
    this.distance = 4.0,
    this.blur = 6.0,
    this.border,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // 1. ลงสีพื้นร่องลึก (ไล่เฉดแสงมืดจากบนซ้ายไปสว่างล่างขวา เพื่อสร้างความรู้สึกลึกชัดเจน)
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFD2D8E2), // มุมบนซ้ายลึกมืด
          const Color(0xFFDFE4EB), // กลางร่อง
          const Color(0xFFEBF0F6), // มุมล่างขวารับแสง
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, bgPaint);

    // บันทึก Layer และ Clip เฉพาะภายในกรอบกล่อง
    canvas.save();
    canvas.clipRRect(rrect);

    final outerRect = rect.inflate(blur * 3 + distance * 3);
    final outerPath = Path()..addRect(outerRect);

    // 2. เงาจมมืดด้านบน-ซ้าย (Dark Inset Shadow)
    final shiftedDarkRRect = rrect.shift(Offset(distance, distance));
    final darkInnerPath = Path()..addRRect(shiftedDarkRRect);
    final darkDifference =
        Path.combine(PathOperation.difference, outerPath, darkInnerPath);

    final darkPaint = Paint()
      ..color = shadowDark
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    canvas.drawPath(darkDifference, darkPaint);

    // ขอบสันเงาบน-ซ้ายคมชัด
    final darkBevelPaint = Paint()
      ..color = shadowDark.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawRRect(rrect, darkBevelPaint);

    // 3. แสงสะท้อนจมด้านล่าง-ขวา (Light Inset Highlight)
    final shiftedLightRRect = rrect.shift(Offset(-distance, -distance));
    final lightInnerPath = Path()..addRRect(shiftedLightRRect);
    final lightDifference =
        Path.combine(PathOperation.difference, outerPath, lightInnerPath);

    final lightPaint = Paint()
      ..color = shadowLight
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    canvas.drawPath(lightDifference, lightPaint);

    canvas.restore();

    // 4. วาดเส้นขอบ (เช่น ขอบเรืองแสงสีฟ้า Cyan ตอน Focus)
    if (border != null && border!.style != BorderStyle.none) {
      final borderPaint = Paint()
        ..color = border!.color
        ..strokeWidth = border!.width
        ..style = PaintingStyle.stroke;
      final innerBorderRRect = rrect.deflate(border!.width / 2);
      canvas.drawRRect(innerBorderRRect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant NeumorphicInsetPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.shadowDark != shadowDark ||
        oldDelegate.shadowLight != shadowLight ||
        oldDelegate.distance != distance ||
        oldDelegate.blur != blur ||
        oldDelegate.border != border;
  }
}

/// กล่องสไตล์ Neumorphic Inset (ร่องจม) พร้อมเงาตกกระทบภายใน
class NeumorphicInsetBox extends StatelessWidget {
  final Widget? child;
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? baseColor;
  final Color shadowDark;
  final Color shadowLight;
  final double distance;
  final double blur;
  final BorderSide? border;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? outerGlowShadows;

  const NeumorphicInsetBox({
    super.key,
    this.child,
    this.width,
    this.height = 54.0,
    this.borderRadius = 16.0,
    this.baseColor,
    this.shadowDark = const Color.fromRGBO(163, 177, 198, 0.90),
    this.shadowLight = const Color.fromRGBO(255, 255, 255, 0.95),
    this.distance = 4.0,
    this.blur = 6.0,
    this.border,
    this.padding,
    this.outerGlowShadows,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = CustomPaint(
      painter: NeumorphicInsetPainter(
        borderRadius: borderRadius,
        baseColor: baseColor,
        shadowDark: shadowDark,
        shadowLight: shadowLight,
        distance: distance,
        blur: blur,
        border: border,
      ),
      child: Container(
        width: width,
        height: height,
        padding: padding,
        child: child,
      ),
    );

    // หากมีเงาเรืองแสงรอบนอก (เช่น Cyan Glow ตอน Active)
    if (outerGlowShadows != null && outerGlowShadows!.isNotEmpty) {
      content = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: outerGlowShadows,
        ),
        child: content,
      );
    }

    return content;
  }
}
