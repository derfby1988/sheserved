import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HistoryTile extends StatelessWidget {
  final Map<String, dynamic> note;

  const HistoryTile({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
    final createdAt = note['created_at'];
    final created = createdAt != null
        ? DateFormat('dd MMM yyyy HH:mm')
            .format(DateTime.parse(createdAt).toLocal())
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'บันทึกเมื่อ $created',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          if (note['chief_complaint'] != null) ...[
            const SizedBox(height: 6),
            Text('อาการสำคัญ: ${note['chief_complaint']}'),
          ],
          if (note['diagnosis'] != null) ...[
            const SizedBox(height: 4),
            Text('การวินิจฉัย: ${note['diagnosis']}'),
          ],
          if (note['treatment_plan'] != null) ...[
            const SizedBox(height: 4),
            Text('แผนการรักษา: ${note['treatment_plan']}'),
          ],
          if (note['recommendations'] != null) ...[
            const SizedBox(height: 4),
            Text('คำแนะนำ: ${note['recommendations']}'),
          ],
        ],
      ),
    );
  }
}
