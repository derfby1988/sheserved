import 'package:flutter/material.dart';

/// การ์ดที่รองรับการปัดซ้ายเพื่อซ่อน/ลบรายการ — ใช้ร่วมกันได้ทุก feature
///
/// แนวทางการใช้งาน (แนวทางเดียวกับ notification panel / toast):
/// ```dart
/// SwipeToDismissCard(
///   key: ValueKey('item_${item.id}'), // แยก state ต่อรายการ
///   onDismissed: () => _deleteItem(item),
///   child: MyCard(item: item),
/// )
/// ```
///
/// - ปัดซ้ายเกิน [dismissThreshold] หรือด้วยความเร็วเกิน [dismissVelocity]
///   → เรียก [onDismissed] (ผู้ใช้เป็นคนจัดการ action ลบ/ซ่อน/mark read)
/// - ปัดไม่ถึงเกณฑ์ → การ์ดเด้งกลับตำแหน่งเดิม
/// - ใช้ GestureDetector แนวนอนโดยตรง ไม่ขัดกับการเลื่อนแนวตั้งของ ListView
class SwipeToDismissCard extends StatefulWidget {
  /// ตัวการ์ดที่ต้องการให้ปัดซ้ายได้
  final Widget child;

  /// เรียกเมื่อปัดซ้ายสำเร็จ — ผู้ใช้จัดการ action ของ feature นั้นเอง
  final VoidCallback onDismissed;

  /// ระยะปัดขั้นต่ำ (px) ที่ถือว่า dismiss — ค่าเริ่มต้น -80
  final double dismissThreshold;

  /// ความเร็วปัดขั้นต่ำ (px/s) ที่ถือว่า dismiss — ค่าเริ่มต้น -500
  final double dismissVelocity;

  /// รัศมีมุมของพื้นหลังตอนปัด — ให้ตรงกับมุมการ์ด (ค่าเริ่มต้น 18)
  final double backgroundRadius;

  /// พื้นหลังที่เผยออกตอนปัด — ถ้าไม่ระบุใช้ค่าเริ่มต้น (แดง + ไอคอนลบ)
  final Widget? background;

  const SwipeToDismissCard({
    super.key,
    required this.child,
    required this.onDismissed,
    this.dismissThreshold = -80,
    this.dismissVelocity = -500,
    this.backgroundRadius = 18,
    this.background,
  });

  @override
  State<SwipeToDismissCard> createState() => _SwipeToDismissCardState();
}

class _SwipeToDismissCardState extends State<SwipeToDismissCard> {
  double _dragOffset = 0;

  void _onDragUpdate(DragUpdateDetails details) {
    if (!mounted) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(-1000.0, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!mounted) return;
    // รีเซ็ตก่อนเสมอ — ถ้า dismiss สำเร็จ widget จะถูก unmount เอง
    setState(() => _dragOffset = 0);
    final shouldDismiss =
        _dragOffset < widget.dismissThreshold ||
        details.velocity.pixelsPerSecond.dx < widget.dismissVelocity;
    if (shouldDismiss) widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        children: [
          Positioned.fill(
            child:
                widget.background ??
                _SwipeDismissBackground(radius: widget.backgroundRadius),
          ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// พื้นหลังค่าเริ่มต้น — ไอคอนลบชิดขวา โทนแดง
class _SwipeDismissBackground extends StatelessWidget {
  final double radius;

  const _SwipeDismissBackground({required this.radius});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.redAccent.withValues(alpha: isDark ? 0.28 : 0.20),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.delete_outline_rounded,
        color: Colors.redAccent.withValues(alpha: isDark ? 0.9 : 0.8),
        size: 22,
      ),
    );
  }
}
