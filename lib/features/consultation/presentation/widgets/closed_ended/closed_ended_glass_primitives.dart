import 'dart:ui';

import 'package:flutter/material.dart';

/// Phase 6.14 — shared glass-morphism primitives for the closed-ended
/// question UI. Purely visual; no feature state or persistence.
///
/// Principles (สอดคล้อง glass_card.dart, glassmorphism_button.dart):
///   1. BackdropFilter + ImageFilter.blur
///   2. Semi-transparent fill
///   3. Gradient overlay (inner shine)
///   4. Subtle border
///   5. Soft shadow
///   6. Rounded corners

/// Circular glass card — used as the radial question center.
class GlassCircleCard extends StatelessWidget {
  final double size;
  final double glassOpacity;
  final double blurSigma;
  final double borderOpacity;
  final double innerShineOpacity;
  final Color? borderColor;
  final Color? tintColor;
  final Color? shadowColor;
  final double? shadowBlur;
  final Widget child;

  const GlassCircleCard({
    super.key,
    required this.size,
    required this.child,
    this.glassOpacity = 0.10,
    this.blurSigma = 22,
    this.borderOpacity = 0.18,
    this.innerShineOpacity = 0.10,
    this.borderColor,
    this.tintColor,
    this.shadowColor,
    this.shadowBlur,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (shadowColor != null)
            BoxShadow(
              color: shadowColor!,
              blurRadius: shadowBlur ?? 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: glassOpacity * 0.6),
                      Colors.white.withValues(alpha: glassOpacity),
                      Colors.white.withValues(alpha: glassOpacity * 0.8),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  border: Border.all(
                    color:
                        borderColor ??
                        Colors.white.withValues(alpha: borderOpacity),
                    width: 0.8,
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: size * 0.18,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: innerShineOpacity),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              if (tintColor != null)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.2,
                      colors: [tintColor!, Colors.transparent],
                    ),
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded glass card — used for the question prompt (radial + compact).
class GlassRoundedCard extends StatelessWidget {
  final double width;
  final double? minHeight;
  final double glassOpacity;
  final double blurSigma;
  final double borderRadius;
  final Color? tintColor;
  final double tintStrength;
  final double shadowOpacity;
  final Widget child;

  const GlassRoundedCard({
    super.key,
    required this.width,
    required this.child,
    this.minHeight,
    this.glassOpacity = 0.08,
    this.blurSigma = 22,
    this.borderRadius = 18,
    this.tintColor,
    this.tintStrength = 0,
    this.shadowOpacity = 0.18,
  });

  @override
  Widget build(BuildContext context) {
    return LitGlassSurface(
      borderRadius: borderRadius,
      blurSigma: blurSigma,
      fillOpacity: glassOpacity,
      accentColor: tintColor,
      accentStrength: tintStrength,
      shadowOpacity: shadowOpacity,
      rimWidth: 2.2,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight ?? 0),
        child: SizedBox(width: width, child: child),
      ),
    );
  }
}

