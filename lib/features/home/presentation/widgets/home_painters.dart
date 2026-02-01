import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Custom Painter for Dotted Circle Border
class DottedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  DottedCirclePainter({
    required this.color,
    this.strokeWidth = 3.0,
    this.dashWidth = 8.0,
    this.dashSpace = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Draw dotted circle
    final path = ui.Path();
    final circumference = 2 * math.pi * radius;
    final dashLength = dashWidth;
    final gapLength = dashSpace;
    final totalLength = dashLength + gapLength;
    final segments = (circumference / totalLength).floor();
    final angleStep = (2 * math.pi) / segments;

    for (int i = 0; i < segments; i++) {
      final startAngle = i * angleStep;
      final endAngle = startAngle + (dashLength / radius);
      
      path.addArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        endAngle - startAngle,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom Painter for Map Skeleton Grid Pattern
class MapSkeletonPainter extends CustomPainter {
  final Color color;
  
  MapSkeletonPainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    const tileSize = 50.0; // Size of each "tile" in the grid
    
    // Draw vertical lines
    for (double x = 0; x < size.width; x += tileSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
    
    // Draw horizontal lines
    for (double y = 0; y < size.height; y += tileSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
    
    // Draw some "road" lines to simulate map features
    final roadPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    
    // Diagonal road
    canvas.drawLine(
      Offset(0, size.height * 0.3),
      Offset(size.width, size.height * 0.7),
      roadPaint,
    );
    
    // Horizontal road
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      roadPaint,
    );
    
    // Vertical road
    canvas.drawLine(
      Offset(size.width * 0.4, 0),
      Offset(size.width * 0.4, size.height),
      roadPaint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
