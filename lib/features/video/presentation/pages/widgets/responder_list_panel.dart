import 'package:flutter/material.dart';

class ResponderListPanel extends StatelessWidget {
  final List<Map<String, dynamic>> responders;

  const ResponderListPanel({
    super.key,
    required this.responders,
  });

  @override
  Widget build(BuildContext context) {
    if (responders.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.people, color: Colors.blueAccent, size: 18),
              const SizedBox(width: 8),
              Text(
                'ผู้ตอบรับช่วยเหลือ (${responders.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...responders.map((r) => _buildResponderItem(r)).toList(),
        ],
      ),
    );
  }

  Widget _buildResponderItem(Map<String, dynamic> r) {
    final name = r['full_name'] ?? r['userName'] ?? 'อาสาสมัคร';
    final distance = r['distanceKm'] ?? 0.0;
    final eta = r['estimatedMinutes'] ?? 0;
    final status = r['status'] ?? 'en_route';

    Color statusColor;
    String statusText;
    switch (status) {
      case 'accepted':
      case 'en_route':
        statusColor = Colors.orange;
        statusText = 'กำลังเดินทาง';
        break;
      case 'arrived':
        statusColor = Colors.blue;
        statusText = 'ถึงที่เกิดเหตุ';
        break;
      default:
        statusColor = Colors.grey;
        statusText = status;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: statusColor.withOpacity(0.2),
            child: Icon(Icons.person, color: statusColor, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 10),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${distance.toStringAsFixed(1)} กม.',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Text(
                '~ $eta นาที',
                style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
