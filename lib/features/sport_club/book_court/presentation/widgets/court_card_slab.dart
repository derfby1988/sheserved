import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Renders a thick, photorealistic 3D acrylic/frosted glass slab matching the prototype:
/// - Prominent visible extruded glass thickness on the RIGHT wall (สันขอบความหนาทางขวาของการ์ด)
/// - Translucent frosted acrylic front face with backdrop blur (ความโปร่งใส)
/// - Radiant internal red ambient glow originating from the 3D cube stack
/// - Studio softbox diagonal specular sheen across the surface
/// - Ambient occlusion contact shadow and floor reflection at the base
class CourtCardSlab extends StatelessWidget {
  final Widget child;
  final int level;
  final double thickness;
  final double opacity;
  final Alignment sheenBegin;
  final Alignment sheenEnd;

  const CourtCardSlab({
    super.key,
    required this.child,
    this.level = 3,
    this.thickness = 12.0,
    this.opacity = 0.38,
    this.sheenBegin = const Alignment(-1.2, -1.0),
    this.sheenEnd = const Alignment(1.2, 1.0),
  });

  @override
  Widget build(BuildContext context) {
    const cornerRadius = 22.0;
    // Margins around the card:
    // Right margin leaves room for the extruded thickness wall
    final slabMarginLeft = 6.0;
    final slabMarginTop = 8.0;
    final slabMarginRight = thickness.clamp(2.0, 32.0) + 8.0;
    final slabMarginBottom = 16.0;

    return CustomPaint(
      painter: CourtCardSlabPainter(
        level: level,
        thickness: thickness,
        opacity: opacity,
        sheenBegin: sheenBegin,
        sheenEnd: sheenEnd,
        marginLeft: slabMarginLeft,
        marginTop: slabMarginTop,
        marginRight: slabMarginRight,
        marginBottom: slabMarginBottom,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          slabMarginLeft,
          slabMarginTop,
          slabMarginRight,
          slabMarginBottom,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(cornerRadius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: child,
          ),
        ),
      ),
    );
  }
}

class CourtCardSlabPainter extends CustomPainter {
  final int level;
  final double thickness;
  final double opacity;
  final Alignment sheenBegin;
  final Alignment sheenEnd;
  final double marginLeft;
  final double marginTop;
  final double marginRight;
  final double marginBottom;

  const CourtCardSlabPainter({
    required this.level,
    this.thickness = 12.0,
    this.opacity = 0.38,
    this.sheenBegin = const Alignment(-1.2, -1.0),
    this.sheenEnd = const Alignment(1.2, 1.0),
    this.marginLeft = 6.0,
    this.marginTop = 8.0,
    this.marginRight = 20.0,
    this.marginBottom = 16.0,
  });

  double get _levelFactor => (level.clamp(1, 5)) / 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final frontRect = Rect.fromLTWH(
      marginLeft,
      marginTop,
      math.max(10.0, size.width - marginLeft - marginRight),
      math.max(10.0, size.height - marginTop - marginBottom),
    );

    const cornerRadius = 22.0;
    final frontRRect = RRect.fromRectAndRadius(
      frontRect,
      const Radius.circular(cornerRadius),
    );
    final frontPath = Path()..addRRect(frontRRect);

    // 3D Glass Slab: The card is angled so the RIGHT wall is facing the viewer.
    // The back face is shifted to the RIGHT (+X) and slightly UP (-Y).
    final thicknessX = thickness.clamp(2.0, 32.0);
    final thicknessY = -thicknessX * 0.20;
    final backRect = frontRect.shift(Offset(thicknessX, thicknessY));
    final backRRect = RRect.fromRectAndRadius(
      backRect,
      const Radius.circular(cornerRadius),
    );
    final backPath = Path()..addRRect(backRRect);

    // 1. Soft contact shadow & ground reflection beneath slab
    _paintGroundShadow(canvas, frontRect, thicknessX);

    // 2. Visible extruded glass thickness wall on the RIGHT (สันขอบความหนาทางขวาของการ์ด)
    _paintExtrudedRightRim(canvas, frontPath, backPath, frontRRect, backRRect, frontRect);

