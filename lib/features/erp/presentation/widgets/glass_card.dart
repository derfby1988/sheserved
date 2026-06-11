import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dashboard_theme.dart';
import '../providers/dashboard_theme_provider.dart';

/// Widget พื้นฐานสำหรับแก้วโปร่งใส (Glassmorphism)
/// ใช้ได้ทั้ง Sidebar, Cards, Dialogs
class GlassCard extends ConsumerWidget {
  final Widget child;
  final double borderRadius;
  final GlassSection section;
  final Color? tintColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BoxBorder? customBorder;
  final List<BoxShadow>? customShadows;

  const GlassCard({
    Key? key,
    required this.child,
    required this.section,
    this.borderRadius = 20,
    this.tintColor,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.customBorder,
    this.customShadows,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(dashboardThemeProvider).theme;
    if (theme == null) {
      // Fallback: ไม่มี theme → ใช้ solid color
      return Container(
        width: width,
        height: height,
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.25),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: Colors.white.withOpacity(0.35), width: 2),
        ),
        child: child,
      );
    }

    final rawOpacity = theme.getOpacityFor(section);
    final opacity = rawOpacity.clamp(0.15, 0.50);
    final blur = theme.glassBlurLevel.toDouble();
    final isDark = theme.isDarkMode;

    final baseColor = isDark ? Colors.black : Colors.white;
    final surfaceTint = isDark ? baseColor : (tintColor ?? baseColor);

    // Base gradient (เนื้อแก้ว)
    final glassGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(surfaceTint, Colors.white, 0.25)!.withOpacity(opacity * 0.55),
        Color.lerp(surfaceTint, Colors.white, 0.15)!.withOpacity(opacity),
        Color.lerp(surfaceTint, Colors.white, 0.08)!.withOpacity(opacity * 0.85),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    // Shadow ชัดขึ้น
    final shadows = customShadows ?? [
      BoxShadow(
        color: isDark
            ? Colors.black.withOpacity(0.5)
            : Colors.black.withOpacity(0.12),
        blurRadius: blur + 8,
        spreadRadius: 2,
        offset: const Offset(0, 4),
      ),
    ];

    return RepaintBoundary(
      child: Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: shadows,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Stack(
              children: [
                // Layer 1: Base glass gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: glassGradient,
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.2)
                          : Colors.white.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                ),
                // Layer 2: Inner shine (ด้านบนสว่าง)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: (height ?? 80) * 0.35,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(isDark ? 0.12 : 0.35),
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(borderRadius),
                        topRight: Radius.circular(borderRadius),
                      ),
                    ),
                  ),
                ),
                // Layer 2.5: Soft tint glow for natural pastel cards
                if (!isDark && tintColor != null)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(borderRadius),
                        gradient: RadialGradient(
                          center: Alignment.topLeft,
                          radius: 1.15,
                          colors: [
                            tintColor!.withOpacity(0.18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                // Layer 3: Content
                Container(
                  padding: padding,
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
