import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'neumorphic_inset.dart';
import 'neumorphic_theme.dart';

/// แถบเลื่อน (Slider) สไตล์ Neumorphic: รางจม (Inset) + หัวหมุดวงกลมนูน
///
/// **หลักการออกแบบ (Design Notes):**
/// - รางวาดด้วย [NeumorphicInsetPainter] ตัวเดียวกับ [NeumorphicInsetBox] เพื่อให้
///   ร่องจมมีมิติเหมือน component อื่นในระบบ (พื้นหลังรอบ widget ควรเป็น
///   [NeumorphicTheme.baseColor])
/// - หัวหมุดเป็นวงกลมนูนเงาสองทิศทางแบบเดียวกับปุ่มเลื่อนของ `NeumorphicSwitchTile`
///   และเปลี่ยนเป็นสี [activeColor] เมื่อค่ามากกว่า [min] (ถือว่า "เปิดใช้งาน")
/// - ยังคงเส้นสี [activeColor] ตามค่าที่เลือก จากจุดเริ่มเดินของหัวหมุดถึงหัวหมุด
/// - หัวหมุดที่ค่าต่ำสุด/สูงสุดจะไม่ชนขอบราง แต่อยู่ห่างจากขอบเท่ารัศมีปลายรางมน
///   (`trackHeight / 2`) เพื่อให้ concentric กับปลายรางและอ่านค่า 0/สูงสุดได้ชัด
/// - ใช้ `Slider` ของ Material เป็นตัวจัดการ gesture/semantics/RTL/divisions แล้ว
///   แทนที่เฉพาะการวาด (track/thumb/overlay/tick mark) ตำแหน่งหัวหมุดจึงตรงกับ
///   การลากเสมอโดยไม่ต้องคำนวณเอง
/// - ความสูงของ widget เท่ากับ [trackHeight] (หรือมากกว่าเล็กน้อยหากหัวหมุดใหญ่กว่า)
class NeumorphicSlider extends StatelessWidget {
  const NeumorphicSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.onChanged,
    this.label,
    this.activeColor = NeumorphicTheme.primaryBlue,
    this.trackHeight = 30,
    this.thumbRadius = 11,
    this.lineHeight = 6,
    this.semanticFormatterCallback,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;

  /// ข้อความบนป้ายลอยขณะลาก (ถ้าไม่ส่งจะไม่แสดงป้าย)
  final String? label;
  final Color activeColor;
  final double trackHeight;
  final double thumbRadius;
  final double lineHeight;
  final SemanticFormatterCallback? semanticFormatterCallback;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final clamped = value.clamp(min, max).toDouble();

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: trackHeight,
        trackShape: _NeumorphicSliderTrackShape(
          trackHeight: trackHeight,
          thumbRadius: thumbRadius,
          activeColor: activeColor,
          lineHeight: lineHeight,
          enabled: enabled,
        ),
        thumbShape: _NeumorphicSliderThumbShape(
          radius: thumbRadius,
          trackHeight: trackHeight,
          activeColor: activeColor,
          min: min,
          enabled: enabled,
        ),
        overlayShape: SliderComponentShape.noOverlay,
        tickMarkShape: SliderTickMarkShape.noTickMark,
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
        disabledActiveTrackColor: Colors.transparent,
        disabledInactiveTrackColor: Colors.transparent,
        valueIndicatorColor: activeColor,
        valueIndicatorTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Slider(
        value: clamped,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
        semanticFormatterCallback: semanticFormatterCallback,
      ),
    );
  }
}

/// รางของ [NeumorphicSlider]: วาดร่องจมเต็มความกว้าง แล้วทับด้วยเส้นสี
/// [activeColor] จากหัวรางถึงหัวหมุด.
class _NeumorphicSliderTrackShape extends SliderTrackShape {
  const _NeumorphicSliderTrackShape({
    required this.trackHeight,
    required this.thumbRadius,
    required this.activeColor,
    required this.lineHeight,
    required this.enabled,
  });

  final double trackHeight;
  final double thumbRadius;
  final Color activeColor;
  final double lineHeight;
  final bool enabled;

