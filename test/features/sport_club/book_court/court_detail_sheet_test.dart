import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_repository.dart';
import 'package:sheserved/features/sport_club/book_court/domain/venue_local_time.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_detail_sheet.dart';
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

  List<VenueCourt> courts = const [];
  List<VenueOperatingHours> hours = const [];
  List<VenueReview> reviews = const [];
  CourtAvailability? availability;
  Object? availabilityError;
  DateTime? availabilityFrom;
  DateTime? availabilityTo;
  final List<String> availabilityCourtIds = [];

  @override
  Future<List<VenueCourt>> listPublicCourts(
    String venueId, {
    String? sportId,
  }) async => courts;

  @override
  Future<List<VenueOperatingHours>> listPublicOperatingHours(
    String venueId,
  ) async => hours;

  @override
  Future<List<VenueReview>> listVenueReviews(
    String venueId, {
    int limit = 50,
  }) async => reviews;

  @override
  Future<CourtAvailability> getCourtAvailability(
    String courtId,
    DateTime from,
    DateTime to,
  ) async {
    availabilityCourtIds.add(courtId);
    availabilityFrom = from;
    availabilityTo = to;
    if (availabilityError != null) throw availabilityError!;
    return availability ?? CourtAvailability(courtId: courtId);
  }
}

const _venue = VenueSummary(
  id: 'venue-1',
  name: 'สนามหลังจวน',
  district: 'เมือง',
  province: 'ขอนแก่น',
);

const _instantCourt = VenueCourt(
  id: 'court-1',
  venueId: 'venue-1',
  sportId: 'sport-1',
  name: 'หลังจวนเก่าภูว้า',
  priceAmount: 80,
  pricingUnit: 'hour',
  courtType: 'standard',
  indoor: false,
  unitLabel: 'คอร์ท',
);

const _approvalCourt = VenueCourt(
  id: 'court-2',
  venueId: 'venue-1',
  sportId: 'sport-1',
  name: 'คอร์ทในร่ม',
  approvalMode: BookingApprovalMode.ownerApproval,
  unitLabel: 'คอร์ท',
);

Widget _harness(
  _FakeBookCourtRepository repo, {
  Future<void> Function(VenueCourt court)? onBookCourt,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => CourtDetailSheet.show(
              context,
              venue: _venue,
              repo: repo,
              onBookCourt: onBookCourt,
              onWriteReview: () async {},
            ),
            child: const Text('เปิดรายละเอียด'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('เปิดรายละเอียด'));
  await tester.pumpAndSettle();
}

Future<void> _swipeCourt(WidgetTester tester, String courtId) async {
  await tester.drag(
    find.byKey(ValueKey('court_$courtId')),
    const Offset(-500, 0),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _FakeBookCourtRepository repo;

  setUp(() {
    repo = _FakeBookCourtRepository()..courts = [_instantCourt];
  });

  testWidgets('court actions stay hidden until the row is swiped left', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(repo, onBookCourt: (_) async {}));
    await _openSheet(tester);

    expect(find.text('คอร์ท หลังจวนเก่าภูว้า'), findsOneWidget);
    expect(find.text('ดูตารางว่าง'), findsNothing);
    expect(find.text('จองเลย'), findsNothing);
    expect(
      find.text('ปัดการ์ดสนามไปทางซ้ายเพื่อดูตารางว่างหรือจอง'),
      findsOneWidget,
    );

    await _swipeCourt(tester, 'court-1');

    expect(find.text('ดูตารางว่าง'), findsOneWidget);
    expect(find.text('จองเลย'), findsOneWidget);
  });

  testWidgets('the revealed booking action books that court', (tester) async {
    final booked = <String>[];
    await tester.pumpWidget(
      _harness(repo, onBookCourt: (court) async => booked.add(court.id)),
    );
    await _openSheet(tester);
    await _swipeCourt(tester, 'court-1');

    await tester.tap(find.text('จองเลย'));
    await tester.pumpAndSettle();

    expect(booked, ['court-1']);
  });

  testWidgets('owner-approval courts ask instead of booking instantly', (
    tester,
  ) async {
    repo.courts = [_approvalCourt];
    await tester.pumpWidget(_harness(repo, onBookCourt: (_) async {}));
    await _openSheet(tester);
    await _swipeCourt(tester, 'court-2');

    expect(find.text('รอเจ้าของอนุมัติ'), findsOneWidget);
    expect(find.text('ขอจอง'), findsOneWidget);
    expect(find.text('จองเลย'), findsNothing);
  });

  testWidgets('without a booking callback only availability is offered', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);
    await _swipeCourt(tester, 'court-1');

    expect(find.text('ดูตารางว่าง'), findsOneWidget);
    expect(find.text('จองเลย'), findsNothing);
    expect(find.text('ขอจอง'), findsNothing);
    expect(find.text('ปัดการ์ดสนามไปทางซ้ายเพื่อดูตารางว่าง'), findsOneWidget);
  });

  testWidgets('tapping a court row loads its availability', (tester) async {
    await tester.pumpWidget(_harness(repo, onBookCourt: (_) async {}));
    await _openSheet(tester);

    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(repo.availabilityCourtIds, ['court-1']);
    expect(find.text('ตารางเวลา'), findsOneWidget);
  });

  testWidgets('availability requests use venue-local day boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    final date = VenueLocalTime.today(_venue.timezone);
    final nextDate = VenueLocalTime.addCalendarDays(date, 1);
    expect(
      repo.availabilityFrom!.toUtc(),
      VenueLocalTime.atWallTime(date, _venue.timezone, 0).toUtc(),
    );
    expect(
      repo.availabilityTo!.toUtc(),
      VenueLocalTime.atWallTime(nextDate, _venue.timezone, 0).toUtc(),
    );
  });

  testWidgets('availability failures show an explicit retry instead of slots', (
    tester,
  ) async {
    repo.availabilityError = StateError('offline');
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(find.text('โหลดตารางว่างไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ตารางเวลา'), findsNothing);
    expect(find.text('ลองใหม่'), findsOneWidget);
  });
}
