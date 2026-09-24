import 'package:flutter/material.dart';

enum ClosedEndedLayoutMode { radial, compact }

typedef AdaptiveClosedEndedLayoutBuilder =
    Widget Function(
      BuildContext context,
      BoxConstraints constraints,
      ClosedEndedLayoutMode mode,
    );

class AdaptiveClosedEndedLayout extends StatelessWidget {
  final String questionText;
  final List<String> options;
  final double radialTopInset;
  final double radialBottomInset;
  final AdaptiveClosedEndedLayoutBuilder builder;

  const AdaptiveClosedEndedLayout({
    super.key,
    required this.questionText,
    required this.options,
    this.radialTopInset = 0,
    this.radialBottomInset = 0,
    required this.builder,
  });

  static bool canUseRadialLayout({
    required Size size,
    required String questionText,
    required List<String> options,
    required double textScale,
    double radialTopInset = 0,
    double radialBottomInset = 0,
  }) {
    if (!size.width.isFinite || !size.height.isFinite) return false;
    final radialHeight = size.height - radialTopInset - radialBottomInset;
    if (!radialHeight.isFinite || size.width < 320 || radialHeight < 200) {
      return false;
    }
    if (size.width / radialHeight > 2) return false;
    if (options.isEmpty || options.length > 5) return false;
    if (questionText.characters.length > 10 ||
        options.any((option) => option.characters.length > 12)) {
      return false;
    }
    final minimumRadialHeight =
        options.any((option) => option.characters.length > 8)
        ? 320
        : options.any((option) => option.characters.length > 3)
        ? 240
        : 200;
    if (radialHeight < minimumRadialHeight) return false;
    return textScale <= 1.3;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final mode =
            canUseRadialLayout(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              questionText: questionText,
              options: options,
              textScale: textScale,
              radialTopInset: radialTopInset,
              radialBottomInset: radialBottomInset,
            )
            ? ClosedEndedLayoutMode.radial
            : ClosedEndedLayoutMode.compact;

        return KeyedSubtree(
          key: ValueKey('closed-ended-${mode.name}-layout'),
          child: builder(context, constraints, mode),
        );
      },
    );
  }
}
