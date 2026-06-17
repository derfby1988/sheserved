import 'package:flutter/material.dart';

/// Map Material icon name string → IconData
IconData? _iconNameToIconData(String? name) {
  switch (name) {
    case 'face': return Icons.face;
    case 'face_retouching_natural': return Icons.face_retouching_natural;
    case 'remove_red_eye_outlined': return Icons.remove_red_eye_outlined;
    case 'hearing_outlined': return Icons.hearing_outlined;
    case 'record_voice_over_outlined': return Icons.record_voice_over_outlined;
    case 'compress': return Icons.compress;
    case 'accessibility_new': return Icons.accessibility_new;
    case 'horizontal_rule': return Icons.horizontal_rule;
    case 'monitor_heart_outlined': return Icons.monitor_heart_outlined;
    case 'fitness_center': return Icons.fitness_center;
    case 'favorite_border': return Icons.favorite_border;
    case 'restaurant_menu': return Icons.restaurant_menu;
    case 'adjust': return Icons.adjust;
    case 'radio_button_checked': return Icons.radio_button_checked;
    case 'pan_tool_alt_outlined': return Icons.pan_tool_alt_outlined;
    case 'water_drop_outlined': return Icons.water_drop_outlined;
    case 'watch_outlined': return Icons.watch_outlined;
    case 'trip_origin': return Icons.trip_origin;
    case 'back_hand_outlined': return Icons.back_hand_outlined;
    case 'directions_walk': return Icons.directions_walk;
    case 'directions_run': return Icons.directions_run;
    case 'lens_outlined': return Icons.lens_outlined;
    case 'linear_scale': return Icons.linear_scale;
    case 'align_vertical_bottom': return Icons.align_vertical_bottom;
    case 'radio_button_unchecked': return Icons.radio_button_unchecked;
    case 'run_circle_outlined': return Icons.run_circle_outlined;
    case 'linear_scale_outlined': return Icons.linear_scale_outlined;
    default: return null;
  }
}

class BodyMapChatBar extends StatelessWidget {
  final List<BodyPartChipData> bodyParts;
  final Map<String, int> patientMessageCount;
  final String? activeBodyPart;
  final ValueChanged<String?> onBodyPartSelected;

  const BodyMapChatBar({
    super.key,
    required this.bodyParts,
    required this.patientMessageCount,
    this.activeBodyPart,
    required this.onBodyPartSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (bodyParts.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: bodyParts.length + 1, // +1 for "ภาพรวม" clear chip
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            // "ภาพรวม" clear filter chip
            final isActive = activeBodyPart == null;
            return _buildChip(
              context,
              label: 'ภาพรวม',
              count: null,
              isActive: isActive,
              onTap: () => onBodyPartSelected(null),
            );
          }

          final part = bodyParts[index - 1];
          final count = patientMessageCount[part.key] ?? 0;
          final isActive = activeBodyPart == part.key;

          return Semantics(
            label: 'พูดคุยเกี่ยวกับ${part.label}, จำนวนข้อความ $count',
            selected: isActive,
            button: true,
            child: _buildChip(
              context,
              label: part.label,
              count: count,
              isActive: isActive,
              onTap: () => onBodyPartSelected(part.key),
              iconName: part.iconName,
            ),
          );
        },
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String label,
    required int? count,
    required bool isActive,
    required VoidCallback onTap,
    String? iconName,
  }) {
    final iconData = _iconNameToIconData(iconName);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.orange : Colors.grey.shade300,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconData != null) ...[
              Icon(iconData, size: 16, color: isActive ? Colors.white : Colors.orange.shade700),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.white : Colors.black87,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.orange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.orange : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BodyPartChipData {
  final String key;
  final String label;
  final String? iconName; // Material icon name (e.g. 'lens_outlined')

  const BodyPartChipData({
    required this.key,
    required this.label,
    this.iconName,
  });
}
