import 'package:flutter/material.dart';

import 'closed_ended_glass_primitives.dart';

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
    final labelText = Text(
      label,
      style: TextStyle(
        fontFamily: 'SukhumvitSet',
        fontSize: size * 0.38,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        shadows: [
          Shadow(
            color: const Color(0xFF0A1433).withValues(alpha: 0.45),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
          Shadow(
            color: color.withValues(alpha: isSelected ? 0.9 : 0.45),
            blurRadius: isSelected ? 14 : 10,
          ),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: glowAnimation,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: labelText),
      ),
      builder: (context, child) {
        final t = glowAnimation.value;
        return Transform.scale(
          scale: isSelected ? 1 + t * 0.15 : 1.0,
          child: LitGlassSurface(
            borderRadius: size * 0.26,
            blurSigma: 20,
            fillOpacity: isSelected ? 0.14 : 0.07,
            accentColor: color,
            accentStrength: isSelected ? 0.36 : 0.16,
            glowOpacity: isSelected ? 0.35 + t * 0.35 : 0,
            rimWidth: (size * 0.03).clamp(1.6, 3.0),
            selected: isSelected,
            child: child!,
          ),
        );
      },
    );
  }
}
