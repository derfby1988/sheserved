import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../services/websocket_service.dart';

import '../../data/models/app_notification.dart';
import '../../data/repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(Supabase.instance.client);
});

class NotificationCategorySummary {
  final int unreadCount;
  final DateTime? latestAt;

  const NotificationCategorySummary({this.unreadCount = 0, this.latestAt});
}

class NotificationState {
  final bool isLoading;
  final List<AppNotification> notifications;

  /// จำนวนที่อ่านจาก repository/gateway
  final int unreadCount;

  /// จำนวนที่รับผ่าน Realtime แล้ว repository ยังนับให้ไม่ได้
  /// (โหมด legacy ไม่มี Supabase Auth session → `getUnreadCount` คืน 0 เสมอ)
  final int localUnreadCount;

  final String? errorMessage;

  const NotificationState({
    this.isLoading = false,
    this.notifications = const [],
    this.unreadCount = 0,
    this.localUnreadCount = 0,
    this.errorMessage,
  });

  /// ตัวเลขที่ควรแสดงบน badge — ต้องรวมรายการที่รับสดด้วย ไม่งั้นการ refresh
  /// จาก repository (ทุก 30 วิ) จะลบตัวเลขที่เพิ่งขึ้นให้ผู้ใช้เห็นทิ้ง
  int get totalUnreadCount => unreadCount + localUnreadCount;

