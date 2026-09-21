import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sheserved/features/chat/data/models/chat_models.dart';
import 'package:sheserved/features/chat/data/repositories/chat_repository.dart';
import 'package:sheserved/features/erp/data/models/app_notification.dart';
import 'package:sheserved/features/chat/presentation/chat_unread_provider.dart';
import 'package:sheserved/features/erp/data/repositories/notification_repository.dart';
import 'package:sheserved/features/erp/presentation/providers/notification_provider.dart';
import 'package:sheserved/shared/widgets/tlz_notification_button.dart';
import 'package:sheserved/shared/widgets/tlz_notification_panel.dart';
import 'package:sheserved/shared/widgets/tlz_notification_toast.dart';
import '../../chat/data/repositories/chat_repository_test.mocks.dart';

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository()
    : super(
        SupabaseClient(
          'https://example.com',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  int unreadCountCalls = 0;

  @override
  Future<int> getUnreadCount({String? category}) async {
    unreadCountCalls++;
    return 4;
  }
}

class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository()
    : super(
        MockSupabaseClient(),
        MockBox<ChatRoom>(),
        MockBox<ChatMessage>(),
        MockBox<ChatParticipant>(),
      );
}

class _FakeChatUnreadNotifier extends ChatUnreadNotifier {
  _FakeChatUnreadNotifier() : super(_FakeChatRepository());

  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
    state = 2;
  }
}

void main() {
  test('builds the Sport Club route for a group reply toast', () {
    final notification = AppNotification(
      id: 'notification-1',
      professionId: '',
      recipientId: 'member-1',
      category: 'chat',
      eventType: 'fitness_group.chat_reply',
      title: 'ตอบกลับคุณในก๊วน',
      createdAt: DateTime.utc(2026, 9, 19),
      payload: const {'groupId': 'group-1', 'chatRoomId': 'room-1'},
    );

    expect(groupChatNotificationRouteArguments(notification), {
      'intent': 'open_chat',
      'groupId': 'group-1',
      'chatRoomId': 'room-1',
    });
  });

  test('strips the mention prefix from a group reply body', () {
    expect(groupChatReplyDisplayBody('@สมชาย ส.\nเจอกันนะ'), 'เจอกันนะ');
    expect(groupChatReplyDisplayBody('ข้อความธรรมดา'), 'ข้อความธรรมดา');
    expect(groupChatReplyDisplayBody(null), '');
  });

  test('resolves a group id from realtime room metadata', () {
    expect(
      fitnessGroupIdFromRoom({
        'id': 'room-uuid',
        'room_type': 'fitness_group',
        'room_ref_id': 'group-1',
      }),
      'group-1',
    );
    expect(
      fitnessGroupIdFromRoom({'id': 'group_group-2', 'room_type': 'direct'}),
      'group-2',
    );
    expect(
      fitnessGroupIdFromRoom({'id': 'direct-room', 'room_type': 'direct'}),
      isNull,
    );
  });

  test('does not route non-group notifications to Sport Club', () {
    final notification = AppNotification(
      id: 'notification-2',
      professionId: '',
      recipientId: 'member-1',
      category: 'system',
      eventType: 'system.notice',
      title: 'แจ้งเตือน',
      createdAt: DateTime.utc(2026, 9, 19),
    );

    expect(groupChatNotificationRouteArguments(notification), isNull);
  });

  test('resolves legacy fitness group room metadata', () {
    final target = fitnessGroupChatTarget({
      'roomId': 'legacy-room-id',
      'roomType': 'fitness_group',
      'roomRefId': 'group-id-1',
    });

    expect(target?.roomId, 'legacy-room-id');
    expect(target?.groupId, 'group-id-1');
  });

  test('resolves new prefixed fitness group room IDs', () {
    final target = fitnessGroupChatTarget({'roomId': 'group_group-id-2'});

    expect(target?.roomId, 'group_group-id-2');
    expect(target?.groupId, 'group-id-2');
  });

  test('does not convert direct chat rooms to group targets', () {
    expect(fitnessGroupChatTarget({'roomId': 'direct-room-id'}), isNull);
  });

  test('opens the admin review page from a sport proposal card', () {
    final notification = AppNotification(
      id: 'sport_proposal_sport-1',
      professionId: '',
      recipientId: 'admin-1',
      category: 'sport',
      eventType: 'sport.proposal_submitted',
      title: 'มีคำขอเพิ่มประเภทกีฬาใหม่',
      createdAt: DateTime.utc(2026, 9, 22),
      payload: const {
        'route': '/community/sport-club/sport/review',
        'sportId': 'sport-1',
      },
    );

    expect(
      notificationPayloadRoute(notification),
      '/community/sport-club/sport/review',
    );
    // การ์ดนี้ไม่ใช่แชทก๊วน จึงไม่ควรได้อาร์กิวเมนต์เปิดแชท
    expect(groupChatNotificationRouteArguments(notification), isNull);
  });

  test('ignores payload routes that are not in-app routes', () {
    final notification = AppNotification(
      id: 'notification-3',
      professionId: '',
      recipientId: 'member-1',
      category: 'system',
      eventType: 'system.notice',
      title: 'แจ้งเตือน',
      createdAt: DateTime.utc(2026, 9, 22),
      payload: const {'route': 'https://example.com/notifications'},
    );

    expect(notificationPayloadRoute(notification), isNull);
  });

  testWidgets(
    'refreshes its unread count on init and app resume without page reload',
    (tester) async {
      final repository = _FakeNotificationRepository();
      final chatNotifier = _FakeChatUnreadNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatUnreadProvider.overrideWith((ref) => chatNotifier),
            notificationRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(body: TlzNotificationButton()),
          ),
        ),
      );
      await tester.pump();

      expect(repository.unreadCountCalls, 1);
      expect(chatNotifier.refreshCalls, 1);
      expect(find.text('6'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(repository.unreadCountCalls, 1);
      expect(chatNotifier.refreshCalls, 1);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(repository.unreadCountCalls, 1);
      expect(chatNotifier.refreshCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(repository.unreadCountCalls, 2);
      expect(chatNotifier.refreshCalls, 2);
      expect(find.text('6'), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(repository.unreadCountCalls, 3);
      expect(chatNotifier.refreshCalls, 3);
    },
  );
}
