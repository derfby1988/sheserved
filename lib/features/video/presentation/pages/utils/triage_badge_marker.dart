import 'dart:ui';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/triage_models.dart';

class TriageBadgeMarker {
  static Future<Uint8List> generateBadgeBitmap(TriageSummary summary) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(120, 40);
    const padding = 4.0;

    final parts = <_BadgePart>[];
    if (summary.deceased > 0) parts.add(_BadgePart('⚫${summary.deceased}', 0xFF000000));
    if (summary.critical > 0) parts.add(_BadgePart('🔴${summary.critical}', 0xFFFF0000));
    if (summary.urgent > 0) parts.add(_BadgePart('🟡${summary.urgent}', 0xFFFFD600));
    if (summary.nonUrgent > 0) parts.add(_BadgePart('🟢${summary.nonUrgent}', 0xFF00C853));
    if (summary.white > 0) parts.add(_BadgePart('⚪${summary.white}', 0xFFFFFFFF));

    if (parts.isEmpty) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(8),
        ),
        Paint()..color = Colors.grey[300]!,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    double totalWidth = 0;
    for (final part in parts) {
      textPainter.text = TextSpan(
        text: part.text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      );
      textPainter.layout();
      totalWidth += textPainter.width + padding * 2;
    }

    final bgWidth = math.min(totalWidth + 8, size.width);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, bgWidth, size.height),
        const Radius.circular(8),
      ),
      Paint()
        ..color = const Color(0xCC000000)
        ..style = PaintingStyle.fill,
    );

    double offsetX = 4;
    for (final part in parts) {
      textPainter.text = TextSpan(
        text: part.text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(offsetX, (size.height - textPainter.height) / 2));
      offsetX += textPainter.width + padding * 2;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}

class _BadgePart {
  final String text;
  final int color;
  _BadgePart(this.text, this.color);
}
