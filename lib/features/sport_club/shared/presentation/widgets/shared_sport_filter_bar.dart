import 'package:flutter/material.dart';

import 'package:sheserved/features/sport_club/presentation/widgets/feed/sport_category_chips.dart';

/// Shared sport-selection row for the Sports Hub.
///
/// One implementation reused by Find Buddies, Book Court and Find Coach so
/// every page offers the same sport options, the same selection state and
/// the same `sportId`. Pages must not build a second sport row on top of
/// this bar.
class SharedSportFilterBar extends StatelessWidget {
  final List<Map<String, dynamic>> sports;
  final String? selectedSportId;
  final Set<String> myCreatedSportIds;
  final void Function(String? id, bool selected) onSportSelected;
  final Widget? trailing;

  const SharedSportFilterBar({
    super.key,
    required this.sports,
    required this.selectedSportId,
    required this.onSportSelected,
    this.myCreatedSportIds = const {},
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SportCategoryChips(
            sports: sports,
            selectedSportId: selectedSportId,
            myCreatedSportIds: myCreatedSportIds,
            onSportSelected: onSportSelected,
          ),
        ),
        ?trailing,
      ],
    );
  }
}
