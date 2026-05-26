import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class TimerBadgeWidget extends StatelessWidget {
  final ValueListenable<int> remainingSeconds;
  final ValueListenable<bool> isTimerRunning;
  final bool allRequiredJoined;
  final String Function(int) formatTimer;

  const TimerBadgeWidget({
    super.key,
    required this.remainingSeconds,
    required this.isTimerRunning,
    required this.allRequiredJoined,
    required this.formatTimer,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([remainingSeconds, isTimerRunning]),
      builder: (context, child) {
        final rs = remainingSeconds.value;
        final itr = isTimerRunning.value;
        final bool isLowTime = rs < 300 && itr;
        final bool isWaiting = !itr && rs > 0 && !allRequiredJoined;
        final bool isStarting = !itr && rs > 0 && allRequiredJoined;

        final Color badgeColor = isWaiting
            ? Colors.orange
            : (isLowTime ? Colors.red : AppColors.primary);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isWaiting
                ? Colors.orange.shade50
                : (isLowTime ? Colors.red.shade50 : badgeColor.withOpacity(0.1)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isWaiting
                  ? Colors.orange.withOpacity(0.3)
                  : (isLowTime ? Colors.red.withOpacity(0.3) : badgeColor.withOpacity(0.3)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isWaiting)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.orange)),
                )
              else if (isStarting)
                Icon(
                  Icons.play_circle_outline,
                  size: 14,
                  color: badgeColor,
                )
              else
                Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: isLowTime ? Colors.red : AppColors.primary,
                ),
              const SizedBox(width: 6),
              Text(
                isWaiting
                    ? 'รอผู้เชี่ยวชาญเข้าร่วม'
                    : (isStarting ? 'เริ่มให้คำปรึกษา' : formatTimer(rs)),
                style: TextStyle(
                  color: isWaiting ? Colors.orange.shade800 : (isLowTime ? Colors.red : badgeColor),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
