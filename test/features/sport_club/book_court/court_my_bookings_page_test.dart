import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/auth/data/models/user_model.dart';
import 'package:sheserved/features/chat/data/models/chat_models.dart';
import 'package:sheserved/features/chat/data/repositories/chat_repository.dart';
import 'package:sheserved/features/chat/presentation/chat_unread_provider.dart';
import 'package:sheserved/features/erp/data/repositories/notification_repository.dart';
import 'package:sheserved/features/erp/presentation/providers/notification_provider.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_repository.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/pages/court_my_bookings_page.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/services/presence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../chat/data/repositories/chat_repository_test.mocks.dart';

class _FakeBookCourtRepository extends BookCourtRepository {
  _FakeBookCourtRepository()
    : super(
        SupabaseClient(
          'https://example.com',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  List<VenueBooking> bookings = const [];
  ({DateTime? serverNow, List<VenueBookingGroup> groups}) groupsResult = (
    serverNow: null,
    groups: const [],
  );

  @override
  Future<({DateTime? serverNow, List<VenueBookingGroup> groups})>
  listMyBookingGroups(String userId) async => groupsResult;

  @override
  Future<List<VenueBooking>> listMyBookings(
    String userId, {
    List<String>? statuses,
  }) async => bookings;

  @override
  Future<Set<String>> listMyReviewedBookingIds(String userId) async => const {};

  @override
  Future<List<VenueReviewTag>> listReviewTagCatalog() async => const [];

  @override
  Future<List<VenueReviewCategory>> listReviewCategoryCatalog() async =>
      const [];
}

// The page header now uses TlzAppTopBar — its notification button is a
// Riverpod consumer, so the test needs a ProviderScope with fakes for the
// repositories/notifiers it watches.
class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository()
    : super(
        SupabaseClient(
          'https://example.com',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

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

UserModel _testUser() => UserModel(
  id: 'booker-1',
  userType: UserType.consumer,
  firstName: 'Test',
  lastName: 'Booker',
  username: 'test-booker',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

VenueBooking _booking({
  required String id,
  required String venueName,
  required VenueBookingStatus status,
  required DateTime startsAt,
  required DateTime endsAt,
  DateTime? decidedAt,
}) => VenueBooking(
  id: id,
  courtId: 'court-$id',
  venueId: 'venue-$id',
  sportId: 'sport-1',
  startsAt: startsAt,
  endsAt: endsAt,
  status: status,
  venueName: venueName,
  courtName: 'คอร์ท 1',
  decidedAt: decidedAt,
);

VenueBookingGroup _evidenceGroup(DateTime now) => VenueBookingGroup(
  id: 'group-notified',
  venueId: 'venue-1',
  venueName: 'สนามทดสอบ',
  timezone: 'Asia/Bangkok',
  status: BookingGroupStatus.awaitingEvidence,
  stage: 'payment',
  approvalMode: BookingApprovalMode.ownerApproval,
  totalAmount: 1,
  evidenceDueAt: now.add(const Duration(hours: 1)),
  paymentDestination: '0830103050',
  requirements: const [
    EvidenceRequirement(
      key: 'req_1',
      label: 'สลิปชำระเงิน',
      kind: 'payment_slip',
      stage: 'payment',
      reviewMode: 'auto_verify',
      required: true,
    ),
  ],
  bookings: [
    BookingGroupChild(
      id: 'booking-1',
      courtId: 'court-1',
      courtName: 'คอร์ท 1',
      startsAt: now.add(const Duration(hours: 2)),
      endsAt: now.add(const Duration(hours: 3)),
      status: VenueBookingStatus.awaitingEvidence,
      priceTotal: 1,
    ),
  ],
);

void main() {
  setUp(() async {
    await AuthService.instance.logout();
  });

  tearDown(() async {
    await PresenceService.instance.stop();
    await AuthService.instance.logout();
  });

  testWidgets(
    'opens the notified group evidence sheet when my bookings loads',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await AuthService.instance.login(_testUser());
      final now = DateTime.now();
      final repo = _FakeBookCourtRepository()
        ..groupsResult = (serverNow: now, groups: [_evidenceGroup(now)]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatUnreadProvider.overrideWith((ref) => _FakeChatUnreadNotifier()),
            notificationRepositoryProvider.overrideWithValue(
              _FakeNotificationRepository(),
            ),
          ],
          child: MaterialApp(
            home: CourtMyBookingsPage(
              repo: repo,
              initialGroupId: 'group-notified',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('สนามทดสอบ'), findsNWidgets(2));
      expect(find.text('สลิปชำระเงิน'), findsOneWidget);
      expect(find.text('ยังไม่ได้ส่ง'), findsOneWidget);
      expect(find.text('ส่ง'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await AuthService.instance.logout();
      await PresenceService.instance.stop();
    },
  );

  testWidgets(
    'expired shares the rejected tab and completed has its own reviewable tab',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await AuthService.instance.login(_testUser());
      final repo = _FakeBookCourtRepository();
      final now = DateTime.now();
      repo.bookings = [
        _booking(
          id: 'pending',
          venueName: 'สนามรออนุมัติ',
          status: VenueBookingStatus.pending,
          startsAt: now.add(const Duration(hours: 4)),
          endsAt: now.add(const Duration(hours: 5)),
        ),
        _booking(
          id: 'rejected-old',
          venueName: 'สนามถูกปฏิเสธเก่า',
          status: VenueBookingStatus.rejected,
          startsAt: now.subtract(const Duration(days: 5)),
          endsAt: now.subtract(const Duration(days: 5, hours: -1)),
          decidedAt: now.subtract(const Duration(days: 4)),
        ),
        _booking(
          id: 'rejected-new',
          venueName: 'สนามถูกปฏิเสธใหม่',
          status: VenueBookingStatus.rejected,
          startsAt: now.subtract(const Duration(days: 3)),
          endsAt: now.subtract(const Duration(days: 3, hours: -1)),
          decidedAt: now.subtract(const Duration(days: 1)),
        ),
        _booking(
          id: 'expired',
          venueName: 'สนามหมดอายุ',
          status: VenueBookingStatus.expired,
          startsAt: now.subtract(const Duration(days: 2)),
          endsAt: now.subtract(const Duration(days: 2, hours: -1)),
        ),
        _booking(
          id: 'cancelled',
          venueName: 'สนามยกเลิก',
          status: VenueBookingStatus.cancelled,
          startsAt: now.add(const Duration(days: 2)),
          endsAt: now.add(const Duration(days: 2, hours: 1)),
        ),
        _booking(
          id: 'completed',
          venueName: 'สนามเสร็จสิ้น',
          status: VenueBookingStatus.completed,
          startsAt: now.subtract(const Duration(hours: 3)),
          endsAt: now.subtract(const Duration(hours: 2)),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatUnreadProvider.overrideWith((ref) => _FakeChatUnreadNotifier()),
            notificationRepositoryProvider.overrideWithValue(
              _FakeNotificationRepository(),
            ),
          ],
          child: MaterialApp(home: CourtMyBookingsPage(repo: repo)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('สนามรออนุมัติ'), findsOneWidget);
      expect(find.text('สนามเสร็จสิ้น'), findsNothing);
      expect(find.text('สนามหมดอายุ'), findsNothing);

      await tester.tap(find.text('ถูกปฏิเสธ'));
      await tester.pumpAndSettle();
      expect(find.text('สนามถูกปฏิเสธใหม่'), findsOneWidget);
      expect(find.text('สนามถูกปฏิเสธเก่า'), findsOneWidget);
      expect(find.text('สนามหมดอายุ'), findsOneWidget);
      expect(find.text('สนามยกเลิก'), findsNothing);
      expect(find.text('ปฏิเสธ'), findsNWidgets(2));
      expect(find.text('หมดอายุ'), findsOneWidget);
      expect(find.text('เหตุผลที่หมดอายุ: อนุมัติไม่ทัน'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('สนามถูกปฏิเสธใหม่')).dy,
        lessThan(tester.getTopLeft(find.text('สนามถูกปฏิเสธเก่า')).dy),
      );
      expect(
        tester.getTopLeft(find.text('สนามถูกปฏิเสธเก่า')).dy,
        lessThan(tester.getTopLeft(find.text('สนามหมดอายุ')).dy),
      );

      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(find.text('สนามยกเลิก'), findsOneWidget);
      expect(find.text('สนามหมดอายุ'), findsNothing);

      await tester.tap(find.text('เสร็จสิ้น'));
      await tester.pumpAndSettle();
      expect(find.text('สนามเสร็จสิ้น'), findsOneWidget);
      expect(find.text('เขียนรีวิว'), findsOneWidget);
      expect(find.text('สนามรออนุมัติ'), findsNothing);
      await PresenceService.instance.stop();
    },
  );
}
