import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sheserved/features/chat/data/models/chat_models.dart';
import 'package:sheserved/features/chat/data/repositories/chat_repository.dart';
import 'package:sheserved/features/chat/presentation/chat_unread_provider.dart';
import 'package:sheserved/features/community/find_buddies/presentation/pages/review_proposed_sports_page.dart';
import 'package:sheserved/features/erp/data/repositories/notification_repository.dart';
import 'package:sheserved/features/erp/presentation/providers/notification_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../chat/data/repositories/chat_repository_test.mocks.dart';

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository() : super(Supabase.instance.client);

  @override
  void invalidateCurrentUserCache() {}

  @override
  Future<int> getUnreadCount({
    String? category,
    bool forceRefresh = false,
  }) async => 0;
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

  @override
  Future<void> refresh() async {}
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });

  testWidgets('the fourth card-style tab opens its preview panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatUnreadProvider.overrideWith((ref) => _FakeChatUnreadNotifier()),
          notificationRepositoryProvider.overrideWithValue(
            _FakeNotificationRepository(),
          ),
        ],
        child: const MaterialApp(home: ReviewProposedSportsPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final cardStyleTab = find.text('รูปแบบการ์ด');
    expect(cardStyleTab, findsOneWidget);
    await tester.ensureVisible(cardStyleTab);
    await tester.tap(cardStyleTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBar))).index,
      3,
    );
    expect(find.text('รูปแบบการ์ดสนาม (Book Court)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('court-card-style-classic')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('court-card-style-painter_3d')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
