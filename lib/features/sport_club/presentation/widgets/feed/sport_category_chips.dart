import 'package:flutter/material.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/services/auth_service.dart';

/// Label for a sport chip: optional emoji icon + name.
/// Also used by [GroupCard] for the sport pill on each card.
class SportChipLabel extends StatelessWidget {
  final String? icon;
  final String label;

  const SportChipLabel({super.key, this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null && icon!.isNotEmpty) ...[
          Text(icon!, style: emojiTextStyle(context)),
          const SizedBox(width: 4),
        ],
        Text(label),
      ],
    );
  }
}

/// Horizontal row of sport filter chips (ทั้งหมด + one per sport).
class SportCategoryChips extends StatelessWidget {
  final List<Map<String, dynamic>> sports;
  final String? selectedSportId;
  final Set<String> myCreatedSportIds;
  final void Function(String? id, bool selected) onSportSelected;

  const SportCategoryChips({
    super.key,
    required this.sports,
    required this.selectedSportId,
    required this.myCreatedSportIds,
    required this.onSportSelected,
  });

  Widget _buildChip(
    BuildContext context,
    String? id,
    String label, {
    String? icon,
  }) {
    final isSelected = selectedSportId == id;
    final isMyCreated = id != null && myCreatedSportIds.contains(id);
    final borderColor = isMyCreated
        ? Colors.blue.shade100
        : Colors.grey.shade300;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: SportChipLabel(icon: icon, label: label),
        selected: isSelected,
        onSelected: (selected) => onSportSelected(id, selected),
        selectedColor: Colors.blue.shade100,
        checkmarkColor: Colors.blue,
        shape: StadiumBorder(
          side: BorderSide(color: borderColor, width: isMyCreated ? 2.0 : 1.0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildChip(context, null, 'ทั้งหมด', icon: '🏅'),
          ...sports.map(
            (s) => _buildChip(
              context,
              s['id']?.toString(),
              s['name_th']?.toString() ?? 'กีฬา',
              icon: s['icon']?.toString(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular "+" button next to the sport chips that navigates to the
/// sport-proposal page.
class AddSportFab extends StatelessWidget {
  const AddSportFab({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.only(left: 4, right: 8),
      child: InkWell(
        onTap: () async {
          if (AuthService.instance.currentUser == null) {
            await Navigator.pushNamed(
              context,
              '/login',
              arguments: {'returnAfterLogin': true},
            );
            if (!context.mounted) return;
            if (AuthService.instance.currentUser == null) return;
          }
          Navigator.pushNamed(context, '/community/sport-club/sport/propose');
        },
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.teal,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.teal, width: 1.5),
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
