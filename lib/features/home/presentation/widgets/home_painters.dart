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
    
    // 1. Background Track (subtle white ring — 3D base plate)
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Helper: Draw 3D arc with shadow + gradient + highlight layers
    void draw3DArc(double startAngle, double sweepAngle, Color color, 
        String label, double labelAngle) {
      if (sweepAngle < 0.02) return;
      
      // Layer 1: Drop Shadow (shifted down, blurred, darker)
      final shadowPaint = Paint()
        ..strokeWidth = strokeWidth + 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = color.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawArc(rect.translate(0, 3), startAngle, sweepAngle, false, shadowPaint);

      // Layer 2: Main arc with sweep gradient for 3D depth
      final mainPaint = Paint()
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      
      final baseOpacity = color.opacity;
      mainPaint.shader = ui.Gradient.sweep(
        center,
        [
          color.withOpacity(baseOpacity * 0.7), // Start slightly more transparent
          color,                                // Middle (100% of input opacity)
          color.withOpacity(baseOpacity * 0.9), // End slightly more transparent
        ],
        [0.0, 0.5, 1.0],
        TileMode.clamp,
        startAngle,
        startAngle + sweepAngle,
      );
      canvas.drawArc(rect, startAngle, sweepAngle, false, mainPaint);

      // Layer 3: Inner-edge highlight (thin bright line for 3D bevel)
      if (sweepAngle > 0.3) {
        final hlRadius = radius - strokeWidth * 0.28;
        final hlRect = Rect.fromCircle(center: center, radius: hlRadius);
        final hlPaint = Paint()
          ..strokeWidth = strokeWidth * 0.18
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withOpacity(0.35);
        canvas.drawArc(hlRect, startAngle + 0.08, sweepAngle - 0.16, false, hlPaint);
      }

      // Arc Label Text
      if (label.isNotEmpty) {
        final ratio = sweepAngle / totalAvailableAngle;
        if (ratio > 0.15) {
          _drawTextOnArc(canvas, label, radius, center, labelAngle, Colors.white, strokeWidth);
        }
      }
    }

    // 2. Provider Arc (top — golden yellow)
    if (providerRatio > 0.02) {
      final sweepAngle = totalAvailableAngle * providerRatio;
      final startAngle = (-math.pi / 2) - (sweepAngle / 2);
      draw3DArc(startAngle, sweepAngle, providerColor, providerLabel, -math.pi / 2);
    }

    // 3. Recipient Arc (bottom — soft blue)
    if (providerRatio < 0.98) {
      final sweepAngleRecipient = totalAvailableAngle * (1 - providerRatio);
      final startAngleRecipient = (math.pi / 2) - (sweepAngleRecipient / 2);
      draw3DArc(startAngleRecipient, sweepAngleRecipient, recipientColor, 
          recipientLabel, math.pi / 2);
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

    // Auto-calculate font size to fit within the ring's stroke band.
    // Thai vowels+tone marks can stack up to ~2.5x fontSize in height,
    // so we use 35% of strokeWidth to guarantee full glyphs stay inside.
    final double fontSize = (strokeWidth * 0.35).clamp(6.0, 12.0);
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
          height: 1.0, // tight line height to avoid Thai vowel clipping
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
      
      // Paint centered — use height/2 so above-baseline Thai vowels (vowels on top)
      // are included and don't clip at the outer edge of the stroke.
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
