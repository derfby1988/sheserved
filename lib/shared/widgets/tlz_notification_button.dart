import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../features/erp/presentation/providers/notification_provider.dart';
import '../../services/websocket_service.dart';
import 'tlz_notification_panel.dart';

/// Notification Button Widget with Badge
/// Shows notification icon with badge count from NotificationProvider
/// กริ่งจะสั่นเมื่อมี notification ใหม่เข้ามาทาง WebSocket
class TlzNotificationButton extends ConsumerStatefulWidget {
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
  ConsumerState<TlzNotificationButton> createState() =>
      _TlzNotificationButtonState();
}

class _TlzNotificationButtonState extends ConsumerState<TlzNotificationButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wiggle;
  late final Animation<double> _rotate;
  late final Animation<double> _scale;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  @override
  void initState() {
    super.initState();
    _wiggle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _rotate = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 0.5), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.5, end: -0.45), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.45, end: 0.4), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.4, end: -0.32), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.32, end: 0.25), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.25, end: -0.18), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.18, end: 0.12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.12, end: -0.07), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.07, end: 0.03), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.03, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _wiggle, curve: Curves.easeInOut));
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.35), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 0.88), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.88, end: 1.18), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 0.94), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.94, end: 1.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 0.98), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.98, end: 1), weight: 1),
    ]).animate(CurvedAnimation(parent: _wiggle, curve: Curves.easeInOut));

    _subscription = WebSocketService().applicationNotificationStream.listen((
      data,
    ) {
      debugPrint('[TlzNotificationButton] application-notification received');
      if (mounted) _wiggle.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notificationState = ref.watch(notificationProvider);
    final categoryCount = widget.category == null
        ? null
        : ref
              .watch(notificationUnreadCountProvider(widget.category))
              .when(
                data: (count) => count,
                loading: () => 0,
                error: (_, _) => 0,
              );
    final count =
        widget.badgeCount ?? categoryCount ?? notificationState.unreadCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: AnimatedBuilder(
            animation: _wiggle,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotate.value,
                alignment: Alignment.topCenter,
                child: Transform.scale(scale: _scale.value, child: child),
              );
            },
            child: Icon(
              Icons.notifications_outlined,
              color: widget.iconColor ?? AppColors.accent,
              size: 24,
            ),
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed:
              widget.onPressed ??
              () {
                showTlzNotificationPanel(context, category: widget.category);
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
                color: widget.badgeColor ?? AppColors.accent, // สีส้ม-เหลือง
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