  NotificationState copyWith({
    bool? isLoading,
    List<AppNotification>? notifications,
    int? unreadCount,
    int? localUnreadCount,
    String? errorMessage,
  }) {
    return NotificationState(
      isLoading: isLoading ?? this.isLoading,
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      localUnreadCount: localUnreadCount ?? this.localUnreadCount,
      errorMessage: errorMessage,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  final NotificationRepository _repo;

  /// แจ้งเตือนที่รับผ่าน Realtime ในหน่วยความจำ — เป็นแหล่งนับ badge เมื่อ
  /// repository อ่าน/nับให้ไม่ได้ (legacy mode)
  final Map<String, AppNotification> _localNotifications = {};

  late final StreamSubscription<Map<String, dynamic>>
  _applicationNotificationSubscription;

  NotificationNotifier(this._repo) : super(const NotificationState()) {
    _applicationNotificationSubscription = WebSocketService()
        .applicationNotificationStream
        .listen(_receiveApplicationNotification);
  }

  bool get _repoCountsLocalNotifications => _repo.usesGateway;

  int get _localUnreadCount => _repoCountsLocalNotifications
      ? 0
      : _localNotifications.values.where((item) => !item.isRead).length;

  /// จำนวนรายการที่รับสดตามหมวด — ใช้เมื่อปุ่มแจ้งเตือนผูกกับหมวดเดียว
  /// ซึ่งอ่านผ่าน `notificationUnreadCountProvider` ที่นับได้แค่ฝั่ง repository
  int localUnreadCountFor(String? category) {
    if (_repoCountsLocalNotifications) return 0;
    return _localNotifications.values
        .where(
          (item) =>
              !item.isRead && (category == null || item.category == category),
        )
        .length;
  }

  void _receiveApplicationNotification(Map<String, dynamic> data) {
    try {
      receiveLocalNotification(AppNotification.fromJson(data));
    } catch (_) {
      // Ignore malformed realtime payloads; the next gateway refresh repairs state.
    }
  }

  /// แจ้งเตือนที่มาทาง Supabase Realtime (เช่นคำขอเพิ่มประเภทกีฬา) —
  /// อัปเดตรายการ + badge ทันทีโดยไม่ต้องรอ refresh รอบถัดไป
  void receiveLocalNotification(AppNotification notification) {
    final previous = state.notifications
        .where((item) => item.id == notification.id)
        .firstOrNull;
    _localNotifications[notification.id] = notification;
    // โหมด gateway นับจาก repository ตรงๆ จึงต้องบวกเองชั่วคราวแล้วรอ refresh
    // ยืนยันตัวเลข — โหมด legacy ใช้ localUnreadCount แทน
    final unreadDelta =
        _repoCountsLocalNotifications &&
            previous == null &&
            !notification.isRead
        ? 1
        : 0;
    state = state.copyWith(
      notifications: [
        notification,
        ...state.notifications.where((item) => item.id != notification.id),
      ],
      unreadCount: state.unreadCount + unreadDelta,
      localUnreadCount: _localUnreadCount,
    );
  }

  /// ตัดการ์ดที่รับสดรายการเดียวออกจาก badge — ใช้เมื่อผู้ใช้กดเปิด/ปัดซ่อน
  /// การ์ด toast ที่สร้างในเครื่อง (ไม่มีแถวจริงใน `app_notifications` ให้ mark)
  void removeLocalNotification(String notificationId) {
    if (!_localNotifications.containsKey(notificationId)) return;
    _localNotifications.remove(notificationId);
    state = state.copyWith(
      notifications: state.notifications
          .where((notification) => notification.id != notificationId)
          .toList(),
      localUnreadCount: _localUnreadCount,
    );
  }

  /// ซิงก์รายการที่รับสดกับสถานะจริงจากต้นทาง (เช่นคำขอกีฬาที่ยัง `pending`)
  /// — ตัดการ์ดที่ถูกตรวจ/ซ่อนไปแล้วออกจากตัวเลขบน badge
  void syncLocalNotifications(Iterable<AppNotification> notifications) {
    final pendingIds = <String>{};
    for (final notification in notifications) {
      _localNotifications[notification.id] = notification;
      if (notification.eventType == 'sport.proposal_submitted') {
        pendingIds.add(notification.id);
      }
    }
    _localNotifications.removeWhere(
      (id, notification) =>
          notification.eventType == 'sport.proposal_submitted' &&
          !pendingIds.contains(id),
    );

    final localUnreadCount = _localUnreadCount;
    if (localUnreadCount == state.localUnreadCount) return;
    state = state.copyWith(localUnreadCount: localUnreadCount);
  }

  @override
  void dispose() {
    _applicationNotificationSubscription.cancel();
    super.dispose();
  }

  Future<void> loadNotifications({String? category}) async {
    state = state.copyWith(isLoading: true);
    final notifications = await _repo.getNotifications(category: category);
    final unreadCount = await _repo.getUnreadCount(category: category);
    state = NotificationState(
      isLoading: false,
      notifications: notifications,
      unreadCount: unreadCount,
      localUnreadCount: _localUnreadCount,
    );
  }

  Future<void> refreshUnreadCount({String? category}) async {
    final count = await _repo.getUnreadCount(category: category);
    state = state.copyWith(
      unreadCount: count,
      localUnreadCount: _localUnreadCount,
    );
  }

  Future<void> markAsRead(String notificationId, {String? category}) async {
    await _repo.markAsRead(notificationId);
    _localNotifications.remove(notificationId);
    await loadNotifications(category: category);
  }

  Future<bool> dismissNotification(
    String notificationId, {
    String? category,
  }) async {
    final success = await _repo.dismissNotification(notificationId);
    if (!success) return false;

    _localNotifications.remove(notificationId);
    state = state.copyWith(
      notifications: state.notifications
          .where((notification) => notification.id != notificationId)
          .toList(),
      localUnreadCount: _localUnreadCount,
    );
    await refreshUnreadCount(category: category);
    return true;
  }

  Future<void> markAllAsRead({String? category}) async {
    await _repo.markAllAsRead(category: category);
    _localNotifications.removeWhere(
      (_, notification) =>
          category == null || notification.category == category,
    );
    await loadNotifications(category: category);
  }
}

final notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
      return NotificationNotifier(ref.read(notificationRepositoryProvider));
    });

final notificationUnreadCountProvider = StreamProvider.family<int, String?>((
  ref,
  category,
) async* {
  final repository = ref.watch(notificationRepositoryProvider);
  yield await repository.getUnreadCount(category: category);

  await for (final event in WebSocketService().applicationNotificationStream) {
    if (category == null || event['category']?.toString() == category) {
      yield await repository.getUnreadCount(category: category);
    }
  }
});

final notificationCategorySummaryProvider =
    StreamProvider.family<NotificationCategorySummary, String?>((
      ref,
      category,
    ) {
      final repository = ref.watch(notificationRepositoryProvider);
      return repository.watchNotifications(category: category).asyncMap((
        notifications,
      ) async {
        final unreadCount = await repository.getUnreadCount(category: category);
        return NotificationCategorySummary(
          unreadCount: unreadCount,
          latestAt: notifications.isEmpty
              ? null
              : notifications.first.createdAt,
        );
      });
    });
