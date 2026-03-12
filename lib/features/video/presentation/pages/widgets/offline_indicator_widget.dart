import 'package:flutter/material.dart';

class OfflineIndicatorWidget extends StatelessWidget {
  const OfflineIndicatorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red.withValues(alpha: 0.8),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 14, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'การเชื่อมต่อขัดข้อง - กำลังพยายามเชื่อมต่อใหม่...',
              style: TextStyle(
                fontFamily: 'SukhumvitSet',
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
