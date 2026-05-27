import 'package:flutter/material.dart';

class HealthPermissionStatusBanner extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onViewData;

  const HealthPermissionStatusBanner({
    super.key,
    required this.request,
    this.onViewData,
  });

  @override
  Widget build(BuildContext context) {
    final status = request['status']?.toString() ?? 'pending';
    final Color bgColor;
    final Color textColor;
    final IconData icon;
    final String label;

    switch (status) {
      case 'granted':
        bgColor = const Color(0xFFE8F5E9);
        textColor = const Color(0xFF2E7D32);
        icon = Icons.check_circle_outline;
        label = 'ผู้ป่วยอนุมัติการเข้าถึงข้อมูลสุขภาพแล้ว';
        break;
      case 'denied':
        bgColor = const Color(0xFFFFEBEE);
        textColor = Colors.redAccent;
        icon = Icons.cancel_outlined;
        label = 'ผู้ป่วยปฏิเสธคำขอดูข้อมูลสุขภาพ';
        break;
      default:
        bgColor = Colors.orange.shade50;
        textColor = Colors.orange.shade800;
        icon = Icons.hourglass_top_rounded;
        label = 'รอผู้ป่วยตอบรับคำขอดูข้อมูลสุขภาพ...';
    }

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          if (status == 'granted')
            TextButton.icon(
              onPressed: onViewData,
              style: TextButton.styleFrom(foregroundColor: textColor),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('ดูข้อมูลที่อนุญาต'),
            ),
        ],
      ),
    );
  }
}