    // 3. Translucent frosted front face with internal red ambient glow and sheen (ความโปร่งใส)
    _paintFrostedFrontFace(canvas, frontPath, frontRRect, frontRect);

    // 4. Polished glass chamfer and rim light highlights
    _paintGlassRimHighlights(canvas, frontRRect, frontRect);
  }

  /// Soft dark contact shadow directly where the slab touches the floor,
  /// plus a subtle ground mirror reflection.
  void _paintGroundShadow(Canvas canvas, Rect frontRect, double thicknessX) {
    final totalWidth = frontRect.width + thicknessX * 0.8;
    final centerX = frontRect.left + totalWidth * 0.5;

    // Ambient occlusion crease right under the base
    final creaseRect = Rect.fromCenter(
      center: Offset(centerX, frontRect.bottom + 4),
      width: totalWidth * 0.92,
      height: 8.0,
    );
    final creasePaint = Paint()
      ..color = const Color(0xFF0F141F).withValues(alpha: 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawOval(creaseRect, creasePaint);

    // Wide soft ground shadow
    final shadowRect = Rect.fromCenter(
      center: Offset(centerX + 4, frontRect.bottom + 12),
      width: totalWidth * 0.98,
      height: 20.0,
    );
    final shadowPaint = Paint()
      ..color = const Color(0xFF1B2232).withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawOval(shadowRect, shadowPaint);

    // Floor reflection: mirror glow of bottom rim
    final reflectRect = Rect.fromLTWH(
      frontRect.left + 8,
      frontRect.bottom + 2,
      totalWidth - 16,
      14,
    );
    final reflectPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(reflectRect);
    canvas.drawRect(reflectRect, reflectPaint);
  }

  /// Paints the visible thickness of the slab on the RIGHT side (สันขอบความหนาทางขวาของการ์ด).
  void _paintExtrudedRightRim(
    Canvas canvas,
    Path frontPath,
    Path backPath,
    RRect frontRRect,
    RRect backRRect,
    Rect frontRect,
  ) {
    // The rim is the area of the back plate that extends outside the front plate.
    final rimPath = Path.combine(PathOperation.difference, backPath, frontPath);

    // 1. Polished clear acrylic/glass facet: vertical refraction gradient
    final rimPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.98), // Bright specular highlight at top-right curve
          const Color(0xFFE8EDF6).withValues(alpha: 0.90), // Polished glass upper facet
          const Color(0xFFCAD5E5).withValues(alpha: 0.78), // Translucent body
          const Color(0xFFB4C2D6).withValues(alpha: 0.72), // Glass refraction tone
          const Color(0xFFFFD2D8).withValues(alpha: 0.80), // Warm red glow reflection from cubes at bottom
        ],
        stops: const [0.0, 0.20, 0.55, 0.80, 1.0],
      ).createShader(backRRect.outerRect);
    canvas.drawPath(rimPath, rimPaint);

    // 2. Rear edge specular highlight line (ขอบสันกระจกด้านหลังสุด)
    final rearStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.98),
          Colors.white.withValues(alpha: 0.85),
          Colors.white.withValues(alpha: 0.50),
          Colors.white.withValues(alpha: 0.92),
        ],
        stops: const [0.0, 0.30, 0.70, 1.0],
      ).createShader(backRRect.outerRect);
    canvas.save();
    canvas.clipPath(rimPath);
    canvas.drawRRect(backRRect, rearStroke);
    canvas.restore();

    // 3. Seam line along front face's right edge (รอยต่อระหว่างหน้าการ์ดกับสันหนา)
    final seamStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.90),
          Colors.white.withValues(alpha: 0.45),
          const Color(0xFF8894A8).withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.75),
        ],
        stops: const [0.0, 0.30, 0.70, 1.0],
      ).createShader(frontRect);
    canvas.drawRRect(frontRRect, seamStroke);
  }

  /// Paints the translucent frosted front face, internal red glow, and surface sheen.
  void _paintFrostedFrontFace(
    Canvas canvas,
    Path frontPath,
    RRect frontRRect,
    Rect frontRect,
  ) {
    // 1. Translucent frosted acrylic/glass base (ความโปร่งใส)
    // Controlled by opacity slider: lets background show through while retaining glass frosting!
    final effectiveOpacity = opacity.clamp(0.05, 1.0);
    final facePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: (effectiveOpacity * 1.25).clamp(0.05, 1.0)),
          Colors.white.withValues(alpha: (effectiveOpacity * 0.90).clamp(0.03, 0.95)),
          const Color(0xFFF0F4FA).withValues(alpha: (effectiveOpacity * 0.75).clamp(0.02, 0.90)),
          const Color(0xFFFFECEF).withValues(alpha: (effectiveOpacity * 0.85).clamp(0.04, 0.95)),
        ],
        stops: const [0.0, 0.35, 0.70, 1.0],
      ).createShader(frontRect);
    canvas.drawRRect(frontRRect, facePaint);

    canvas.save();
    canvas.clipRRect(frontRRect);

    // 2. Internal Red Ambient Glow: radiated outward from the 3D cube stack area
    final glowCenterX = frontRect.right - frontRect.width * 0.22;
    final glowCenterY = frontRect.top + frontRect.height * 0.38;
    final glowCenter = Offset(glowCenterX, glowCenterY);
    final glowRadius = math.min(frontRect.width, frontRect.height) * 0.85;

    final redGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF2535).withValues(alpha: 0.45 * _levelFactor),
          const Color(0xFFFF4552).withValues(alpha: 0.22 * _levelFactor),
          const Color(0xFFFF2535).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius));
    canvas.drawCircle(glowCenter, glowRadius, redGlowPaint);

    // Warm light bleed downward towards the stepper track
    final groundGlowRect = Rect.fromCenter(
      center: Offset(glowCenterX, frontRect.bottom - 18),
      width: frontRect.width * 0.50,
      height: 38,
    );
    final groundGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF303E).withValues(alpha: 0.25 * _levelFactor),
          const Color(0xFFFF303E).withValues(alpha: 0.0),
        ],
      ).createShader(groundGlowRect);
    canvas.drawOval(groundGlowRect, groundGlowPaint);

    // 3. Studio softbox diagonal specular sheen across the face
    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: sheenBegin,
        end: sheenEnd,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.32),
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.15, 0.35, 0.55, 0.75],
      ).createShader(frontRect);
    canvas.drawRect(frontRect, sheenPaint);

    // 4. Subtle inner chamfer glow
    final innerStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.95),
          Colors.white.withValues(alpha: 0.35),
          const Color(0xFFFFB3B8).withValues(alpha: 0.45),
        ],
        stops: const [0.0, 0.60, 1.0],
      ).createShader(frontRect);
    canvas.drawRRect(frontRRect, innerStrokePaint);

    canvas.restore();
  }

  /// High-specular rim lights along the front and top-left edges of the acrylic slab.
  void _paintGlassRimHighlights(
    Canvas canvas,
    RRect frontRRect,
    Rect frontRect,
  ) {
    // Front edge crisp highlight
    final frontHighlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.98),
          Colors.white.withValues(alpha: 0.65),
          Colors.white.withValues(alpha: 0.25),
          Colors.white.withValues(alpha: 0.85),
        ],
        stops: const [0.0, 0.35, 0.70, 1.0],
      ).createShader(frontRect);
    canvas.drawRRect(frontRRect, frontHighlight);
  }

  @override
  bool shouldRepaint(covariant CourtCardSlabPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.thickness != thickness ||
      oldDelegate.opacity != opacity ||
      oldDelegate.sheenBegin != sheenBegin ||
      oldDelegate.sheenEnd != sheenEnd ||
      oldDelegate.marginLeft != marginLeft ||
      oldDelegate.marginTop != marginTop ||
      oldDelegate.marginRight != marginRight ||
      oldDelegate.marginBottom != marginBottom;
}