  /// ต้องเป็น false เพื่อให้ตำแหน่งหัวหมุดอิงกับ [getPreferredRect] ตรง ๆ
  /// (ถ้า true ทาง Material จะหักระยะรางเพิ่มเอง)
  @override
  bool get isRounded => false;

  double _topOf(RenderBox parentBox) =>
      (parentBox.size.height - trackHeight) / 2;

  /// ระยะจากขอบรางถึงจุดเริ่ม/สิ้นสุดที่หัวหมุดเดินได้
  ///
  /// ใช้รัศมีของหัวราง (ปลายมน) เป็นค่าตั้งต้น เพื่อให้หัวหมุดที่ค่าต่ำสุด/สูงสุด
  /// อยู่ concentric กับปลายรางและไม่ชนขอบ (ถ้าหัวหมุดใหญ่กว่ารัศมีหัวราง
  /// ก็ยังกันไม่ให้ล้นออกนอกขอบ)
  double get _edgeInset => math.max(thumbRadius, trackHeight / 2);

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackTop = offset.dy + _topOf(parentBox);
    return Rect.fromLTRB(
      offset.dx + _edgeInset,
      trackTop,
      offset.dx + parentBox.size.width - _edgeInset,
      trackTop + trackHeight,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final canvas = context.canvas;
    final double trackTop = offset.dy + _topOf(parentBox);
    final Rect grooveRect = Rect.fromLTRB(
      offset.dx,
      trackTop,
      offset.dx + parentBox.size.width,
      trackTop + trackHeight,
    );

    // ร่องจม: ใช้ painter ตัวเดียวกับ NeumorphicInsetBox
    canvas.save();
    canvas.translate(grooveRect.left, grooveRect.top);
    NeumorphicInsetPainter(
      borderRadius: trackHeight / 2,
    ).paint(canvas, grooveRect.size);
    canvas.restore();

    // เส้นแสดงค่าที่เลือก: จากจุดเริ่มเดินของหัวหมุดถึงหัวหมุด
    final double lineStart = grooveRect.left + _edgeInset;
    final double lineEnd = thumbCenter.dx;
    if (lineEnd - lineStart > 0.5) {
      canvas.drawLine(
        Offset(lineStart, grooveRect.center.dy),
        Offset(lineEnd, grooveRect.center.dy),
        Paint()
          ..color = activeColor.withValues(alpha: enabled ? 1 : 0.4)
          ..strokeWidth = lineHeight
          ..strokeCap = StrokeCap.round,
      );
    }
  }
}

/// หัวหมุดของ [NeumorphicSlider]: วงกลมนูนสองทิศทางแบบปุ่มเลื่อนของ
/// `NeumorphicSwitchTile` และเปลี่ยนเป็น [activeColor] เมื่อค่าเกิน [min].
class _NeumorphicSliderThumbShape extends SliderComponentShape {
  const _NeumorphicSliderThumbShape({
    required this.radius,
    required this.trackHeight,
    required this.activeColor,
    required this.min,
    required this.enabled,
  });

  final double radius;
  final double trackHeight;
  final Color activeColor;
  final double min;
  final bool enabled;

  static const double _depth = 2;
  static const double _blur = 4;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(math.max(radius + _depth, trackHeight / 2));

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final double t = enableAnimation.value.clamp(0.0, 1.0);
    final bool active = enabled && value > min;
    final Color body = active
        ? Color.lerp(NeumorphicTheme.baseColor, activeColor, t)!
        : NeumorphicTheme.baseColor;

    canvas.drawCircle(
      center.translate(_depth, _depth),
      radius,
      Paint()
        ..color = NeumorphicTheme.shadowDark.withValues(
          alpha: NeumorphicTheme.shadowDark.a * t,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _blur),
    );
    canvas.drawCircle(
      center.translate(-_depth, -_depth),
      radius,
      Paint()
        ..color = NeumorphicTheme.shadowLight.withValues(
          alpha: NeumorphicTheme.shadowLight.a * t,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _blur),
    );
    canvas.drawCircle(center, radius, Paint()..color = body);
  }
}
