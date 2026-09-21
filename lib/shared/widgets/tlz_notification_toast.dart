import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../features/erp/data/models/app_notification.dart';
import '../../features/erp/presentation/providers/notification_provider.dart';
import '../../services/auth_service.dart';
import '../../services/navigation_service.dart';
import '../../services/websocket_service.dart';
import 'swipe_to_dismiss_card.dart';

Map<String, dynamic>? groupChatNotificationRouteArguments(
  AppNotification notification,
) {
  if (notification.eventType != 'fitness_group.chat_reply') return null;

  final payload = notification.payload;
  final groupId =
      payload['groupId']?.toString() ?? payload['group_id']?.toString() ?? '';
  final roomId =
      payload['chatRoomId']?.toString() ??
      payload['chat_room_id']?.toString() ??
      payload['roomId']?.toString() ??
      payload['room_id']?.toString() ??
      '';
  if (groupId.isEmpty || roomId.isEmpty) return null;

  return {'intent': 'open_chat', 'groupId': groupId, 'chatRoomId': roomId};
}

/// เส้นทางปลายทางที่ notification ระบุไว้ใน payload
/// ใช้กับ event ที่ไม่ใช่แชทก๊วน เช่นคำขอเพิ่มประเภทกีฬา (`/community/sport-club/sport/review`)
String? notificationPayloadRoute(AppNotification notification) {
  final route = notification.payload['route']?.toString();
  if (route == null || !route.startsWith('/')) return null;
  return route;
}

/// ตัด prefix mention `@ชื่อ น.\n` ออกเพื่อแสดงเฉพาะเนื้อความจริง
String groupChatReplyDisplayBody(String? content) {
  final raw = (content ?? '').trim();
  if (!raw.startsWith('@')) return raw;
  final separatorIndex = raw.indexOf('\n');
  if (separatorIndex <= 1) return raw;
  return raw.substring(separatorIndex + 1).trim();
}

/// ตรวจว่า room นี้เป็นห้องก๊วนกีฬาหรือไม่ แล้วคืน groupId ที่ต้องใช้เปิดแชท
String? fitnessGroupIdFromRoom(Map<String, dynamic> room) {
  final roomId = room['id']?.toString() ?? '';
  final roomType = room['room_type']?.toString() ?? '';
  final roomRefId = room['room_ref_id']?.toString() ?? '';
  if (roomType == 'fitness_group' && roomRefId.isNotEmpty) return roomRefId;
  if (roomId.startsWith('group_')) {
    final groupId = roomId.substring('group_'.length);
    return groupId.isEmpty ? null : groupId;
  }
  return null;
}

