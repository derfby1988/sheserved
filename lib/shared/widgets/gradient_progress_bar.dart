import 'package:flutter/material.dart';

/// แถบความคืบหน้าแบบ gradient แบบไม่ระบุจำนวน (indeterminate) — ใช้บอกว่า
/// กำลังโหลดข้อมูล/ภาพชุดใหม่ โดยไม่บัง content ด้านหลัง
///
/// segment กวาดจากนอกจอซ้ายไปนอกจอขวาแล้ววนซ้ำ และจางหัว-ท้ายด้วย alpha
/// จึงไม่เห็นการกระตุกตอนเริ่มรอบใหม่ (ต่างจาก `CircularProgressIndicator`
/// ที่ไม่บอกว่ากำลังโหลดส่วนไหนของหน้าจอ)
class GradientProgressBar extends StatefulWidget {
  /// ความสูงของแถบ — ดีฟอลต์บาง ๆ เหมือน loading bar ของเบราว์เซอร์
  final double height;

  /// สีของ gradient ที่กวาดจากซ้ายไปขวา
  final List<Color> colors;

  /// สีรางด้านหลังแถบ — null = โปร่งใส มองเห็นแผนที่ด้านหลัง
  final Color? trackColor;

  /// ระยะเวลาต่อหนึ่งรอบการกวาด
  final Duration period;

  final BorderRadius borderRadius;

  const GradientProgressBar({
    super.key,
    this.height = 3,
    this.colors = const [
      Color(0xFFFF6B35),
      Color(0xFFFFC24B),
      Color(0xFFFF6B35),
    ],
    this.trackColor,
    this.period = const Duration(milliseconds: 1300),
    this.borderRadius = const BorderRadius.all(Radius.circular(99)),
  });

  @override
  State<GradientProgressBar> createState() => _GradientProgressBarState();
}

class _GradientProgressBarState extends State<GradientProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// ค่า alignment ที่ทำให้ segment (กว้าง [widthFactor] ของแถบ) วิ่งจาก
  /// นอกซ้ายไปนอกขวาพอดี: จุดที่หลุดจอคือ ±(1 + widthFactor) / (1 - widthFactor)
  static const double _widthFactor = 0.45;
  static const double _slideExtent = (1 + _widthFactor) / (1 - _widthFactor);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: ColoredBox(
          color: widget.trackColor ?? Colors.transparent,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final slide =
                  -_slideExtent + 2 * _slideExtent * _controller.value;
              return Align(
                alignment: Alignment(slide, 0),
                child: FractionallySizedBox(
                  widthFactor: _widthFactor,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.colors.first.withValues(alpha: 0),
                          ...widget.colors,
                          widget.colors.last.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
