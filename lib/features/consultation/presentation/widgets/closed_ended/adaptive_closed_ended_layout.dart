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
  final AdaptiveClosedEndedLayoutBuilder builder;

  const AdaptiveClosedEndedLayout({
    super.key,
    required this.questionText,
    required this.options,
    required this.builder,
  });

  static bool canUseRadialLayout({
    required Size size,
    required String questionText,
    required List<String> options,
    required double textScale,
  }) {
    if (!size.width.isFinite || !size.height.isFinite) return false;
    if (size.width < 360 || size.height < 560) return false;
    if (size.width / size.height > 2) return false;
    if (options.isEmpty || options.length > 5) return false;
    if (questionText.length > 10 ||
        options.any((option) => option.length > 12)) {
      return false;
    }
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
