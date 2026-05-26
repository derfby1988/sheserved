import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class ActionButtonsWidget extends StatelessWidget {
  final bool isProvider;
  final bool readOnly;
  final VoidCallback onFinishPressed;
  final VoidCallback onVideoCallPressed;
  final VoidCallback onInfoPressed;

  const ActionButtonsWidget({
    super.key,
    required this.isProvider,
    required this.readOnly,
    required this.onFinishPressed,
    required this.onVideoCallPressed,
    required this.onInfoPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isProvider && !readOnly)
          TextButton.icon(
            onPressed: onFinishPressed,
            icon: const Icon(Icons.done_all, color: AppColors.primary, size: 18),
            label: const Text('จบงาน', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        if (!readOnly)
          IconButton(
            icon: const Icon(Icons.videocam_outlined, color: AppColors.primary),
            onPressed: onVideoCallPressed,
          ),
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.grey),
          onPressed: onInfoPressed,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
