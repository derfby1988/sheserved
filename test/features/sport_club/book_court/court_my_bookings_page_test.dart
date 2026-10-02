import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/auth/data/models/user_model.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_repository.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/pages/court_my_bookings_page.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/services/presence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

void main() {
  setUp(() async {
    await AuthService.instance.logout();
  });

  tearDown(() async {
    await PresenceService.instance.stop();
    await AuthService.instance.logout();
  });

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
        MaterialApp(home: CourtMyBookingsPage(repo: repo)),
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
