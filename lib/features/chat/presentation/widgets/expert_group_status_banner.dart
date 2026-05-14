import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/chat_models.dart';
import '../../../../services/service_locator.dart';

class ExpertGroupStatusBanner extends StatelessWidget {
  final ChatRoom room;
  final bool isProvider;
  final VoidCallback? onAbandon;

  const ExpertGroupStatusBanner({
    Key? key,
    required this.room,
    required this.isProvider,
    this.onAbandon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (room.roomType != 'consultation') return const SizedBox.shrink();

    // In a real app, check if provider is assigned or if the room is active
    // For now, if there is more than 1 participant, assume doctor joined.
    // Or we can check if there's any participant with doctor role (requires more data)
    final isDoctorJoined = room.participantIds.length > 1;

    if (!isDoctorJoined) {
      return Container(
        color: Colors.orange.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.hourglass_empty, color: Colors.orange),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '⏳ รอแพทย์รับงาน',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.green.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '✅ แพทย์รับงานแล้ว',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            ),
          ),
          if (isProvider && room.isActive)
            TextButton(
              onPressed: onAbandon,
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('สละสิทธิ์'),
            ),
        ],
      ),
    );
  }
}
