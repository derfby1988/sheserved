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

/// Custom Painter for Ratio Circle (Online Providers vs Recipients)
class RatioCirclePainter extends CustomPainter {
  final double providerRatio; // 0.0 to 1.0
  final Color providerColor;
  final Color recipientColor;
  final double strokeWidth;
  final String providerLabel;
  final String recipientLabel;

  RatioCirclePainter({
    required this.providerRatio,
    required this.providerColor,
    required this.recipientColor,
    required this.providerLabel,
    required this.recipientLabel,
    this.strokeWidth = 10.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final providerPaint = Paint()
      ..color = providerColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final recipientPaint = Paint()
      ..color = recipientColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const gap = 0.15; // Gap between arcs in radians (about 8.5 degrees)
    const totalAvailableAngle = 2 * math.pi - (2 * gap);
    
    // Draw Provider arc (Top Half Focus)
    if (providerRatio > 0.05) {
      final sweepAngle = totalAvailableAngle * providerRatio;
      // Start from top-center and expand outwards symmetrically
      final startAngle = (-math.pi / 2) - (sweepAngle / 2);
      
      canvas.drawArc(rect, startAngle, sweepAngle, false, providerPaint);

      _drawCapCircle(canvas, center, radius, startAngle, providerColor);
      _drawCapCircle(canvas, center, radius, startAngle + sweepAngle, providerColor);

      if (providerLabel.isNotEmpty && providerRatio > 0.15) {
        _drawTextOnArc(canvas, providerLabel, radius, center, -math.pi / 2, Colors.white, strokeWidth);
      }
    }

    // Draw Recipient arc (Bottom Half Focus)
    if (providerRatio < 0.95) {
      final sweepAngleRecipient = totalAvailableAngle * (1 - providerRatio);
      // Start from bottom-center and expand outwards symmetrically
      final startAngleRecipient = (math.pi / 2) - (sweepAngleRecipient / 2);
      
      canvas.drawArc(rect, startAngleRecipient, sweepAngleRecipient, false, recipientPaint);

      _drawCapCircle(canvas, center, radius, startAngleRecipient, recipientColor);
      _drawCapCircle(canvas, center, radius, startAngleRecipient + sweepAngleRecipient, recipientColor);

      if (recipientLabel.isNotEmpty && (1 - providerRatio) > 0.15) {
        _drawTextOnArc(canvas, recipientLabel, radius, center, math.pi / 2, Colors.white, strokeWidth);
      }
    }
  }

  void _drawCapCircle(Canvas canvas, Offset center, double radius, double angle, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final x = center.dx + radius * math.cos(angle);
    final y = center.dy + radius * math.sin(angle);
    
    canvas.drawCircle(Offset(x, y), strokeWidth / 2, paint);
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

    // แยกกลุ่มตัวอักษรภาษาไทยให้พยัญชนะ สระ และวรรณยุกต์อยู่ด้วยกัน
    final List<String> charList = text.runes.map((r) => String.fromCharCode(r)).toList();
    // หมายเหตุ: เพื่อความแม่นยำสูงสุดในภาษาไทย เราจะพยายามจับกลุ่มตัวอักษรที่มีสระ/วรรณยุกต์ติดกัน
    final List<String> clusters = [];
    String currentCluster = '';
    
    // Logic พื้นฐานในการรวมวรรณยุกต์และสระในภาษาไทย
    for (int i = 0; i < text.length; i++) {
      int charCode = text.codeUnitAt(i);
      // ช่วงรหัสสระและวรรณยุกต์ไทย (บน/ล่าง)
      bool isThaiMark = (charCode >= 0x0E31 && charCode <= 0x0E3A) || // สระบน/ล่าง
                        (charCode >= 0x0E47 && charCode <= 0x0E4E);   // วรรณยุกต์
      
      if (isThaiMark && clusters.isNotEmpty) {
        clusters[clusters.length - 1] += text[i];
      } else {
        clusters.add(text[i]);
      }
    }

    const double fontSize = 11.0;
    // ปรับระยะห่างตามจำนวนกลุ่มตัวอักษร
    final double charAngleSpan = (fontSize * 0.85) / radius;
    final double totalTextAngle = clusters.length * charAngleSpan;
    
    double currentAngle = midAngle - (totalTextAngle / 2);

    // ตรวจสอบว่าเป็นส่วนล่างของวงกลมหรือไม่ (สำหรับกลับหัวตัวหนังสือให้อ่านง่าย)
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

      // คำนวณความเบี่ยงเบนของมุมเล็กน้อย (สำหรับสระ/วรรณยุกต์จะไม่เพิ่มระยะห่าง)
      double angle = currentAngle;
      
      // ถ้าเป็นส่วนล่าง เราจะหมุนข้อความ 180 องศาเพื่อไม่ให้กลับหัว
      if (isBottom) {
        // วาดสลับลำดับจากขวาไปซ้าย หรือหมุนตัวอักษรแต่ละตัว
        angle = midAngle + (midAngle - currentAngle);
      }

      final double x = center.dx + radius * math.cos(angle);
      final double y = center.dy + radius * math.sin(angle);

      canvas.save();
      canvas.translate(x, y);
      
      if (isBottom) {
        canvas.rotate(angle - math.pi / 2); // หมุนตัวอักษรยืนขึ้นสำหรับด้านล่าง
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
