import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../features/erp/data/models/app_notification.dart';
import '../../features/erp/presentation/providers/notification_provider.dart';
import '../../services/websocket_service.dart';

/// การ์ดจางๆ ที่แสดงใต้ Top Bar เมื่อมี notification ใหม่เข้ามาทาง WebSocket
/// เป็น child ตรงของ Stack ใน MaterialApp.builder → return Positioned ได้
/// แอนิเมชัน: fade + slide ลงมา → ค้างสักครู่ → fade + slide กลับขึ้น → หายไป
class TlzNotificationToast extends ConsumerStatefulWidget {
  const TlzNotificationToast({super.key});

  @override
  ConsumerState<TlzNotificationToast> createState() =>
      _TlzNotificationToastState();
}

class _TlzNotificationToastState extends ConsumerState<TlzNotificationToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _hideTimer;
  AppNotification? _current;
  double _dragOffset = 0;

  static const _showDuration = Duration(milliseconds: 480);
  static const _hideDuration = Duration(milliseconds: 560);
  static const _holdDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _showDuration,
      reverseDuration: _hideDuration,
    );
    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _subscription = WebSocketService().applicationNotificationStream.listen(
      _onNotification,
    );
  }

  void _onNotification(Map<String, dynamic> data) {
    if (!mounted) return;
    debugPrint(
      '[TlzNotificationToast] received: ${data['type'] ?? data['event_type'] ?? 'unknown'}',
    );
    AppNotification notification;
    try {
      notification = AppNotification.fromJson(data);
    } catch (e) {
      debugPrint('[TlzNotificationToast] parse error: $e');
      return;
    }

    _hideTimer?.cancel();
    _controller.stop();

    // ถ้าการ์ดกำลังแสดงอยู่ → อัปเดตเนื้อหา + รีเซ็ต hold timer (ไม่ต้อง animate ใหม่)
    if (_controller.value > 0 && _current != null) {
      setState(() {
        _dragOffset = 0;
        _current = notification;
      });
      _hideTimer = Timer(_holdDuration, () {
        if (mounted) _hideCurrent();
      });
      return;
    }

    // ไม่ได้แสดง → เริ่มแอนิเมชันใหม่
    setState(() {
      _dragOffset = 0;
      _current = notification;
    });
    _controller.forward(from: 0).then((_) {
      if (!mounted) return;
      // hold สักครู่ แล้ว reverse (fade + slide กลับขึ้น)
      _hideTimer = Timer(_holdDuration, () {
        if (mounted) _hideCurrent();
      });
    });
  }

  /// ปิดการ์ดปัจจุบัน พร้อมยกเลิก timer และ reverse แอนิเมชัน
  void _hideCurrent() {
    _hideTimer?.cancel();
    _controller.reverse().then((_) {
      if (mounted) setState(() => _current = null);
    });
  }

  /// ปัดซ้ายเพื่อยกเลิกรายการแจ้งเตือนนั้น
  /// ปิดการ์ดทันที แล้วแจ้ง provider เพื่อ mark dismissed (non-blocking)
  void _dismissCurrent() {
    final notification = _current;
    _hideTimer?.cancel();
    _controller.stop();
    setState(() {
      _dragOffset = 0;
      _current = null;
    });
    if (notification == null) return;
    ref
        .read(notificationProvider.notifier)
        .dismissNotification(notification.id, category: notification.category);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!mounted) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(-1000.0, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final shouldDismiss =
        _dragOffset < -80 || details.velocity.pixelsPerSecond.dx < -500;
    if (shouldDismiss) {
      _dismissCurrent();
      return;
    }
    if (mounted) setState(() => _dragOffset = 0);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_current == null) return const SizedBox.shrink();
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 56,
      left: 16,
      right: 16,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            const Positioned.fill(child: _ToastDismissBackground()),
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: SlideTransition(
                position: _slide,
                child: FadeTransition(
                  opacity: _opacity,
                  child: _ToastCard(notification: _current!),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// พื้นหลังที่เผยออกเมื่อปัดซ้าย — ไอคอนปิดโทนเดียวกับการ์ด (ไม่มีขอบ)
class _ToastDismissBackground extends StatelessWidget {
  const _ToastDismissBackground();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.redAccent.withValues(alpha: isDark ? 0.22 : 0.16),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(
        Icons.delete_outline_rounded,
        color: Colors.redAccent.withValues(alpha: isDark ? 0.9 : 0.8),
        size: 22,
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  final AppNotification notification;
  const _ToastCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surface.withValues(alpha: isDark ? 0.28 : 0.42),
                colorScheme.surface.withValues(alpha: isDark ? 0.18 : 0.30),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accent.withValues(alpha: 0.32),
                      AppColors.accent.withValues(alpha: 0.14),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (notification.body != null &&
                        notification.body!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          notification.body!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.65,
                                ),
                                height: 1.35,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
