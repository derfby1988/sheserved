import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';

class AvailabilityToggleButton extends StatelessWidget {
  final String status;
  final VoidCallback onToggle;
  const AvailabilityToggleButton({
    required this.status,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isBusy = status == 'busy';
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isBusy
              ? AppColors.warning.withOpacity(0.25)
              : AppColors.success.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isBusy
                ? AppColors.warning.withOpacity(0.6)
                : Colors.white.withOpacity(0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBusy ? Icons.do_not_disturb_rounded : Icons.circle,
              size: 10,
              color: isBusy ? AppColors.warning : AppColors.success,
            ),
            const SizedBox(width: 5),
            Text(
              isBusy ? 'ไม่ว่าง' : 'ว่าง',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

