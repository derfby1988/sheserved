import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../services/auth_service.dart';
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
  RealtimeChannel? _sportResultChannel;

  NotificationNotifier(this._repo) : super(const NotificationState()) {
    _applicationNotificationSubscription = WebSocketService()
        .applicationNotificationStream
        .listen(_receiveApplicationNotification);
    if (!_repo.usesGateway) _subscribeSportResults();
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

  /// โหมด legacy ใช้ Supabase Realtime ที่มีอยู่แล้วเพื่อแจ้งผลคำขอให้ผู้ยื่น
  /// โดยตรง การรับ event นี้อัปเดตเฉพาะ provider จึงไม่สร้าง toast
  void _subscribeSportResults() {
    try {
      _sportResultChannel = Supabase.instance.client
          .channel('sport_proposal_results')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'sports',
            callback: _receiveSportReviewUpdate,
          )
          .subscribe();
    } catch (_) {
      // Realtime is best-effort; the persisted app notification remains available.
    }
  }

  void _receiveSportReviewUpdate(PostgresChangePayload change) {
    final record = change.newRecord;
    final userId = AuthService.instance.userId;
    final proposedBy = record['proposed_by']?.toString();
    final status = record['status']?.toString();
    final sportId = record['id']?.toString() ?? '';
    if (userId == null || proposedBy != userId || sportId.isEmpty) return;
    if (status != 'approved' && status != 'rejected') return;

    final approved = status == 'approved';
    receiveLocalNotification(
      AppNotification(
        id: 'sport_proposal_result_$sportId',
        professionId: '',
        recipientId: userId,
        category: 'sport',
        eventType: approved
            ? 'sport.proposal_approved'
            : 'sport.proposal_rejected',
        title: approved
            ? 'คำขอเพิ่มประเภทกีฬาได้รับการอนุมัติ'
            : 'คำขอเพิ่มประเภทกีฬาถูกปฏิเสธ',
        body: approved
            ? 'ประเภทกีฬา "${record['name_th'] ?? ''}" พร้อมใช้งานแล้ว'
            : 'เหตุผล: ${record['rejection_reason'] ?? 'ไม่ระบุ'}',
        payload: {
          'route': '/community/sport-club',
          'sportId': sportId,
          'sportName': record['name_th']?.toString() ?? '',
          if (!approved) 'rejectionReason': record['rejection_reason'],
        },
        createdAt:
            DateTime.tryParse(record['reviewed_at']?.toString() ?? '') ??
            DateTime.now(),
      ),
    );
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

  bool _isLocalSportResult(AppNotification notification) =>
      notification.eventType == 'sport.proposal_approved' ||
      notification.eventType == 'sport.proposal_rejected';

  /// การ์ดที่ client synthesize เอง (คำขอ/ผลเสนอกีฬา) ไม่มีแถวจริงให้ repo
  /// นับ — รายการ realtime อื่นถูก persist ใน `app_notifications` ก่อนส่งสดเสมอ
  /// เมื่อ repo อ่าน/นับแถวจริงได้แล้วต้องปล่อยทิ้ง ไม่งั้น badge เบิ้ลกับ
  /// `unreadCount` ที่ repository ส่งกลับมา
  bool _isClientSynthesized(AppNotification notification) =>
      notification.id.startsWith('sport_proposal_');

  void _dropPersistedLocalNotifications() {
    _localNotifications.removeWhere(
      (_, notification) => !_isClientSynthesized(notification),
    );
  }

  @override
  void dispose() {
    _applicationNotificationSubscription.cancel();
    _sportResultChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> loadNotifications({String? category}) async {
    state = state.copyWith(isLoading: true);
    final notifications = await _repo.getNotifications(category: category);
    final unreadCount = await _repo.getUnreadCount(category: category);
    final localResults = _localNotifications.values
        .where(
          (notification) =>
              _isLocalSportResult(notification) &&
              (category == null || notification.category == category),
        )
        .toList();
    final loadedIds = notifications
        .map((notification) => notification.id)
        .toSet();
    _dropPersistedLocalNotifications();
    state = NotificationState(
      isLoading: false,
      notifications: [
        ...notifications,
        ...localResults.where(
          (notification) => !loadedIds.contains(notification.id),
        ),
      ],
      unreadCount: unreadCount,
      localUnreadCount: _localUnreadCount,
    );
  }

  Future<void> refreshUnreadCount({String? category}) async {
    final count = await _repo.getUnreadCount(category: category);
    _dropPersistedLocalNotifications();
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
