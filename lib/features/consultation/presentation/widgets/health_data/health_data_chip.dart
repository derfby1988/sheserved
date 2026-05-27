import 'package:flutter/material.dart';
import '../../../../../../core/constants/app_colors.dart';

class HealthDataChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const HealthDataChip({
    super.key,
    required this.label,
    required this.value,
    this.icon = Icons.info_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: AppColors.primary),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      backgroundColor: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      side: BorderSide(color: Colors.grey.shade300),
    );
  }
}
