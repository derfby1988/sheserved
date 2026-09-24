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

/// Rounded glass card — used for the compact question card and chips.
class GlassRoundedCard extends StatelessWidget {
  final double width;
  final double? minHeight;
  final double glassOpacity;
  final double blurSigma;
  final double borderOpacity;
  final double innerShineOpacity;
  final double borderRadius;
  final Color? borderColor;
  final Color? tintColor;
  final Color? shadowColor;
  final double? shadowBlur;
  final Widget child;

  const GlassRoundedCard({
    super.key,
    required this.width,
    required this.child,
    this.minHeight,
    this.glassOpacity = 0.10,
    this.blurSigma = 22,
    this.borderOpacity = 0.18,
    this.innerShineOpacity = 0.10,
    this.borderRadius = 18,
    this.borderColor,
    this.tintColor,
    this.shadowColor,
    this.shadowBlur,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          if (shadowColor != null)
            BoxShadow(
              color: shadowColor!,
              blurRadius: shadowBlur ?? 16,
              spreadRadius: 1,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: glassOpacity * 0.55),
                      Colors.white.withValues(alpha: glassOpacity),
                      Colors.white.withValues(alpha: glassOpacity * 0.85),
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
                height: (minHeight ?? 60) * 0.18,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(borderRadius),
                      topRight: Radius.circular(borderRadius),
                    ),
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
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      gradient: RadialGradient(
                        center: Alignment.topLeft,
                        radius: 1.15,
                        colors: [tintColor!, Colors.transparent],
                      ),
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
