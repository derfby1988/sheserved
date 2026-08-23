import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notification_provider.dart';
import '../widgets/glass_card.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';
import '../../../../shared/widgets/tlz_notification_panel.dart';

class NotificationListPage extends ConsumerStatefulWidget {
  final String? category;

  const NotificationListPage({super.key, this.category});

  @override
  ConsumerState<NotificationListPage> createState() =>
      _NotificationListPageState();
}

class _NotificationListPageState extends ConsumerState<NotificationListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(notificationProvider.notifier)
          .loadNotifications(category: widget.category);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('การแจ้งเตือน'),
        actions: [
          if (state.unreadCount > 0)
            TextButton.icon(
              onPressed: () {
                ref
                    .read(notificationProvider.notifier)
                    .markAllAsRead(category: widget.category);
              },
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('อ่านทั้งหมด'),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off_outlined,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'ไม่มีการแจ้งเตือน',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref
                      .read(notificationProvider.notifier)
                      .loadNotifications(category: widget.category),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.notifications.length,
                    itemBuilder: (context, index) {
                      final notif = state.notifications[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          section: GlassSection.card,
                          tintColor: notif.isRead
                              ? null
                              : Theme.of(context).colorScheme.primaryContainer,
                          child: ListTile(
                            leading: _categoryIcon(notif.category),
                            title: Text(
                              notif.title,
                              style: TextStyle(
                                fontWeight: notif.isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                              ),
                            ),
                            subtitle: notif.body != null
                                ? Text(notif.body!)
                                : null,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatRelativeTime(notif.createdAt),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.grey.shade600,
                                      ),
                                ),
                                if (!notif.isRead)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () async {
                              final opened =
                                  await openTlzNotificationDestination(
                                context,
                                notif,
                              );
                              if (!context.mounted) return;
                              if (!opened) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'ยังไม่พบหน้าปลายทางของการแจ้งเตือนนี้',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final dismissed = await ref
                                  .read(notificationProvider.notifier)
                                  .dismissNotification(
                                    notif.id,
                                    category: widget.category,
                                  );
                              if (!context.mounted || dismissed) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'ไม่สามารถซ่อนการแจ้งเตือนได้ กรุณาลองใหม่',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _categoryIcon(String category) {
    final icon = switch (category) {
      'procurement' => Icons.shopping_cart_outlined,
      'inventory' => Icons.inventory_2_outlined,
      'kpi' => Icons.analytics_outlined,
      'hr' => Icons.people_outlined,
      'chat' => Icons.chat_bubble_outline,
      'consultation' => Icons.medical_services_outlined,
      'donation' => Icons.volunteer_activism_outlined,
      'health' => Icons.health_and_safety_outlined,
      'articles' => Icons.article_outlined,
      'pharmacy' => Icons.local_pharmacy_outlined,
      _ => Icons.notifications_outlined,
    };
    return Icon(icon);
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
    if (diff.inHours < 24) return '${diff.inHours} ชม.ที่แล้ว';
    if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
    return ThaiDateUtils.formatShortDateBE(dateTime);
  }
}
