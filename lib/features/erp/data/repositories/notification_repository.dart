import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../config/app_config.dart';
import '../../../../core/network/authenticated_http_client.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/websocket_service.dart';
import '../models/app_notification.dart';

class NotificationRepository {
  final SupabaseClient _client;
  static final Map<String, ({DateTime at, List<AppNotification> data})>
  _notificationsCache = {};
  static final Map<String, ({DateTime at, int count})> _unreadCache = {};
  static const _cacheTtl = Duration(seconds: 10);

  NotificationRepository(this._client);

  bool get _useGateway => AppConfig.useBackendAuth;

  /// ตัวตนผู้ใช้ในแอป (`public.users.id`) — โหมด custom auth ไม่มี Supabase
  /// Auth session จึง `auth.currentUser` เป็น null เสมอ ส่วน RPC แจ้งเตือน
  /// ทั้งหมดรับ `p_user_id` เป็น `public.users.id` โดยตรง
  String? get _appUserId =>
      AuthService.instance.userId ?? _client.auth.currentUser?.id;

  /// อ่านครั้งแรกทันทีแล้ว re-fetch ทุกครั้งที่ websocket ส่ง
  /// `application-notification` เข้ามา — โหมด legacy subscribe ตาราง
  /// `app_notifications` ตรง ๆ ไม่ได้เพราะ RLS ใช้ `auth.uid()` ซึ่งเป็น null
  Stream<T> _watchWithSocketRefresh<T>(Future<T> Function() fetch) async* {
    yield await fetch();
    await for (final _ in WebSocketService().applicationNotificationStream) {
      yield await fetch();
    }
  }

  /// true = อ่าน/นับแจ้งเตือนผ่าน backend gateway ซึ่งมองเห็นทุกแถวใน
  /// `app_notifications` (รวมแถวที่ DB trigger สร้าง) — โหมด legacy
  /// (`false`) จะอ่านผ่าน Supabase ตรงและคืน 0 เมื่อไม่มี Supabase Auth session
  bool get usesGateway => _useGateway;

  void _configureGateway() {
    AuthenticatedHttpClient.instance.configure(
      baseUrl: AppConfig.backendApiUrl,
    );
  }

  Future<dynamic> _gatewayRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParams,
  }) async {
    _configureGateway();
    final response = await AuthenticatedHttpClient.instance.request(
      method,
      path,
      body: body == null ? null : jsonEncode(body),
      queryParams: queryParams?.map((key, value) => MapEntry(key, '$value')),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Notification gateway request failed: ${response.statusCode}',
      );
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  AppNotification _fromGatewayJson(Map<String, dynamic> json) {
    return AppNotification.fromJson(json);
  }

  Future<List<AppNotification>> getNotifications({
    String? category,
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    try {
      if (_useGateway) {
        final cacheKey = '${category ?? '*'}:$limit';
        final cached = _notificationsCache[cacheKey];
        if (cached != null &&
            DateTime.now().difference(cached.at) < _cacheTtl) {
          return cached.data;
        }
        final data = await _gatewayRequest(
          'GET',
          '/api/notifications',
          queryParams: {
            if (category != null) 'category': category,
            'limit': limit,
          },
        );
        final notifications = (data as List)
            .map((item) => _fromGatewayJson(Map<String, dynamic>.from(item)))
            .toList();
        _notificationsCache[cacheKey] = (
          at: DateTime.now(),
          data: notifications,
        );
        return notifications;
      }

      final userId = _appUserId;
      if (userId == null) return [];

      final response = await _client.rpc(
        'list_app_notifications',
        params: {
          'p_user_id': userId,
          if (category != null) 'p_category': category,
          'p_limit': limit,
          if (unreadOnly) 'p_unread_only': true,
        },
      );
      return (response as List)
          .map(
            (e) =>
                AppNotification.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (e) {
      debugPrint('[NotificationRepo] getNotifications error: $e');
      return [];
    }
  }

  Future<int> getUnreadCount({String? category}) async {
    try {
      if (_useGateway) {
        final cacheKey = category ?? '*';
        final cached = _unreadCache[cacheKey];
        if (cached != null &&
            DateTime.now().difference(cached.at) < _cacheTtl) {
          return cached.count;
        }
        final data = await _gatewayRequest(
          'GET',
          '/api/notifications/unread-count',
          queryParams: {if (category != null) 'category': category},
        );
        final count = (data as Map<String, dynamic>)['count'] as int? ?? 0;
        _unreadCache[cacheKey] = (at: DateTime.now(), count: count);
        return count;
      }

      final userId = _appUserId;
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

  Stream<int> watchUnreadCount({String? category}) {
    if (_useGateway) {
      // Realtime badge updates come from WebSocketService. Avoid polling every
      // top bar because the backend already rate-limits notification reads.
      return Stream.fromFuture(getUnreadCount(category: category));
    }

    if (_appUserId == null) return Stream.value(0);

    return _watchWithSocketRefresh(() => getUnreadCount(category: category));
  }

  Future<bool> markAsRead(String notificationId) async {
    try {
      if (_useGateway) {
        final data = await _gatewayRequest(
          'POST',
          '/api/notifications/$notificationId/read',
        );
        return (data as Map<String, dynamic>)['success'] == true;
      }

      final userId = _appUserId;
      if (userId == null) return false;

      final result = await _client.rpc(
        'mark_notification_read',
        params: {'p_notification_id': notificationId, 'p_user_id': userId},
      );
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('[NotificationRepo] markAsRead error: $e');
      return false;
    }
  }

  Future<bool> dismissNotification(String notificationId) async {
    try {
      if (_useGateway) {
        final data = await _gatewayRequest(
          'POST',
          '/api/notifications/$notificationId/dismiss',
        );
        return (data as Map<String, dynamic>)['success'] == true;
      }

      final userId = _appUserId;
      if (userId == null) return false;

      final result = await _client.rpc(
        'dismiss_notification',
        params: {'p_notification_id': notificationId, 'p_user_id': userId},
      );
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('[NotificationRepo] dismissNotification error: $e');
      return false;
    }
  }

  Future<int> markAllAsRead({String? category}) async {
    try {
      if (_useGateway) {
        final notifications = await getNotifications(category: category);
        var count = 0;
        for (final notification in notifications.where(
          (item) => !item.isRead,
        )) {
          if (await markAsRead(notification.id)) count++;
        }
        return count;
      }

      final userId = _appUserId;
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
    if (_useGateway) {
      return Stream.fromFuture(getNotifications(category: category));
    }

    if (_appUserId == null) {
      return Stream.value([]);
    }

    return _watchWithSocketRefresh(() => getNotifications(category: category));
  }
}
