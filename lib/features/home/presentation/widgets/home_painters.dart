import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Custom Painter for Dotted Circle Border
class DottedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double rotationOffset; // New: allow external rotation

  DottedCirclePainter({
    required this.color,
    this.strokeWidth = 3.0,
    this.dashWidth = 8.0,
    this.dashSpace = 4.0,
    this.rotationOffset = 0.0,
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
      final startAngle = (i * angleStep) + rotationOffset;
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
  bool shouldRepaint(covariant DottedCirclePainter oldDelegate) => 
      oldDelegate.rotationOffset != rotationOffset || oldDelegate.color != color;
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

/// Custom Painter for Ratio Circle (Online Providers vs Recipients)
class RatioCirclePainter extends CustomPainter {
  final double providerRatio; // 0.0 to 1.0
  final Color providerColor;
  final Color recipientColor;
  final double strokeWidth;
  final String providerLabel;
  final String recipientLabel;
  final bool showGlow;

  RatioCirclePainter({
    required this.providerRatio,
    required this.providerColor,
    required this.recipientColor,
    required this.providerLabel,
    required this.recipientLabel,
    this.strokeWidth = 10.0,
    this.showGlow = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth * 1.5) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    const gap = 0.15; // Gap between arcs in radians
    const totalAvailableAngle = 2 * math.pi - (2 * gap);
    
    // 1. Draw Background Track (Dimmer version)
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.05)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // 2. Draw Arc Glow (Shadow Layer)
    if (showGlow) {
      final glowPaint = Paint()
        ..strokeWidth = strokeWidth * 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      if (providerRatio > 0.02) {
        final sweepAngle = totalAvailableAngle * providerRatio;
        final startAngle = (-math.pi / 2) - (sweepAngle / 2);
        glowPaint.color = providerColor.withOpacity(0.3);
        canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
      }

      if (providerRatio < 0.98) {
        final sweepAngleRecipient = totalAvailableAngle * (1 - providerRatio);
        final startAngleRecipient = (math.pi / 2) - (sweepAngleRecipient / 2);
        glowPaint.color = recipientColor.withOpacity(0.3);
        canvas.drawArc(rect, startAngleRecipient, sweepAngleRecipient, false, glowPaint);
      }
    }

    // 3. Draw Main Arcs with Gradients
    final providerPaint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (providerRatio > 0.02) {
      final sweepAngle = totalAvailableAngle * providerRatio;
      final startAngle = (-math.pi / 2) - (sweepAngle / 2);
      
      providerPaint.shader = ui.Gradient.sweep(
        center,
        [
          providerColor.withOpacity(0.6),
          providerColor,
          providerColor.withOpacity(0.6),
        ],
        [0.0, 0.5, 1.0],
        TileMode.clamp,
        startAngle,
        startAngle + sweepAngle,
      );
      
      canvas.drawArc(rect, startAngle, sweepAngle, false, providerPaint);

      if (providerLabel.isNotEmpty && providerRatio > 0.15) {
        _drawTextOnArc(canvas, providerLabel, radius, center, -math.pi / 2, Colors.white, strokeWidth);
      }
    }

    final recipientPaint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (providerRatio < 0.98) {
      final sweepAngleRecipient = totalAvailableAngle * (1 - providerRatio);
      final startAngleRecipient = (math.pi / 2) - (sweepAngleRecipient / 2);
      
      recipientPaint.shader = ui.Gradient.sweep(
        center,
        [
          recipientColor.withOpacity(0.6),
          recipientColor,
          recipientColor.withOpacity(0.6),
        ],
        [0.0, 0.5, 1.0],
        TileMode.clamp,
        startAngleRecipient,
        startAngleRecipient + sweepAngleRecipient,
      );

      canvas.drawArc(rect, startAngleRecipient, sweepAngleRecipient, false, recipientPaint);

      if (recipientLabel.isNotEmpty && (1 - providerRatio) > 0.15) {
        _drawTextOnArc(canvas, recipientLabel, radius, center, math.pi / 2, Colors.white, strokeWidth);
      }
    }
  }

  void _drawTextOnArc(
    Canvas canvas, 
    String text, 
    double radius, 
    Offset center, 
    double midAngle, 
    Color color,
    double strokeWidth,
  ) {
    if (text.isEmpty) return;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    final List<String> clusters = [];
    for (int i = 0; i < text.length; i++) {
        int charCode = text.codeUnitAt(i);
        bool isThaiMark = (charCode >= 0x0E31 && charCode <= 0x0E3A) || 
                          (charCode >= 0x0E47 && charCode <= 0x0E4E);
        
        if (isThaiMark && clusters.isNotEmpty) {
          clusters[clusters.length - 1] += text[i];
        } else {
          clusters.add(text[i]);
        }
    }

    const double fontSize = 11.0;
    final double charAngleSpan = (fontSize * 0.85) / radius;
    final double totalTextAngle = clusters.length * charAngleSpan;
    
    double currentAngle = midAngle - (totalTextAngle / 2);
    bool isBottom = midAngle > 0 && midAngle < math.pi;

    for (int i = 0; i < clusters.length; i++) {
      textPainter.text = TextSpan(
        text: clusters[i],
        style: TextStyle(
          fontFamily: 'SukhumvitSet',
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          height: 1.0,
          shadows: [
            Shadow(color: Colors.black.withOpacity(0.4), blurRadius: 4),
          ],
        ),
      );
      textPainter.layout();

      double angle = currentAngle;
      if (isBottom) {
        angle = midAngle + (midAngle - currentAngle);
      }

      final double x = center.dx + radius * math.cos(angle);
      final double y = center.dy + radius * math.sin(angle);

      canvas.save();
      canvas.translate(x, y);
      
      if (isBottom) {
        canvas.rotate(angle - math.pi / 2);
      } else {
        canvas.rotate(angle + math.pi / 2);
      }
      
      textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      canvas.restore();

      currentAngle += charAngleSpan;
    }
  }

  @override
  bool shouldRepaint(covariant RatioCirclePainter oldDelegate) {
    return oldDelegate.providerRatio != providerRatio;
  }
}
