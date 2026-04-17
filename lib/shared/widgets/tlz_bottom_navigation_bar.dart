import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// วิดเจ็ต Navigation Bar ส่วนกลางที่ออกแบบมาให้ลอยเด่น (Floating) อยู่เหนือเนื้อหาด้วยสไตล์ Glassmorphism
/// 
/// ⚠️ **[สำคัญ] ข้อควรจำ 3 ข้อสำหรับหน้าจอที่จะเรียกใช้งาน (เพื่อให้ลอยสวยงาม):**
/// เพื่อให้ Navigation Bar วางลอยตัวและให้เนื้อหาสามารถมุดลอดผ่านด้านใต้ได้ กรุณาตั้งหน้าจอดังนี้:
/// 1. ที่ `Scaffold` หลัก: ต้องตั้งค่า `extendBody: true,` เสมอ
/// 2. ที่กรอบกั้นเนื้อหา `SafeArea` (ถ้ามี): ต้องตั้งค่า `bottom: false,` เพื่อให้เนื้อหาทะลุลงขอบล่างได้
/// 3. ที่ท้ายสุดของเนื้อหาที่เลื่อนได้ (เช่นใน ListView/Column): ให้ใส่ `const SizedBox(height: 120)` กันหน้าสุดท้ายถูกทับเสมอ
///
/// **ตัวอย่างการใช้งานแบบสมบูรณ์:**
/// ```dart
/// Scaffold(
///   extendBody: true,   // <--- กฎข้อที่ 1
///   bottomNavigationBar: Builder(
///     builder: (context) => TlzBottomNavigationBar(
///       currentIndex: 0,
///       scrollController: _scrollController, // ใส่ตัวนี้เพื่อมี Animation ซ่อน/แสดงอัตโนมัติ
///       onIndexChanged: (index) { /* เปลี่ยนหน้า */ },
///       onAddPressed: () { /* กดปุ่มแจ้งเหตุ */ },
///     ),
///   ),
///   body: SafeArea(
///     bottom: false,    // <--- กฎข้อที่ 2
///     child: SingleChildScrollView(
///       controller: _scrollController,
///       child: Column(
///         children: [
///           // ... ใส่เนื้อหา Content ตามปกติ ...
///           const SizedBox(height: 120), // <--- กฎข้อที่ 3
///         ],
///       ),
///     ),
///   ),
/// )
/// ```
class TlzBottomNavigationBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onIndexChanged;
  final VoidCallback onAddPressed;
  final ScrollController? scrollController;

  const TlzBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.onAddPressed,
    this.scrollController,
  });

  @override
  State<TlzBottomNavigationBar> createState() => _TlzBottomNavigationBarState();
}

class _TlzBottomNavigationBarState extends State<TlzBottomNavigationBar> {
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant TlzBottomNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (widget.scrollController == null) return;
    