/// การ์ดจางๆ ที่แสดงใต้ Top Bar เมื่อมี notification ใหม่เข้ามา
/// รับได้ 2 ทาง: WebSocket (application-notification) และ Supabase Realtime
/// (ข้อความที่มี `reply_to_sender_id` ตรงกับผู้ใช้ปัจจุบันในห้องก๊วน)
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
  StreamSubscription<Map<String, dynamic>>? _applicationSubscription;
  StreamSubscription<AuthState>? _supabaseAuthSubscription;
  RealtimeChannel? _chatReplyChannel;
  Timer? _hideTimer;
  AppNotification? _current;
  String? _subscribedUserId;
  final Set<String> _seenReplyMessageIds = {};
  final Map<String, Map<String, dynamic>> _roomCache = {};
  final Map<String, String> _userNameCache = {};

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

    _applicationSubscription = WebSocketService().applicationNotificationStream
        .listen(_onNotification);

    // Supabase Realtime เป็นช่องทางฟรีที่ใช้ในแอปอยู่แล้ว จึงไม่ต้องพึ่ง
    // websocket-server สำหรับแจ้งเตือนการตอบกลับในห้องก๊วน
    AuthService.instance.addListener(_handleAuthChanged);
    try {
      _supabaseAuthSubscription = Supabase
          .instance
          .client
          .auth
          .onAuthStateChange
          .listen((_) => _handleAuthChanged());
    } catch (e) {
      debugPrint('[TlzNotificationToast] supabase auth listen error: $e');
    }
    _subscribeChatReplies();
  }

  void _handleAuthChanged() {
    if (!mounted) return;
    _subscribeChatReplies();
  }

  /// รองรับทั้ง backend auth (AuthService) และ Supabase session โดยตรง
  String? _resolveChatReplyUserId() {
    final authUserId = AuthService.instance.currentUser?.id;
    if (authUserId != null && authUserId.isNotEmpty) return authUserId;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  void _subscribeChatReplies() {
    final userId = _resolveChatReplyUserId();
    if (userId == _subscribedUserId) return;

    _chatReplyChannel?.unsubscribe();
    _chatReplyChannel = null;
    _subscribedUserId = userId;
    _seenReplyMessageIds.clear();
    if (userId == null) return;

    try {
      _chatReplyChannel = Supabase.instance.client
          .channel('chat_reply_toast_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'reply_to_sender_id',
              value: userId,
            ),
            callback: _onChatReplyInsert,
          )
          .subscribe();
      debugPrint('[TlzNotificationToast] subscribed chat replies for $userId');
    } catch (e) {
      debugPrint('[TlzNotificationToast] chat reply subscribe error: $e');
    }
  }

  Future<void> _onChatReplyInsert(PostgresChangePayload payload) async {
    final record = payload.newRecord;
    final senderId = record['sender_id']?.toString() ?? '';
    final myUserId = _subscribedUserId;
    if (!mounted || myUserId == null || senderId.isEmpty) return;
    if (senderId == myUserId) return;

    final messageId = record['id']?.toString() ?? '';
    if (messageId.isEmpty || !_seenReplyMessageIds.add(messageId)) return;

    final roomId = record['room_id']?.toString() ?? '';
    if (roomId.isEmpty) return;

    try {
      final room = await _roomInfo(roomId);
      if (room == null) return;
      final groupId = fitnessGroupIdFromRoom(room);
      if (groupId == null) return;

      final senderName = await _userDisplayName(senderId);
      final groupName = room['title']?.toString().trim();
      final notification = AppNotification(
        id: 'fitness_group_chat_reply_$messageId',
        professionId: '',
        recipientId: myUserId,
        category: 'chat',
        eventType: 'fitness_group.chat_reply',
        title:
            '$senderName ตอบกลับคุณใน ${groupName?.isNotEmpty == true ? groupName : 'ก๊วนกีฬา'}',
        body: groupChatReplyDisplayBody(record['content']?.toString()),
        payload: {
          'route': '/community/sport-club',
          'intent': 'open_chat',
          'groupId': groupId,
          'chatRoomId': roomId,
          'messageId': messageId,
          'senderId': senderId,
        },
        createdAt:
            DateTime.tryParse(record['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
      if (!mounted) return;
      _showNotification(notification);
    } catch (e) {
      debugPrint('[TlzNotificationToast] chat reply lookup error: $e');
    }
  }

  Future<Map<String, dynamic>?> _roomInfo(String roomId) async {
    final cached = _roomCache[roomId];
    if (cached != null) return cached;
    final response = await Supabase.instance.client
        .from('chat_rooms')
        .select('id, title, room_type, room_ref_id')
        .eq('id', roomId)
        .maybeSingle();
    if (response == null) return null;
    final room = Map<String, dynamic>.from(response);
    _roomCache[roomId] = room;
    return room;
  }

  Future<String> _userDisplayName(String userId) async {
    final cached = _userNameCache[userId];
    if (cached != null) return cached;
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('first_name, last_name')
          .eq('id', userId)
          .maybeSingle();
      final name = [response?['first_name'], response?['last_name']]
          .map((value) => value?.toString().trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .join(' ');
      final resolved = name.isEmpty ? 'สมาชิกก๊วน' : name;
      _userNameCache[userId] = resolved;
      return resolved;
    } catch (_) {
      return 'สมาชิกก๊วน';
    }
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

    _showNotification(notification);
  }

  void _showNotification(AppNotification notification) {
    if (!mounted) return;
    _hideTimer?.cancel();
    _controller.stop();

    // ถ้าการ์ดกำลังแสดงอยู่ → อัปเดตเนื้อหา + รีเซ็ต hold timer (ไม่ต้อง animate ใหม่)
    if (_controller.value > 0 && _current != null) {
      setState(() => _current = notification);
      _hideTimer = Timer(_holdDuration, () {
        if (mounted) _hideCurrent();
      });
      return;
    }

    // ไม่ได้แสดง → เริ่มแอนิเมชันใหม่
    setState(() => _current = notification);
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

  void _openCurrentNotification() {
    final notification = _current;
    if (notification == null) return;

    final chatArguments = groupChatNotificationRouteArguments(notification);
    if (chatArguments != null) {
      _hideCurrent();
      NavigationService.navigatorKey.currentState?.pushNamed(
        '/community/sport-club',
        arguments: chatArguments,
      );
      return;
    }

    // event อื่นที่ระบุ route ปลายทางมาใน payload (เช่นคำขอเพิ่มประเภทกีฬา)
    final route = notificationPayloadRoute(notification);
    if (route == null) return;
    _hideCurrent();
    NavigationService.navigatorKey.currentState?.pushNamed(route);
  }

  /// การ์ดปัจจุบันกดเปิดปลายทางได้หรือไม่ (แชทก๊วน หรือ route ใน payload)
  bool _isCurrentOpenable() {
    final notification = _current;
    if (notification == null) return false;
    return groupChatNotificationRouteArguments(notification) != null ||
        notificationPayloadRoute(notification) != null;
  }

  /// ปัดซ้ายเพื่อยกเลิกรายการแจ้งเตือนนั้น
  /// ปิดการ์ดทันที แล้วแจ้ง provider เพื่อ mark dismissed (non-blocking)
  void _dismissCurrent() {
    final notification = _current;
    _hideTimer?.cancel();
    _controller.stop();
    setState(() => _current = null);
    if (notification == null ||
        notification.eventType == 'fitness_group.chat_reply') {
      return;
    }
    ref
        .read(notificationProvider.notifier)
        .dismissNotification(notification.id, category: notification.category);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    _applicationSubscription?.cancel();
    _supabaseAuthSubscription?.cancel();
    _chatReplyChannel?.unsubscribe();
    AuthService.instance.removeListener(_handleAuthChanged);
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
      child: SwipeToDismissCard(
        key: ValueKey('tlz_notification_toast_${_current!.id}'),
        backgroundRadius: 20,
        onTap: _isCurrentOpenable() ? _openCurrentNotification : null,
        onDismissed: _dismissCurrent,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _opacity,
            child: _ToastCard(notification: _current!),
          ),
        ),
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
