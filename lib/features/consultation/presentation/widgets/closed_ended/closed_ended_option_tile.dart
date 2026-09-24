import 'package:flutter/material.dart';

/// Phase 6.14 — shared tap target / semantics wrapper for answer options.
///
/// Wraps a quantitative or qualitative option widget with a ≥44×44 hit
/// target and screen-reader semantics. No persistence or feature state.
class ClosedEndedOptionTile extends StatelessWidget {
  final int index;
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget child;

  const ClosedEndedOptionTile({
    super.key,
    required this.index,
    required this.label,
    required this.isSelected,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'ตัวเลือกที่ ${index + 1}: $label',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: child,
        ),
      ),
    );
  }
}
