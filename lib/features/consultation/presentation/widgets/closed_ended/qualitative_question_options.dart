import 'package:flutter/material.dart';

import 'closed_ended_glass_primitives.dart';

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
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Center(
              heightFactor: 1,
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
                  shadows: [
                    Shadow(
                      color: const Color(0xFF0A1433).withValues(alpha: 0.45),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      builder: (context, child) {
        final t = glowAnimation.value;
        return Transform.scale(
          scale: isSelected ? 1 + t * 0.15 : 1.0,
          child: LitGlassSurface(
            borderRadius: 18,
            blurSigma: 22,
            fillOpacity: isSelected ? 0.14 : 0.07,
            accentColor: color,
            accentStrength: isSelected ? 0.34 : 0.12,
            glowOpacity: isSelected ? 0.25 + t * 0.3 : 0,
            rimWidth: 2.0,
            selected: isSelected,
            child: child!,
          ),
        );
      },
    );
  }
}
