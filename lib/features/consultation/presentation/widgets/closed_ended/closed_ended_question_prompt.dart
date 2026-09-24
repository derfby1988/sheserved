import 'package:flutter/material.dart';

import 'closed_ended_glass_primitives.dart';

/// Phase 6.14 — question prompt card for the patient answer UI.
///
/// Purely presentational: renders the question text (and quiz icon) in either
/// a circular card (center of the radial layout) or a rounded card (compact
/// scroll layout). No options, no persistence.
class ClosedEndedQuestionPrompt extends StatelessWidget {
  final String questionText;

  /// Diameter for [ClosedEndedQuestionPrompt.circular].
  final double size;

  /// Card width for [ClosedEndedQuestionPrompt.compact].
  final double width;

  final bool circular;
  final Animation<double>? pulseAnimation;

  const ClosedEndedQuestionPrompt.circular({
    super.key,
    required this.questionText,
    required this.size,
    this.pulseAnimation,
  }) : width = 0,
       circular = true;

  const ClosedEndedQuestionPrompt.compact({
    super.key,
    required this.questionText,
    required this.width,
  }) : size = 0,
       circular = false,
       pulseAnimation = null;

  @override
  Widget build(BuildContext context) {
    if (circular) {
      final compact = size < 80;
      final showIcon = size >= 96;
      final card = SizedBox(
        width: size,
        height: size,
        child: GlassRoundedCard(
          width: size,
          minHeight: size,
          borderRadius: size * 0.24,
          glassOpacity: 0.09,
          blurSigma: 24,
          shadowOpacity: 0.24,
          child: Padding(
            padding: EdgeInsets.all(compact ? 8 : (size < 112 ? 10 : 16)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showIcon) ...[
                  Icon(
                    Icons.quiz_rounded,
                    size: size < 112 ? 18 : 22,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  SizedBox(height: size < 112 ? 4 : 8),
                ],
                Text(
                  questionText,
                  textAlign: TextAlign.center,
                  maxLines: compact ? 2 : (size < 112 ? 3 : 4),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'SukhumvitSet',
                    fontSize: compact ? 11 : (size < 112 ? 12 : 14),
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: compact ? 1.25 : 1.4,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.40),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final pulse = pulseAnimation;
      if (pulse == null) return card;
      return AnimatedBuilder(
        animation: pulse,
        builder: (_, _) {
          final scale = 1.0 + (pulse.value * 0.03);
          return Transform.scale(scale: scale, child: card);
        },
      );
    }

    return GlassRoundedCard(
      width: width,
      minHeight: 112,
      glassOpacity: 0.08,
      blurSigma: 20,
      borderRadius: 20,
      tintColor: const Color(0xFF00BCD4),
      tintStrength: 0.08,
      shadowOpacity: 0.16,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.quiz_rounded,
              size: width < 320 ? 18 : 22,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              questionText,
              textAlign: TextAlign.center,
              softWrap: true,
              style: const TextStyle(
                fontFamily: 'SukhumvitSet',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