/// Lit glass surface — mimics a photographed glass tile:
///
///   outside : soft drop shadow + white bloom halo (+ accent glow if selected)
///   body    : very translucent fill, top-left diffuse wash, warm pink leak
///             bottom-right, cool cyan leak bottom-left, inner shadow along
///             bottom/right edges (glass thickness)
///   rim     : thick crisp gradient rim (brightest at top), diffuse inner rim
///             glow, inner bevel line, specular hotspots + top-edge glint
///
/// Lighting is drawn with painters (not stacked widgets) so each corner can be
/// lit independently and the dark shadow never bleeds through the glass.
class LitGlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final double fillOpacity;
  final Color? accentColor;
  final double accentStrength;
  final double glowOpacity;
  final double rimWidth;
  final double shadowOpacity;
  final bool selected;

  const LitGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 18,
    this.blurSigma = 22,
    this.fillOpacity = 0.08,
    this.accentColor,
    this.accentStrength = 0,
    this.glowOpacity = 0,
    this.rimWidth = 2,
    this.shadowOpacity = 0.20,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GlassHaloPainter(
        radius: borderRadius,
        shadowOpacity: shadowOpacity,
        accent: accentColor,
        glowOpacity: glowOpacity,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: CustomPaint(
            painter: _GlassBodyPainter(
              radius: borderRadius,
              fillOpacity: fillOpacity,
              accent: accentColor,
              accentStrength: accentStrength,
            ),
            foregroundPainter: _GlassRimPainter(
              radius: borderRadius,
              rimWidth: rimWidth,
              rimColor: selected && accentColor != null
                  ? Color.lerp(Colors.white, accentColor, 0.45)!
                  : Colors.white,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

RRect _glassRRect(Size size, double radius) => RRect.fromRectAndRadius(
  Offset.zero & size,
  Radius.circular(radius.clamp(0.0, size.shortestSide / 2)),
);

Path _outsideOf(RRect rrect, {double margin = 80}) => Path.combine(
  PathOperation.difference,
  Path()..addRect(rrect.outerRect.inflate(margin)),
  Path()..addRRect(rrect),
);

Color _clear(Color c) => c.withValues(alpha: 0);

class _GlassHaloPainter extends CustomPainter {
  final double radius;
  final double shadowOpacity;
  final Color? accent;
  final double glowOpacity;

  const _GlassHaloPainter({
    required this.radius,
    required this.shadowOpacity,
    required this.accent,
    required this.glowOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = _glassRRect(size, radius);
    canvas.save();
    canvas.clipPath(_outsideOf(rrect));

    if (shadowOpacity > 0) {
      canvas.drawRRect(
        rrect.shift(const Offset(0, 8)),
        Paint()
          ..color = const Color(0xFF050A1E).withValues(alpha: shadowOpacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }

    canvas.drawRRect(
      rrect.inflate(1),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.30),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.18),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rrect.outerRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    final glow = accent;
    if (glow != null && glowOpacity > 0) {
      canvas.drawRRect(
        rrect.inflate(3),
        Paint()
          ..color = glow.withValues(alpha: glowOpacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassHaloPainter old) =>
      old.radius != radius ||
      old.shadowOpacity != shadowOpacity ||
      old.accent != accent ||
      old.glowOpacity != glowOpacity;
}

class _GlassBodyPainter extends CustomPainter {
  final double radius;
  final double fillOpacity;
  final Color? accent;
  final double accentStrength;

  const _GlassBodyPainter({
    required this.radius,
    required this.fillOpacity,
    required this.accent,
    required this.accentStrength,
  });

  void _radial(
    Canvas canvas,
    Rect rect,
    Alignment center,
    double r,
    Color color,
  ) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: center,
          radius: r,
          colors: [color, _clear(color)],
        ).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = _glassRRect(size, radius);
    final d = size.shortestSide;

    // Base fill — barely-there white so the backdrop shows through.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: fillOpacity * 1.6),
            Colors.white.withValues(alpha: fillOpacity * 0.55),
            Colors.white.withValues(alpha: fillOpacity),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    final tint = accent;
    if (tint != null && accentStrength > 0) {
      _radial(
        canvas,
        rect,
        const Alignment(0, 1.25),
        1.15,
        tint.withValues(alpha: accentStrength),
      );
    }

    // Diffuse daylight wash from the top-left.
    _radial(
      canvas,
      rect,
      const Alignment(-0.95, -1.05),
      1.05,
      Colors.white.withValues(alpha: 0.22),
    );
    // Environment colour leaks.
    _radial(
      canvas,
      rect,
      const Alignment(1.05, 1.05),
      0.75,
      const Color(0xFFFFB3C8).withValues(alpha: 0.32),
    );
    _radial(
      canvas,
      rect,
      const Alignment(-1.05, 1.0),
      0.6,
      const Color(0xFFA3E6FF).withValues(alpha: 0.18),
    );

    // Inner shadow on bottom/right edges → reads as glass thickness.
    canvas.drawPath(
      _outsideOf(rrect, margin: 40).shift(Offset(-d * 0.02, -d * 0.035)),
      Paint()
        ..color = const Color(0xFF0A1433).withValues(alpha: 0.24)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          (d * 0.05).clamp(2.0, 10.0),
        ),
    );
  }

  @override
  bool shouldRepaint(_GlassBodyPainter old) =>
      old.radius != radius ||
      old.fillOpacity != fillOpacity ||
      old.accent != accent ||
      old.accentStrength != accentStrength;
}

class _GlassRimPainter extends CustomPainter {
  final double radius;
  final double rimWidth;
  final Color rimColor;

  const _GlassRimPainter({
    required this.radius,
    required this.rimWidth,
    required this.rimColor,
  });

  void _hotspot(Canvas canvas, Offset center, double r, double alpha) {
    if (r <= 0) return;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = _glassRRect(size, radius);
    final rect = rrect.outerRect;
    final d = size.shortestSide;
    final r = rrect.tlRadiusX;
    Color rim(double a) => rimColor.withValues(alpha: a);

    // Diffuse inner rim glow — light soaking into the glass from the edge.
    final diffuseW = (d * 0.09).clamp(4.0, 12.0);
    canvas.drawRRect(
      rrect.deflate(diffuseW / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = diffuseW
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [rim(0.40), rim(0.12), rim(0.08), rim(0.24)],
          stops: const [0.0, 0.4, 0.7, 1.0],
        ).createShader(rect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, diffuseW * 0.45),
    );

    // Crisp thick rim — brightest along the top, strong again at the bottom.
    canvas.drawRRect(
      rrect.deflate(rimWidth / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..shader = LinearGradient(
          begin: const Alignment(-0.3, -1),
          end: const Alignment(0.3, 1),
          colors: [rim(0.95), rim(0.62), rim(0.42), rim(0.80)],
          stops: const [0.0, 0.35, 0.7, 1.0],
        ).createShader(rect),
    );

    // Inner bevel line.
    canvas.drawRRect(
      rrect.deflate(rimWidth + 1.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = rim(0.22),
    );

    // Specular hotspots — main light top-right, secondary top-left.
    _hotspot(canvas, Offset(size.width - r * 0.55, r * 0.45), r * 0.95, 0.55);
    _hotspot(canvas, Offset(r * 0.5, r * 0.5), r * 0.6, 0.30);

    // Glint running along the top edge.
    final glintLength = size.width - r * 2;
    if (glintLength > 0) {
      final y = rimWidth * 1.6;
      canvas.drawLine(
        Offset(r, y),
        Offset(size.width - r, y),
        Paint()
          ..strokeWidth = 1.2
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.55),
              Colors.white.withValues(alpha: 0.75),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.45, 0.8, 1.0],
          ).createShader(Rect.fromLTWH(r, 0, glintLength, y * 2))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) =>
      old.radius != radius ||
      old.rimWidth != rimWidth ||
      old.rimColor != rimColor;
}

/// Glass icon button (close/back) — minimum 44×44 tap target.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 0.8,
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white.withValues(alpha: 0.8),
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass badge — e.g. expert name + avatar above the question.
class GlassBadge extends StatelessWidget {
  final String text;
  final String? avatarUrl;

  const GlassBadge({super.key, required this.text, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                backgroundImage: avatarUrl != null
                    ? NetworkImage(avatarUrl!)
                    : null,
                child: avatarUrl == null
                    ? Icon(
                        Icons.person,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.6),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'SukhumvitSet',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass action button — confirm/cancel inside dialogs.
class GlassActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isFilled;
  final Color? fillColor;
  final Widget? child;

  const GlassActionButton({
    super.key,
    required this.label,
    this.onTap,
    this.isFilled = false,
    this.fillColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isFilled
                  ? (fillColor ?? Colors.white).withValues(alpha: 0.30)
                  : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isFilled
                    ? (fillColor ?? Colors.white).withValues(alpha: 0.50)
                    : Colors.white.withValues(alpha: 0.20),
                width: 1,
              ),
            ),
            child: Center(
              child:
                  child ??
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(
                        alpha: isFilled ? 1.0 : 0.7,
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
