import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MedicationTile extends StatelessWidget {
  final Map<String, dynamic> prescription;

  const MedicationTile({super.key, required this.prescription});

  @override
  Widget build(BuildContext context) {
    final created = prescription['issued_at'] != null
        ? DateFormat('dd MMM yyyy HH:mm')
            .format(DateTime.parse(prescription['issued_at']).toLocal())
        : '';
    final meds = (prescription['medications'] as List?) ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ออกเมื่อ $created',
            style: TextStyle(color: Colors.green.shade900, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ...meds.take(4).map((item) {
            final med = item as Map<String, dynamic>;
            final name = med['name'] ?? '-';
            final dose = med['dose'] ?? '';
            final freq = med['frequency'] ?? '';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('$name  $dose  $freq'),
            );
          }),
          if (prescription['notes'] != null) ...[
            const Divider(),
            Text('คำแนะนำ: ${prescription['notes']}'),
          ],
        ],
      ),
    );
  }
}
