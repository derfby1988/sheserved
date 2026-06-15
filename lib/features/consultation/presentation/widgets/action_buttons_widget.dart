import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class ActionButtonsWidget extends StatelessWidget {
  final bool isProvider;
  final bool readOnly;
  final bool hasFinished;
  final VoidCallback onFinishPressed;
  final VoidCallback onRevertPressed;
  final VoidCallback onVideoCallPressed;
  final VoidCallback onInfoPressed;

  const ActionButtonsWidget({
    super.key,
    required this.isProvider,
    required this.readOnly,
    this.hasFinished = false,
    required this.onFinishPressed,
    required this.onRevertPressed,
    required this.onVideoCallPressed,
    required this.onInfoPressed,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('[ActionButtonsWidget] build: isProvider=$isProvider, hasFinished=$hasFinished, readOnly=$readOnly');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isProvider && hasFinished)
          TextButton.icon(
            onPressed: onRevertPressed,
            icon: const Icon(Icons.undo_rounded, color: Color(0xFFFF9800), size: 18),
            label: const Text('ยกเลิกปิดงาน', style: TextStyle(color: Color(0xFFFF9800), fontSize: 12, fontWeight: FontWeight.bold)),
          )
        else if (isProvider && !readOnly)
          TextButton.icon(
            onPressed: onFinishPressed,
            icon: const Icon(Icons.done_all, color: AppColors.primary, size: 18),
            label: const Text('จบงาน', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        if (!readOnly && !hasFinished)
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
