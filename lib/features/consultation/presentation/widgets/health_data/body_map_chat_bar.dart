import 'package:flutter/material.dart';

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
  }) {
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

  const BodyPartChipData({
    required this.key,
    required this.label,
  });
}
