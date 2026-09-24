import 'dart:ui';

import 'package:flutter/material.dart';

class QualitativeQuestionOptions extends StatelessWidget {
  final List<Widget> options;
  final double spacing;

  const QualitativeQuestionOptions({
    super.key,
    required this.options,
    this.spacing = 12,
  });

  // สี teal shades สำหรับ qualitative
  static const _colors = [
    Color(0xFF00897B),
    Color(0xFF00796B),
    Color(0xFF00695C),
    Color(0xFF00BFA5),
    Color(0xFF1DE9B6),
    Color(0xFF64FFDA),
    Color(0xFF26A69A),
    Color(0xFF4DB6AC),
    Color(0xFF80CBC4),
    Color(0xFFB2DFDB),
  ];

  static Color colorForIndex(int index) => _colors[index % _colors.length];

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

class QualitativeAnswerOption extends StatelessWidget {
  final String label;
  final Color color;
  final double width;
  final double minHeight;
  final bool isSelected;
  final bool compact;
  final Animation<double> glowAnimation;

  const QualitativeAnswerOption({
    super.key,
    required this.label,
    required this.color,
    required this.width,
    required this.minHeight,
    required this.isSelected,
    required this.compact,
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
                  width: width + 16,
                  height: compact ? minHeight + 16 : width + 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
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
              Container(
                width: width,
                constraints: BoxConstraints(minHeight: minHeight),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: isSelected ? 0.16 : 0.07),
                      color.withValues(alpha: isSelected ? 0.16 : 0.07),
                      Colors.white.withValues(alpha: isSelected ? 0.12 : 0.05),
                    ],
                  ),
                  border: Border.all(
                    color: color.withValues(alpha: isSelected ? 0.42 : 0.18),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.06),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Center(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          softWrap: true,
                          maxLines: compact ? null : 3,
                          overflow: compact
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'SukhumvitSet',
                            fontSize: compact ? 14 : 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.3,
                          ),
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
