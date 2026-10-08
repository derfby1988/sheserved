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
  final double shadowWidthFactor;
  final double shadowHeightFactor;
  final double shadowOpacity;

  const CourtCardSlab({
    super.key,
    required this.child,
    this.level = 3,
    this.thickness = 12.0,
    this.opacity = 0.38,
    this.sheenBegin = const Alignment(-1.2, -1.0),
    this.sheenEnd = const Alignment(1.2, 1.0),
    this.shadowWidthFactor = 1.0,
    this.shadowHeightFactor = 1.0,
    this.shadowOpacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    const cornerRadius = 22.0;
    // Margins around the card:
    // Right margin leaves room for the extruded thickness wall
    final slabMarginLeft = 6.0;
    final slabMarginTop = 8.0;
    final slabMarginRight = thickness.clamp(2.0, 32.0) + 8.0;
    final slabMarginBottom = (16.0 * shadowHeightFactor).clamp(16.0, 36.0);

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
        shadowWidthFactor: shadowWidthFactor,
        shadowHeightFactor: shadowHeightFactor,
        shadowOpacity: shadowOpacity,
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
  final double shadowWidthFactor;
  final double shadowHeightFactor;
  final double shadowOpacity;

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
    this.shadowWidthFactor = 1.0,
    this.shadowHeightFactor = 1.0,
    this.shadowOpacity = 1.0,
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

  /// Seamless, photorealistic contact shadow and diffuse floor reflection matching
  /// the prototype image (prototype_bottom.png):
  /// - No sharp cutoffs or boxy drawRect edges anywhere (zero rectangular cuts)
  /// - Smooth Gaussian falloff in all directions (left, right, bottom)
  /// - Tight ambient occlusion contact crease directly along the base touchline
  /// - Soft frosted floor reflection mirroring the card, with warm red ambient
  ///   glow under the ruby cubes
  /// - Seamless optical continuity transitioning smoothly into the card's rounded corners
  void _paintGroundShadow(Canvas canvas, Rect frontRect, double thicknessX) {
    if (shadowOpacity <= 0.0) return;

    const cornerRadius = 22.0;
    final footprintWidth = frontRect.width + thicknessX;
    final centerX = frontRect.left + footprintWidth * 0.5;
    final bottom = frontRect.bottom;

    final wFactor = shadowWidthFactor.clamp(0.4, 2.5);
    final hFactor = shadowHeightFactor.clamp(0.3, 3.0);
    final opFactor = shadowOpacity.clamp(0.0, 2.0);

    // 1. Wide ambient ground shadow (บรรยากาศเงามืดรอบฐานแบบกระจายกว้าง นุ่มนวล)
    final ambientShadowRect = Rect.fromCenter(
      center: Offset(centerX, bottom + 8.0 * hFactor),
      width: footprintWidth * 1.06 * wFactor,
      height: 24.0 * hFactor,
    );
    final ambientShadowPaint = Paint()
      ..color = const Color(0xFF080D1A).withValues(alpha: (0.16 * opFactor).clamp(0.0, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14.0 * math.sqrt(hFactor));
    canvas.drawOval(ambientShadowRect, ambientShadowPaint);

    // 2. Main contact ground shadow (เงาหลักใต้แผ่นการ์ด นุ่มลึก)
    final mainShadowRect = Rect.fromCenter(
      center: Offset(centerX + 2.0, bottom + 5.0 * hFactor),
      width: footprintWidth * 0.94 * wFactor,
      height: 16.0 * hFactor,
    );
    final mainShadowPaint = Paint()
      ..color = const Color(0xFF060A14).withValues(alpha: (0.26 * opFactor).clamp(0.0, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8.0 * math.sqrt(hFactor));
    canvas.drawOval(mainShadowRect, mainShadowPaint);

    // 3. Ambient occlusion contact crease (รอยเงาสัมผัสแนบสนิทที่ผิวสัมผัสพื้น)
    //    Tapers naturally as the rounded corners curve upward off the ground.
    final creaseWidth = math.max(20.0, (frontRect.width - cornerRadius * 1.4 + thicknessX * 0.5) * wFactor);
    final creaseCenterX = frontRect.left + cornerRadius * 0.7 + (creaseWidth / wFactor) * 0.5;
    final creaseRect = Rect.fromCenter(
      center: Offset(creaseCenterX, bottom),
      width: creaseWidth,
      height: 4.5 * math.min(1.4, hFactor),
    );
    final creasePaint = Paint()
      ..color = const Color(0xFF03050A).withValues(alpha: (0.44 * opFactor).clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);
    canvas.drawOval(creaseRect, creasePaint);

    // 4. Soft frosted floor reflection (แสงสะท้อนบนพื้นโต๊ะจากแผ่นกระจก)
    //    Naturally elliptical with Gaussian blur — NO sharp edges, smoothly dissolves.
    final reflectWidth = math.max(20.0, (frontRect.width * 0.88 + thicknessX * 0.5) * wFactor);
    final reflectRect = Rect.fromCenter(
      center: Offset(centerX, bottom + 4.0 * hFactor),
      width: reflectWidth,
      height: 13.0 * hFactor,
    );
    final reflectPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: (0.22 * opFactor).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: (0.28 * opFactor).clamp(0.0, 1.0)),
          Color(0xFFFF6270).withValues(alpha: (0.26 * _levelFactor * opFactor).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.16, 0.52, 0.82, 1.0],
      ).createShader(reflectRect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.5 * math.sqrt(hFactor));
    canvas.drawOval(reflectRect, reflectPaint);

    // 5. Warm red ambient puddle under the 3D voxel cubes (แสงสีแดงส่องกระทบพื้น)
    final cubeGlowCenterX = frontRect.right - frontRect.width * 0.20;
    final cubeGlowRect = Rect.fromCenter(
      center: Offset(cubeGlowCenterX, bottom + 3.0 * hFactor),
      width: frontRect.width * 0.44 * wFactor,
      height: 10.0 * hFactor,
    );
    final cubeGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF2535).withValues(alpha: (0.26 * _levelFactor * opFactor).clamp(0.0, 1.0)),
          const Color(0xFFFF4552).withValues(alpha: (0.10 * _levelFactor * opFactor).clamp(0.0, 1.0)),
          const Color(0xFFFF2535).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(cubeGlowRect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5.0 * math.sqrt(hFactor));
    canvas.drawOval(cubeGlowRect, cubeGlowPaint);

    // 6. Hairline contact specular highlight along the card's flat bottom edge (เส้นประกายสัมผัสพื้น)
    //    Connects the card face and ground seamlessly without protruding past corners.
    final contactLineStart = frontRect.left + cornerRadius * 0.85;
    final contactLineEnd = frontRect.right + thicknessX * 0.35;
    if (contactLineEnd > contactLineStart) {
      final lineRect = Rect.fromLTRB(
        contactLineStart,
        bottom - 1.0,
        contactLineEnd,
        bottom + 1.0,
      );
      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: (0.65 * opFactor).clamp(0.0, 1.0)),
            Colors.white.withValues(alpha: (0.80 * opFactor).clamp(0.0, 1.0)),
            Colors.white.withValues(alpha: (0.50 * opFactor).clamp(0.0, 1.0)),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.15, 0.50, 0.85, 1.0],
        ).createShader(lineRect);
      canvas.drawLine(
        Offset(contactLineStart, bottom),
        Offset(contactLineEnd, bottom),
        linePaint,
      );
    }
  }

  /// Paints the visible thickness of the slab on the RIGHT side and BOTTOM
  /// (สันขอบความหนาทางขวาและล่างของการ์ด), simulating frosted acrylic depth
  /// with an inner shadow at the seam, matching the reference image.
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

    // --- Single seamless paint of the entire rim shape ---
    // rimPath is already the correct rounded-corner shape from Path.combine(difference).
    // No clips needed — the path itself defines clean boundaries at every corner.
    // A single diagonal gradient covers top→right specular + bottom warm-red reflection.
    final rimPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.white.withValues(alpha: 0.98),          // specular top-right
          const Color(0xFFECF0F8).withValues(alpha: 0.90), // polished glass
          const Color(0xFFD6DDE9).withValues(alpha: 0.80), // frosted body
          const Color(0xFFBFC9DA).withValues(alpha: 0.74), // depth
          const Color(0xFFFFD2D8).withValues(alpha: 0.78), // warm red glow (cube reflection)
        ],
        stops: const [0.0, 0.20, 0.50, 0.78, 1.0],
      ).createShader(backRRect.outerRect);
    canvas.drawPath(rimPath, rimPaint);

    // 3. Rear edge specular highlight line (ขอบสันกระจกด้านหลังสุด)
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

    // 4. Inner shadow along the seam — dark contact line where front face meets
    //    the extruded edge, visible in the reference as a soft dark crease
    //    (เงาตรงรอยต่อระหว่างหน้าการ์ดกับสันหนา)
    canvas.save();
    canvas.clipPath(rimPath);
    final seamShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF3A4556).withValues(alpha: 0.0),
          const Color(0xFF3A4556).withValues(alpha: 0.30),
          const Color(0xFF3A4556).withValues(alpha: 0.45),
          const Color(0xFF3A4556).withValues(alpha: 0.25),
          const Color(0xFF3A4556).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.15, 0.50, 0.85, 1.0],
      ).createShader(frontRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawRRect(frontRRect, seamShadow);
    canvas.restore();

    // 5. Seam specular highlight line along front face's edge — sits on top of
    //    the shadow, giving the bright-edge-over-dark-crease look of glass
    //    (ขอบขาวด้านในรอยต่อ)
    final seamStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.92),
          Colors.white.withValues(alpha: 0.50),
          const Color(0xFF8894A8).withValues(alpha: 0.30),
          Colors.white.withValues(alpha: 0.70),
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
      oldDelegate.marginBottom != marginBottom ||
      oldDelegate.shadowWidthFactor != shadowWidthFactor ||
      oldDelegate.shadowHeightFactor != shadowHeightFactor ||
      oldDelegate.shadowOpacity != shadowOpacity;
}
