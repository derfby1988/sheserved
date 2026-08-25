import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../features/chat/presentation/chat_unread_provider.dart';
import '../../features/chat/presentation/pages/chat_room_page.dart';
import '../../features/erp/data/models/app_notification.dart';
import '../../features/erp/presentation/providers/notification_provider.dart';
import '../../features/erp/presentation/widgets/glass_card.dart';

Future<void> showTlzNotificationPanel(
  BuildContext context, {
  String? category,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (_) => TlzNotificationPanel(category: category),
  );
}

Future<bool> openTlzNotificationDestination(
  BuildContext context,
  AppNotification notification,
) async {
  final route = _resolveNotificationRoute(notification);
  if (route == null) return false;

  try {
    await Navigator.of(context).pushNamed(
      route,
      arguments: _notificationArguments(route, notification.payload),
    );
    return true;
  } catch (_) {
    return false;
  }
}

String? _resolveNotificationRoute(AppNotification notification) {
  final payloadRoute = notification.payload['route']?.toString();
  if (payloadRoute != null && payloadRoute.startsWith('/')) {
    return payloadRoute;
  }

  return switch (notification.category) {
    'chat' => '/chat-list',
    'consultation' => '/health-program-requests',
    'donation' => '/donate',
    'health' => '/health',
    'articles' => '/articles',
    'procurement' || 'inventory' || 'kpi' || 'hr' || 'admin' => '/erp',
    _ => null,
  };
}

Object? _notificationArguments(
  String route,
  Map<String, dynamic> payload,
) {
  if (route == '/articles') return payload['filter']?.toString();
  if (route == '/chat-list' ||
      route == '/health-program-requests' ||
      route == '/donate' ||
      route == '/health' ||
      route == '/erp') {
    return null;
  }
  return payload.isEmpty ? null : payload;
}

class TlzNotificationPanel extends ConsumerStatefulWidget {
  final String? category;

  const TlzNotificationPanel({super.key, this.category});

  @override
  ConsumerState<TlzNotificationPanel> createState() =>
      _TlzNotificationPanelState();
}

