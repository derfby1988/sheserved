import 'package:flutter/material.dart';

class EmergencyStatusBannerWidget extends StatelessWidget {
  final String status;
  final String message;
  final VoidCallback? onDismiss;

  const EmergencyStatusBannerWidget({
    super.key,
    required this.status,
    required this.message,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    IconData icon;

    switch (status) {
      case 'accepted':
        bgColor = Colors.orange.shade800;
        icon = Icons.airport_shuttle;
        break;
      case 'arrived':
        bgColor = Colors.blue.shade700;
        icon = Icons.location_on;
        break;
      case 'resolved':
        bgColor = Colors.green.shade700;
        icon = Icons.check_circle;
        break;
      default:
        bgColor = Colors.grey.shade800;
        icon = Icons.info;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