    final direction = widget.scrollController!.position.userScrollDirection;
    if (direction == ScrollDirection.reverse) {
      if (_isVisible) {
        setState(() => _isVisible = false);
      }
    } else if (direction == ScrollDirection.forward) {
      if (!_isVisible) {
        setState(() => _isVisible = true);
      }
    }
  }

  // ─── จานสีจาก Reference ─── //
  // ดึงจากภาพต้นแบบ: ปุ่มดาร์กสีเทาดำ charcoal มีผิว olive
  static const _darkBtnColor = Color(0xFF3A3D33);
  // ไอคอนในปุ่มดาร์ก: สีเขียวอมเหลือง / ครีมอ่อน
  static const _darkBtnIconColor = Color(0xFFCCD68A);
  // ปุ่ม Active: สีครีม ivory อ่อนนุ่ม
  static const _activeBtnColor = Color(0xFFF0EDD8);
  // ไอคอนสถานะ Active: สีเทาดำ
  static const _activeIconColor = Color(0xFF2C2D28);
  // ไอคอนปกติ: สีเทา olive อ่อน
  static const _defaultIconColor = Color(0xFF5C5E54);

  /// คำนวณตัวคูณขนาดจากความกว้างจอ (ฐาน 400px)
  /// จอกว้าง 400px = scale 1.0, จอแคบกว่า = ลดขนาด, จอกว้างกว่า = เพิ่มเล็กน้อย (cap ไว้ที่ 1.1)
  double _scale(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return (w / 400).clamp(0.7, 1.1);
  }

  @override
  Widget build(BuildContext context) {
    final s = _scale(context);
    final hPad = (18 * s).roundToDouble();
    final innerPad = (12 * s).roundToDouble();
    final radius = (40 * s).clamp(28.0, 40.0);
    
    // ดึงค่าพื้นที่ปลอดภัยด้านล่าง (เช่น แถบ Home ของ iOS)
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    // ปรับให้ iOS สูง 14px แบบคงที่ (ตามที่ผู้ใช้ต้องการ) ส่วน Android ใช้ 16px (คูณ scale)
    final bottomMargin = bottomSafeArea > 0 ? 14.0 : 16 * s;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      offset: _isVisible ? Offset.zero : const Offset(0, 1.5),
      curve: Curves.easeInOut,
      child: Padding(
        padding: EdgeInsets.only(left: hPad, right: hPad, bottom: bottomMargin),
        child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // ─── โซนซ้าย: ปุ่ม Home แยกออกมา ─── //
              _buildGlassBlock(
                radius: radius,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: innerPad, vertical: 8 * s),
                  child: _buildNavItem(0, Icons.home_filled, 'Home', s),
                ),
              ),
              
              SizedBox(width: 8 * s), // ระยะห่าง 2 โซน

              // ─── โซนขวา: เครื่องมืออื่นๆ แบบแคปซูล ─── //
              Expanded(
                child: _buildGlassBlock(
                  radius: radius,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: innerPad, vertical: 8 * s),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildGlassBubbleNav(1, Icons.volunteer_activism_rounded, s, hasNotification: true),
                        _buildAddButton(s),
                        _buildGlassBubbleNav(3, Icons.local_pharmacy_rounded, s),
                        _buildGlassBubbleNav(4, Icons.person_rounded, s),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
    );
  }

  /// สร้างก้อนกระจกไล่สี
  Widget _buildGlassBlock({required double radius, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 40,
            spreadRadius: -4,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
          child: CustomPaint(
            foregroundPainter: _GlassEdgePainter(radius: radius),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                color: Colors.white.withOpacity(0.01),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// ─── ปุ่ม Home แบบ Pill: เมื่อ Active จะขยายเป็นแคปซูลครีม ─── ///
  Widget _buildNavItem(int index, IconData icon, String label, double s) {
    final isSelected = widget.currentIndex == index;
    final iconSize = (22 * s).roundToDouble();
    final fontSize = (13 * s).roundToDouble();

    return GestureDetector(
      onTap: () => widget.onIndexChanged(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 14 * s : 10 * s,
          vertical: 8 * s,
        ),
        decoration: BoxDecoration(
          color: isSelected ? _activeBtnColor : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          // ขอบขาวเล็กมากสำหรับปุ่ม Active (เหมือนขอบเม็ดกระจก)
          border: isSelected
              ? Border.all(color: Colors.white.withOpacity(0.9), width: 1.0)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                  // Inner glow effect: เงาสีขาวเพื่อให้ดูนูน
                  BoxShadow(
                    color: Colors.white.withOpacity(0.7),
                    blurRadius: 1,
                    spreadRadius: -1,
                    offset: const Offset(0, -1),
                  ),
                ]
              : null,
        ),
        child: Builder(
          builder: (context) {
            final content = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.white : _defaultIconColor, // สีขาวถูกใช้เพื่อไล่เฉดสีทับ
                  size: iconSize,
                ),
                if (isSelected) ...[
                  SizedBox(width: 6 * s),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white, // ใช้ขาวให้ Gradient วาดทับได้เต็มที่
                      fontWeight: FontWeight.w700,
                      fontSize: fontSize,
                      letterSpacing: 0.3,
                    ),
                  ),
                ]
              ],
            );

            if (!isSelected) return content;

            // ─── ใช้ ShaderMask เพื่อทำ Text Gradient ส้ม-ชมพู-ม่วง ตามภาพ Reference ─── //
            return ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFFEA8039), // ส้มซ้าย
                  Color(0xFFC95B6A), // ชมพูแสดตรงกลาง
                  Color(0xFF7438B0), // ม่วงขวา
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: content,
            );
          },
        ),
      ),
    );
  }

  /// ─── ปุ่มไอคอนแบบ Glass Bubble: เกือบใสสนิทเหมือน Reference ─── ///
  Widget _buildGlassBubbleNav(int index, IconData icon, double s, {bool hasNotification = false}) {
    final isSelected = widget.currentIndex == index;
    final iconSize = (22 * s).roundToDouble();
    final pad = (9 * s).roundToDouble();

    return GestureDetector(
      onTap: () => widget.onIndexChanged(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          // ─── เนื้อลูกแก้ว: ใสแทบมองทะลุ ─── //
          color: isSelected
              ? _activeBtnColor // ปุ่ม Active: ครีม ivory
              : Colors.white.withOpacity(0.08), // ปุ่มปกติ: ใสเกือบหมด แค่มีฝ้าเล็กน้อย
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.9)
                : Colors.white.withOpacity(0.35), // ขอบลูกแก้วจางๆ
            width: 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              icon,
              color: isSelected ? _activeIconColor : _defaultIconColor,
              size: iconSize,
            ),
            if (hasNotification)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withOpacity(0.35),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// ─── ปุ่ม + ตรงกลาง: ดาร์กสี charcoal + ไอคอนเขียวอ่อน ─── ///
  Widget _buildAddButton(double s) {
    final iconSize = (26 * s).roundToDouble();
    final pad = (10 * s).roundToDouble();

    return GestureDetector(
      onTap: widget.onAddPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: _darkBtnColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: _darkBtnIconColor.withOpacity(0.08),
              blurRadius: 12,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Icon(
          Icons.add,
          color: _darkBtnIconColor,
          size: iconSize,
        ),
      ),
    );
  }
}

/// ─── Custom Painter: วาดขอบกระจกไล่สีวนรอบมุม (Sweep Gradient) ─── ///
class _GlassEdgePainter extends CustomPainter {
  final double radius;
  _GlassEdgePainter({this.radius = 40});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // ─── 1. ขอบกระจกไล่สีวนรอบมุม (Sweep Gradient) ─── //
    final borderPaint = Paint()
      ..shader = const SweepGradient(
        center: Alignment.center,
        colors: [
          Color(0xBBD4878F), // ขวา: ชมพูพีช
          Color(0xBBB0B8D8), // ล่าง: ลาเวนเดอร์
          Color(0xBB88D8E8), // ซ้าย: ฟ้าไซยาน
          Color(0xBB8FD9C0), // บน: มิ้นท์เขียว
          Color(0xBBD4878F), // กลับมาชมพู
        ],
        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(rrect, borderPaint);

    // ─── 2. แสงสะท้อนด้านบน ─── //
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          Colors.white.withOpacity(0.50),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(rrect, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant _GlassEdgePainter oldDelegate) => oldDelegate.radius != radius;
}
