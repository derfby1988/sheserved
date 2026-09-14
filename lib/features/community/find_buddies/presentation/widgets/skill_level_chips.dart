import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../domain/models/sport_skill_level.dart';

/// Interactive selector for choosing allowed skill levels when creating or editing a group.
class SkillLevelSelector extends StatelessWidget {
  final List<SportSkillLevel> availableLevels;
  final List<String> selectedLevels;
  final ValueChanged<List<String>> onLevelsChanged;
  final TextEditingController? noteController;

  const SkillLevelSelector({
    super.key,
    required this.availableLevels,
    required this.selectedLevels,
    required this.onLevelsChanged,
    this.noteController,
  });

  bool get isAllSelected =>
      selectedLevels.isEmpty || selectedLevels.contains('all');

  void _toggleLevel(String key) {
    if (key == 'all') {
      onLevelsChanged(['all']);
      return;
    }

    final current = List<String>.from(selectedLevels);
    current.remove('all');

    if (current.contains(key)) {
      current.remove(key);
      if (current.isEmpty) {
        onLevelsChanged(['all']);
      } else {
        onLevelsChanged(current);
      }
    } else {
      current.add(key);
      onLevelsChanged(current);
    }
  }

  void _showLevelDetailDialog(BuildContext context, SportSkillLevel level) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(level.labelTh, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (level.labelEn.isNotEmpty && level.labelEn != level.labelTh) ...[
              Text(
                'English: ${level.labelEn}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              level.description ?? 'ไม่มีคำอธิบายเพิ่มเติมสำหรับระดับนี้',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('เข้าใจแล้ว'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.stars_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            const Text(
              'ระดับฝีมือของผู้เล่นที่เปิดรับ',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const Spacer(),
            Text(
              isAllSelected ? 'เปิดรับทุกระดับ' : '${selectedLevels.length} ระดับที่เลือก',
              style: TextStyle(fontSize: 12, color: isAllSelected ? AppColors.primaryDark : Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'เลือกช่วงระดับที่เหมาะสม หรือเปิดรับทุกระดับเพื่อความสนุกร่วมกัน',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availableLevels.map((lvl) {
            final isSelected = lvl.key == 'all'
                ? isAllSelected
                : (!isAllSelected && selectedLevels.contains(lvl.key));

            return Tooltip(
              message: lvl.description ?? lvl.labelTh,
              child: FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(lvl.labelTh),
                    if (lvl.description != null && lvl.description!.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _showLevelDetailDialog(context, lvl),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: isSelected ? AppColors.primaryDark : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
                selected: isSelected,
                onSelected: (_) => _toggleLevel(lvl.key),
                selectedColor: AppColors.primary.withValues(alpha: 0.18),
                checkmarkColor: AppColors.primaryDark,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primaryDark : Colors.black87,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected ? AppColors.primaryDark : Colors.grey.shade300,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        if (noteController != null) ...[
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            maxLength: 150,
            decoration: InputDecoration(
              labelText: 'คำอธิบายระดับเพิ่มเติม (ตัวเลือก)',
              hintText: 'เช่น เน้นตีสนุก ไม่ซีเรียสผลแพ้ชนะ / ขอคนที่ตีเกมได้คล่อง',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ],
    );
  }
}

/// Compact badge for displaying skill level on group card or header.
class SkillLevelBadge extends StatelessWidget {
  final List<String>? targetSkillLevels;
  final List<SportSkillLevel>? availableLevels;
  final bool isCompact;

  const SkillLevelBadge({
    super.key,
    required this.targetSkillLevels,
    this.availableLevels,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final levels = availableLevels ?? kGenericSkillLevels;
    final summary = formatSkillLevelSummary(targetSkillLevels, levels);
    final isAll = summary == 'ทุกระดับ';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 8,
        vertical: isCompact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: isAll
            ? Colors.teal.shade50
            : AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAll
              ? Colors.teal.shade200
              : AppColors.primary.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAll ? Icons.all_inclusive_rounded : Icons.military_tech_rounded,
            size: isCompact ? 12 : 14,
            color: isAll ? Colors.teal.shade700 : AppColors.primaryDark,
          ),
          const SizedBox(width: 4),
          Text(
            summary,
            style: TextStyle(
              fontSize: isCompact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: isAll ? Colors.teal.shade800 : AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}