class _TlzNotificationPanelState
    extends ConsumerState<TlzNotificationPanel> {
  static const _filters = <({String label, String? value})>[
    (label: 'ทั้งหมด', value: null),
    (label: 'แชท', value: 'chat'),
    (label: 'คำปรึกษา', value: 'consultation'),
    (label: 'ERP', value: 'procurement'),
    (label: 'บริจาค', value: 'donation'),
    (label: 'สุขภาพ', value: 'health'),
  ];

  String? _selectedCategory;
  List<Map<String, dynamic>> _chatRooms = [];
  bool _isLoadingChatRooms = false;

  bool get _showsChat =>
      _selectedCategory == null || _selectedCategory == 'chat';

  bool get _needsChatData =>
      widget.category == null || _selectedCategory == 'chat';

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.category;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    await _loadNotifications();
    if (_needsChatData) await _loadChatRooms();
  }

  Future<void> _loadNotifications() {
    return ref
        .read(notificationProvider.notifier)
        .loadNotifications(category: _selectedCategory);
  }

  Future<void> _loadChatRooms() async {
    if (_isLoadingChatRooms) return;
    setState(() => _isLoadingChatRooms = true);
    final rooms = await ref
        .read(chatUnreadProvider.notifier)
        .getUnreadRoomSummaries();
    if (!mounted) return;
    setState(() {
      _chatRooms = rooms;
      _isLoadingChatRooms = false;
    });
  }

  Future<void> _refresh() async {
    final tasks = <Future<void>>[_loadNotifications()];
    if (_needsChatData) {
      tasks.add(_loadChatRooms());
    }
    await Future.wait(tasks);
  }

  Future<void> _changeCategory(String? category) async {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
      if (!_needsChatData) _chatRooms = [];
    });
    await _refresh();
  }

  Future<void> _markAllAsRead() async {
    final tasks = <Future<void>>[
      ref
          .read(notificationProvider.notifier)
          .markAllAsRead(category: _selectedCategory),
    ];
    if (_showsChat) {
      tasks.add(ref.read(chatUnreadProvider.notifier).markAllAsRead());
    }
    await Future.wait(tasks);
    await _refresh();
  }

  Future<void> _openNotification(AppNotification notification) async {
    final opened = await openTlzNotificationDestination(context, notification);
    if (!opened || !mounted) {
      if (mounted) _showMessage('ยังไม่พบหน้าปลายทางของการแจ้งเตือนนี้');
      return;
    }

    final dismissed = await ref
        .read(notificationProvider.notifier)
        .dismissNotification(
          notification.id,
          category: _selectedCategory,
        );
    if (!mounted) return;
    if (!dismissed) {
      _showMessage('ไม่สามารถซ่อนการแจ้งเตือนได้ กรุณาลองใหม่');
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _openChatRoom(Map<String, dynamic> room) async {
    final roomId = room['roomId']?.toString();
    if (roomId == null || roomId.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatRoomPage(roomId: roomId)),
    );
    if (!mounted) return;

    await ref.read(chatUnreadProvider.notifier).markRoomAsRead(roomId);
    await _loadChatRooms();
    if (mounted && _chatRooms.every((item) => item['roomId'] != roomId)) {
      setState(() {});
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  DateTime? _latestChatAt() {
    DateTime? latest;
    for (final room in _chatRooms) {
      final createdAt = DateTime.tryParse(room['createdAt']?.toString() ?? '');
      if (createdAt != null && (latest == null || createdAt.isAfter(latest))) {
        latest = createdAt;
      }
    }
    return latest;
  }

  List<({
    String label,
    String? value,
    int unreadCount,
    DateTime? latestAt,
    int index,
  })> _buildOrderedFilters({
    required NotificationCategorySummary allSummary,
    required int chatUnreadCount,
    required DateTime? latestChatAt,
  }) {
    final filters = _filters.asMap().entries.map((entry) {
      final filter = entry.value;
      var unreadCount = 0;
      DateTime? latestAt;

      if (filter.value == null) {
        unreadCount = allSummary.unreadCount + chatUnreadCount;
        latestAt = allSummary.latestAt;
      } else if (filter.value == 'chat') {
        unreadCount = chatUnreadCount;
        latestAt = latestChatAt;
      } else {
        final summary = ref
            .watch(notificationCategorySummaryProvider(filter.value))
            .maybeWhen(
              data: (value) => value,
              orElse: () => const NotificationCategorySummary(),
            );
        unreadCount = summary.unreadCount;
        latestAt = summary.latestAt;
      }

      if (filter.value == null &&
          latestChatAt != null &&
          (latestAt == null || latestChatAt.isAfter(latestAt))) {
        latestAt = latestChatAt;
      }

      return (
        label: filter.label,
        value: filter.value,
        unreadCount: unreadCount,
        latestAt: latestAt,
        index: entry.key,
      );
    }).toList();

    final allFilter = filters.first;
    final categoryFilters = filters.skip(1).toList()
      ..sort((a, b) {
        final aHasUnread = a.unreadCount > 0;
        final bHasUnread = b.unreadCount > 0;
        if (aHasUnread != bHasUnread) return aHasUnread ? -1 : 1;

        if (aHasUnread) {
          final aLatest = a.latestAt;
          final bLatest = b.latestAt;
          if (aLatest != null && bLatest != null) {
            final latestComparison = bLatest.compareTo(aLatest);
            if (latestComparison != 0) return latestComparison;
          } else if (aLatest != null) {
            return -1;
          } else if (bLatest != null) {
            return 1;
          }
          final countComparison = b.unreadCount.compareTo(a.unreadCount);
          if (countComparison != 0) return countComparison;
        }

        return a.index.compareTo(b.index);
      });

    return [allFilter, ...categoryFilters];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);
    final allSummary = ref
        .watch(notificationCategorySummaryProvider(null))
        .maybeWhen(
          data: (summary) => summary,
          orElse: () => const NotificationCategorySummary(),
        );
    final selectedSummary = ref
        .watch(notificationCategorySummaryProvider(_selectedCategory))
        .maybeWhen(
          data: (summary) => summary,
          orElse: () => const NotificationCategorySummary(),
        );
    final chatUnreadCount = _chatRooms.fold<int>(
      0,
      (total, room) => total + ((room['unreadCount'] as num?)?.toInt() ?? 0),
    );
    final selectedAppUnreadCount = _selectedCategory == null
        ? allSummary.unreadCount
        : selectedSummary.unreadCount;
    final totalUnread =
        selectedAppUnreadCount + (_showsChat ? chatUnreadCount : 0);
    final latestChatAt = _latestChatAt();
    final orderedFilters = _buildOrderedFilters(
      allSummary: allSummary,
      chatUnreadCount: chatUnreadCount,
      latestChatAt: latestChatAt,
    );
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.50,
      maxChildSize: 0.86,
      expand: false,
      builder: (context, scrollController) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: GlassCard(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                section: GlassSection.dialog,
                borderRadius: 28,
                glassOpacity: 0.36,
                glassBlur: 22,
                customBorder: Border.all(
                  color: Colors.white.withValues(alpha: 0.42),
                  width: 1.2,
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurface.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: colorScheme.onSurface.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'การแจ้งเตือน',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: colorScheme.onSurface,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    totalUnread > 0
                                        ? 'ยังไม่อ่าน $totalUnread รายการ'
                                        : 'ไม่มีรายการที่ยังไม่อ่าน',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.82),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            if (totalUnread > 0)
                              TextButton.icon(
                                onPressed: _markAllAsRead,
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.accentDark,
                                ),
                                icon: const Icon(Icons.done_all, size: 18),
                                label: const Text('อ่านทั้งหมด'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.category == null)
                        SizedBox(
                          height: 42,
                          child: ListView.separated(
                            padding: const EdgeInsets.only(
                              left: 20,
                              right: 32,
                            ),
                            scrollDirection: Axis.horizontal,
                            itemCount: orderedFilters.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final filter = orderedFilters[index];
                              final selected =
                                  _selectedCategory == filter.value;
                              final hasUnread = filter.unreadCount > 0;
                              final inactiveColor = colorScheme.onSurface
                                  .withValues(alpha: 0.12);
                              return ChoiceChip(
                                label: Text(filter.label),
                                selected: selected,
                                onSelected: (_) =>
                                    _changeCategory(filter.value),
                                labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : hasUnread
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurface.withValues(
                                              alpha: 0.55,
                                            ),
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                visualDensity: VisualDensity.compact,
                                selectedColor: hasUnread
                                    ? AppColors.accent.withValues(alpha: 0.85)
                                    : Colors.grey.withValues(alpha: 0.70),
                                backgroundColor: hasUnread
                                    ? AppColors.accent.withValues(alpha: 0.15)
                                    : inactiveColor,
                                side: BorderSide(
                                  color: hasUnread
                                      ? AppColors.accent.withValues(alpha: 0.45)
                                      : colorScheme.onSurface
                                          .withValues(alpha: 0.18),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: state.isLoading &&
                                state.notifications.isEmpty &&
                                _chatRooms.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : RefreshIndicator(
                                onRefresh: _refresh,
                                color: AppColors.primary,
                                child: ListView(
                                  controller: scrollController,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    8,
                                    20,
                                    24,
                                  ),
                                  children: [
                                    if (_chatRooms.isNotEmpty && _showsChat)
                                      ...[
                                        _buildSectionTitle('ข้อความแชท'),
                                        ..._chatRooms.map(_buildChatRoomCard),
                                      ],
                                    if (state.notifications.isNotEmpty &&
                                        _selectedCategory != 'chat')
                                      ...[
                                        _buildSectionTitle(
                                          _selectedCategory == null
                                              ? 'การแจ้งเตือนระบบ'
                                              : 'รายการแจ้งเตือน',
                                        ),
                                        ...state.notifications
                                            .map(_buildNotificationCard),
                                      ],
                                    if (_chatRooms.isEmpty &&
                                        state.notifications.isEmpty)
                                      _buildEmptyState(),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildChatRoomCard(Map<String, dynamic> room) {
    final colorScheme = Theme.of(context).colorScheme;
    final roomId = room['roomId']?.toString() ?? '';
    final title = room['title']?.toString() ?? 'ห้องสนทนา';
    final preview = room['preview']?.toString() ?? '';
    final unreadCount = (room['unreadCount'] as num?)?.toInt() ?? 0;
    final createdAt = DateTime.tryParse(room['createdAt']?.toString() ?? '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 18,
        glassOpacity: 0.28,
        glassBlur: 14,
        customBorder: Border.all(
          color: Colors.white.withValues(alpha: 0.38),
          width: 1.0,
        ),
        tintColor: AppColors.info.withValues(alpha: 0.12),
        padding: EdgeInsets.zero,
        child: ListTile(
          onTap: roomId.isEmpty ? null : () => _openChatRoom(room),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: AppColors.info.withValues(alpha: 0.18),
            child: const Icon(Icons.chat_bubble_outline, color: AppColors.info),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            preview.isEmpty ? 'มีข้อความที่ยังไม่ได้อ่าน' : preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (createdAt != null)
                Text(
                  _formatRelativeTime(createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.68),
                      ),
                ),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.info,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$unreadCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(AppNotification notification) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = _categoryColor(notification.category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 18,
        glassOpacity: 0.28,
        glassBlur: 14,
        customBorder: Border.all(
          color: Colors.white.withValues(alpha: 0.38),
          width: 1.0,
        ),
        tintColor: notification.isRead
            ? null
            : AppColors.accent.withValues(alpha: 0.14),
        padding: EdgeInsets.zero,
        child: ListTile(
          onTap: () => _openNotification(notification),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: iconColor.withValues(alpha: 0.16),
            child: Icon(_categoryIcon(notification.category), color: iconColor),
          ),
          title: Text(
            notification.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight:
                  notification.isRead ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
          subtitle: notification.body == null
              ? Text(
                  _categoryLabel(notification.category),
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.78),
                  ),
                )
              : Text(
                  notification.body!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.78),
                  ),
                ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatRelativeTime(notification.createdAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.68),
                    ),
              ),
              if (!notification.isRead) ...[
                const SizedBox(height: 5),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 240,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 56,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              'ไม่มีการแจ้งเตือน',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'เมื่อมีรายการใหม่จะแสดงที่นี่',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.78),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      'chat' => Icons.chat_bubble_outline,
      'consultation' => Icons.medical_services_outlined,
      'procurement' => Icons.shopping_cart_outlined,
      'inventory' => Icons.inventory_2_outlined,
      'kpi' => Icons.analytics_outlined,
      'hr' => Icons.people_outlined,
      'donation' => Icons.volunteer_activism_outlined,
      'health' => Icons.health_and_safety_outlined,
      'articles' => Icons.article_outlined,
      'pharmacy' => Icons.local_pharmacy_outlined,
      _ => Icons.notifications_outlined,
    };
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'chat' => AppColors.info,
      'consultation' => AppColors.primaryDark,
      'donation' => AppColors.error,
      'health' => AppColors.success,
      'pharmacy' => AppColors.secondary,
      _ => AppColors.accentDark,
    };
  }

  String _categoryLabel(String category) {
    return switch (category) {
      'chat' => 'ข้อความแชท',
      'consultation' => 'คำปรึกษา',
      'procurement' => 'จัดซื้อ',
      'inventory' => 'คลังสินค้า',
      'kpi' => 'KPI',
      'hr' => 'บุคลากร',
      'donation' => 'บริจาค',
      'health' => 'สุขภาพ',
      'articles' => 'บทความ',
      'pharmacy' => 'ร้านยา',
      _ => 'ระบบ',
    };
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
    if (diff.inHours < 24) return '${diff.inHours} ชม.ที่แล้ว';
    if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year + 543}';
  }
}
