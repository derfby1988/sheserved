import 'package:flutter/material.dart';

class RibbonBookmark extends StatelessWidget {
  final bool isBookmarked;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final Color? activeColor;
  final Color? inactiveColor;

  const RibbonBookmark({
    super.key,
    required this.isBookmarked,
    this.onTap,
    this.width = 20,
    this.height = 28,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        size: Size(width, height),
        painter: RibbonBookmarkPainter(
          isBookmarked: isBookmarked,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
        ),
      ),
    );
  }
}

class RibbonBookmarkPainter extends CustomPainter {
  final bool isBookmarked;
  final Color? activeColor;
  final Color? inactiveColor;

  RibbonBookmarkPainter({
    required this.isBookmarked,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isBookmarked 
          ? (activeColor ?? const Color(0xFFFFD700)) 
          : (inactiveColor ?? Colors.white.withOpacity(0.5))
      ..style = isBookmarked ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.75)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant RibbonBookmarkPainter oldDelegate) {
    return oldDelegate.isBookmarked != isBookmarked;
  }
}
