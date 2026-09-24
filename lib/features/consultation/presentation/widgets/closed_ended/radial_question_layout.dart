import 'dart:math' as math;

import 'package:flutter/material.dart';

class RadialQuestionLayout extends StatelessWidget {
  final Widget question;
  final int optionCount;
  final double optionSizeFactor;
  final Animation<double> entranceAnimation;
  final Widget? orbitRing;
  final Widget Function(BuildContext context, int index, double optionSize)
  optionBuilder;

  const RadialQuestionLayout({
    super.key,
    required this.question,
    required this.optionCount,
    required this.optionSizeFactor,
    required this.entranceAnimation,
    required this.optionBuilder,
    this.orbitRing,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        if (!side.isFinite || side <= 0) return const SizedBox.shrink();

        final optionSize = (side * optionSizeFactor)
            .clamp(48.0, 112.0)
            .toDouble();
        final radius = math
            .min(side * 0.32, side / 2 - optionSize / 2 - 4)
            .clamp(0.0, side / 2)
            .toDouble();

        return Center(
          child: SizedBox.square(
            dimension: side,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ?orbitRing,
                question,
                ...List.generate(optionCount, (index) {
                  // เริ่มจากด้านบน (-π/2) และกระจายรอบวง
                  final angle =
                      -math.pi / 2 + (2 * math.pi * index / optionCount);
                  final offset = Offset(
                    radius * math.cos(angle),
                    radius * math.sin(angle),
                  );
                  // Stagger delay: 100ms per option
                  final staggerInterval = optionCount > 1
                      ? Interval(
                          (index * 0.08).clamp(0.0, 0.6),
                          ((index * 0.08) + 0.4).clamp(0.0, 1.0),
                          curve: Curves.elasticOut,
                        )
                      : const Interval(0.0, 1.0, curve: Curves.elasticOut);

                  return AnimatedBuilder(
                    animation: entranceAnimation,
                    builder: (context, child) {
                      final progress = staggerInterval.transform(
                        entranceAnimation.value,
                      );
                      // Fly in from edge towards final position
                      final flyOffset = Offset(
                        offset.dx * (1 + (1 - progress) * 1.5),
                        offset.dy * (1 + (1 - progress) * 1.5),
                      );
                      return Transform.translate(
                        offset: Offset.lerp(flyOffset, offset, progress)!,
                        child: Transform.scale(
                          scale: progress,
                          child: Opacity(
                            opacity: progress.clamp(0.0, 1.0),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: SizedBox.square(
                      dimension: optionSize,
                      child: optionBuilder(context, index, optionSize),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
