// finish_job_warning_dialog.dart
// Phase 6.8: Expert Completion Rules

import 'package:flutter/material.dart';

class FinishJobWarningDialog extends StatelessWidget {
  final List<String> missingRequirements;
  final VoidCallback? onOverride;

  const FinishJobWarningDialog({
    super.key,
    required this.missingRequirements,
    this.onOverride,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9800)),
          SizedBox(width: 8),
          Text('ยังไม่สามารถจบงานได้'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'คุณยังไม่ครบตามเงื่อนไขการปิดงาน:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          ...missingRequirements.map((req) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.cancel,
                  color: Colors.redAccent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    req,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('กลับไปทำงานต่อ'),
        ),
        if (onOverride != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
              onOverride!();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
            ),
            child: const Text('จบงานโดยไม่สนใจ'),
          ),
      ],
    );
  }
}
