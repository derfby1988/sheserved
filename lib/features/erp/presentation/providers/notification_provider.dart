import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/app_notification.dart';
import '../../data/repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(Supabase.instance.client);
});

class NotificationState {
  final bool isLoading;
  final List<AppNotification> notifications;
  final int unreadCount;
  final String? errorMessage;

  const NotificationState({
    this.isLoading = false,
    this.notifications = const [],
    this.unreadCount = 0,
    this.errorMessage,
  });

  NotificationState copyWith({
    bool? isLoading,
    List<AppNotification>? notifications,
    int? unreadCount,
    String? errorMessage,
  }) {
    return NotificationState(
      isLoading: isLoading ?? this.isLoading,
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      errorMessage: errorMessage,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  final NotificationRepository _repo;

  NotificationNotifier(this._repo) : super(const NotificationState());

  Future<void> loadNotifications({String? category}) async {
    state = state.copyWith(isLoading: true);
    final notifications = await _repo.getNotifications(category: category);
    final unreadCount = await _repo.getUnreadCount(category: category);
    state = NotificationState(
      isLoading: false,
      notifications: notifications,
      unreadCount: unreadCount,
    );
  }

  Future<void> refreshUnreadCount({String? category}) async {
    final count = await _repo.getUnreadCount(category: category);
    state = state.copyWith(unreadCount: count);
  }

  Future<void> markAsRead(String notificationId) async {
    await _repo.markAsRead(notificationId);
    await loadNotifications();
  }

  Future<void> markAllAsRead({String? category}) async {
    await _repo.markAllAsRead(category: category);
    await loadNotifications();
  }
}

final notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier(ref.read(notificationRepositoryProvider));
});

final notificationUnreadCountProvider =
    StreamProvider.family<int, String?>((ref, category) {
  return ref
      .watch(notificationRepositoryProvider)
      .watchUnreadCount(category: category);
});
