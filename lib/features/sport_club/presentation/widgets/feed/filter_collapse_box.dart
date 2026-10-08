import 'package:flutter/material.dart';

/// Hides [child] while a feed is scrolled up: it slides up, fades out and —
/// when [collapseHeight] is true — gives its layout height back to the list.
///
/// Shared by the Find Buddies feed (pinned overlay bar, keeps its height so
/// the cards never jump) and the Book Court quick-filter row (in-flow row,
/// collapses its height so the list moves up) so both screens hide their
/// filters the same way.
class FilterCollapseBox extends StatelessWidget {
  static const Duration slideDuration = Duration(milliseconds: 280);
  static const Duration fadeDuration = Duration(milliseconds: 240);
  static const Curve curve = Curves.easeOutCubic;

  /// Slides up by 60% of its height while collapsed — enough to clear the
  /// row beneath without making the motion feel heavy.
  static const Offset hiddenOffset = Offset(0, -0.6);

  final bool collapsed;
  final Widget child;

  /// When true the box also shrinks to zero height while collapsed.
  final bool collapseHeight;

  const FilterCollapseBox({
    super.key,
    required this.collapsed,
    required this.child,
    this.collapseHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedSlide(
      duration: slideDuration,
      curve: curve,
      offset: collapsed ? hiddenOffset : Offset.zero,
      child: AnimatedOpacity(
        duration: fadeDuration,
        opacity: collapsed ? 0 : 1,
        child: child,
      ),
    );
    if (collapseHeight) {
      content = AnimatedAlign(
        alignment: Alignment.center,
        duration: slideDuration,
        curve: curve,
        heightFactor: collapsed ? 0 : 1,
        child: content,
      );
    }
    return ClipRect(
      child: IgnorePointer(
        ignoring: collapsed,
        child: ExcludeSemantics(excluding: collapsed, child: content),
      ),
    );
  }
}
