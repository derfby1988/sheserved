import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../features/erp/presentation/providers/notification_provider.dart';
import 'tlz_notification_panel.dart';

/// Notification Button Widget with Badge
/// Shows notification icon with badge count from NotificationProvider
class TlzNotificationButton extends ConsumerWidget {
  final int? badgeCount;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final Color? badgeColor;
  final String? category;

  const TlzNotificationButton({
    super.key,
    this.badgeCount,
    this.onPressed,
    this.iconColor,
    this.badgeColor,
    this.category,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationState = ref.watch(notificationProvider);
    final categoryCount = category == null
        ? null
        : ref.watch(notificationUnreadCountProvider(category)).when(
              data: (count) => count,
              loading: () => 0,
              error: (_, _) => 0,
            );
    final count = badgeCount ?? categoryCount ?? notificationState.unreadCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            Icons.notifications_outlined,
            color: iconColor ?? AppColors.accent,
            size: 24,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: onPressed ?? () {
            showTlzNotificationPanel(context, category: category);
          },
        ),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: badgeColor ?? AppColors.accent, // สีส้ม-เหลือง
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textOnPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
