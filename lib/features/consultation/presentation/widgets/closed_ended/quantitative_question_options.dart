import 'dart:ui';

import 'package:flutter/material.dart';

class QuantitativeQuestionOptions extends StatelessWidget {
  final List<Widget> options;
  final double spacing;

  const QuantitativeQuestionOptions({
    super.key,
    required this.options,
    this.spacing = 12,
  });

  // สี gradient สำหรับ quantitative (เขียว → เหลือง → แดง)
  static const _colors = [
    Color(0xFF4CAF50), // เขียว (ระดับต่ำ)
    Color(0xFF8BC34A),
    Color(0xFFCDDC39),
    Color(0xFFFFEB3B), // เหลือง (กลาง)
    Color(0xFFFFC107),
    Color(0xFFFF9800),
    Color(0xFFFF5722),
    Color(0xFFF44336), // แดง (ระดับสูง)
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
  ];

  static Color colorForIndex(int index, int count) {
    final ratio = count > 1 ? index / (count - 1) : 0.0;
    final colorIndex = (ratio * (_colors.length - 1)).round().clamp(
      0,
      _colors.length - 1,
    );
    return _colors[colorIndex];
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: spacing,
      runSpacing: spacing,
      children: options,
    );
  }
}

class QuantitativeAnswerOption extends StatelessWidget {
  final String label;
  final Color color;
  final double size;
  final bool isSelected;
  final Animation<double> glowAnimation;

  const QuantitativeAnswerOption({
    super.key,
    required this.label,
    required this.color,
    required this.size,
    required this.isSelected,
    required this.glowAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glowAnimation,
      builder: (context, child) {
        final scale = isSelected ? 1 + glowAnimation.value * 0.15 : 1.0;
        final glowOpacity = isSelected ? 0.25 + glowAnimation.value * 0.3 : 0.0;
        return Transform.scale(
          scale: scale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow behind selected option
              if (isSelected)
                Container(
                  width: size + 16,
                  height: size + 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: glowOpacity),
                        blurRadius: 24,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                ),
              // Glass option card
              ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(
                            alpha: isSelected ? 0.18 : 0.08,
                          ),
                          color.withValues(alpha: isSelected ? 0.18 : 0.08),
                          Colors.white.withValues(
                            alpha: isSelected ? 0.12 : 0.05,
                          ),
                        ],
                      ),
                      border: Border.all(
                        color: color.withValues(alpha: isSelected ? 0.5 : 0.25),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.08),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'SukhumvitSet',
                          fontSize: size * 0.32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: color.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
