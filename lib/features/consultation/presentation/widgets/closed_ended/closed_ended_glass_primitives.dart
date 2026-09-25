import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

export 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

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
