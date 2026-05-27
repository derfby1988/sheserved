import 'package:flutter/material.dart';
import 'health_data_chip.dart';
import 'weight_history_card.dart';

class GeneralSectionContent extends StatelessWidget {
  final Map<String, dynamic> general;

  const GeneralSectionContent({super.key, required this.general});

  @override
  Widget build(BuildContext context) {
    final profile = general['profile'] as Map<String, dynamic>?;
    final healthInfo = general['health_info'] as Map<String, dynamic>?;
    final weightHistory = (general['weight_history'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];

    final chips = <Widget>[];

    void addChip(String label, dynamic value, {IconData icon = Icons.info}) {
      if (value == null) return;
      chips.add(HealthDataChip(label: label, value: value.toString(), icon: icon));
    }

    addChip(
      'ส่วนสูง',
      healthInfo?['height'] != null ? '${healthInfo!['height']} ซม.' : null,
      icon: Icons.height,
    );
    addChip('BMI', healthInfo?['bmi'], icon: Icons.scale);
    addChip('คะแนนสุขภาพ', healthInfo?['health_score'], icon: Icons.favorite);

    final emergencyContact = general['emergency_contact'];
    final emergencyPhone = general['emergency_phone'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (profile != null)
          Text(
            '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
        if (weightHistory.isNotEmpty) ...[
          const SizedBox(height: 12),
          WeightHistoryCard(weightHistory: weightHistory),
        ],
        if (emergencyContact != null || emergencyPhone != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ผู้ติดต่อฉุกเฉิน',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                ),
                if (emergencyContact != null) Text('ชื่อ: $emergencyContact'),
                if (emergencyPhone != null) Text('โทร: $emergencyPhone'),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
