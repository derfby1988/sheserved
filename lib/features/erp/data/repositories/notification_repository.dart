import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

class NotificationRepository {
  final SupabaseClient _client;

  NotificationRepository(this._client);

  Future<List<AppNotification>> getNotifications({
    String? category,
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      var query = _client
          .from('app_notifications')
          .select()
          .eq('recipient_id', userId);

      if (category != null) {
        query = query.eq('category', category);
      }
      if (unreadOnly) {
        query = query.eq('is_read', false);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[NotificationRepo] getNotifications error: $e');
      return [];
    }
  }

  Future<int> getUnreadCount({String? category}) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return 0;

      final result = await _client.rpc(
        'get_unread_notification_count',
        params: {
          'p_user_id': userId,
          if (category != null) 'p_category': category,
        },
      );
      return (result as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[NotificationRepo] getUnreadCount error: $e');
      return 0;
    }
  }

  Future<bool> markAsRead(String notificationId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      final result = await _client.rpc(
        'mark_notification_read',
        params: {
          'p_notification_id': notificationId,
          'p_user_id': userId,
        },
      );
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('[NotificationRepo] markAsRead error: $e');
      return false;
    }
  }

  Future<int> markAllAsRead({String? category}) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return 0;

      final result = await _client.rpc(
        'mark_all_notifications_read',
        params: {
          'p_user_id': userId,
          if (category != null) 'p_category': category,
        },
      );
      return (result as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[NotificationRepo] markAllAsRead error: $e');
      return 0;
    }
  }

  Stream<List<AppNotification>> watchNotifications({String? category}) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return Stream.value([]);
    }

    return _client
        .from('app_notifications')
        .stream(primaryKey: ['id'])
        .asyncMap((_) => getNotifications(category: category));
  }
}
