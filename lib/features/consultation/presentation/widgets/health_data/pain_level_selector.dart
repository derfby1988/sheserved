import 'package:flutter/material.dart';

class PainLevelSelector extends StatelessWidget {
  final String? selectedPain;
  final ValueChanged<String>? onSelected;

  static const List<Map<String, dynamic>> painLevels = [
    {'label': 'ไม่มี', 'color': Color(0xFF4CAF50), 'icon': Icons.sentiment_very_satisfied},
    {'label': 'เล็กน้อย', 'color': Color(0xFF8BC34A), 'icon': Icons.sentiment_satisfied},
    {'label': 'ปานกลาง', 'color': Color(0xFFFFC107), 'icon': Icons.sentiment_neutral},
    {'label': 'มาก', 'color': Color(0xFFFF9800), 'icon': Icons.sentiment_dissatisfied},
    {'label': 'มากที่สุด', 'color': Color(0xFFF44336), 'icon': Icons.sentiment_very_dissatisfied},
  ];

  const PainLevelSelector({super.key, this.selectedPain, this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.healing, color: Colors.orange.shade600, size: 20),
            const SizedBox(width: 8),
            Text('ระดับความเจ็บปวดของคุณ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
          ]),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: painLevels.map((level) {
              final isSelected = selectedPain == level['label'].toString();
              final color = level['color'] as Color;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => onSelected?.call(level['label'].toString()),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? color : Colors.grey.shade200, width: isSelected ? 2 : 1),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(level['icon'] as IconData, color: isSelected ? color : Colors.grey.shade400, size: 24),
                          const SizedBox(height: 4),
                          Text(level['label'] as String, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? color : Colors.grey.shade500), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
