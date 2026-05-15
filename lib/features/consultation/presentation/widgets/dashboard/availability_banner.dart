import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';

class AvailabilityBanner extends StatelessWidget {
  final String status;
  const AvailabilityBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final isBusy = status == 'busy';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isBusy
            ? AppColors.warning.withOpacity(0.2)
            : AppColors.success.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBusy
              ? AppColors.warning.withOpacity(0.5)
              : AppColors.success.withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isBusy ? AppColors.warning : AppColors.success,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isBusy
                ? '🔴 สถานะ: ไม่ว่าง (กำลังให้บริการ)'
                : '🟢 สถานะ: พร้อมรับงาน',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

