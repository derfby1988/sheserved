import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_repository.dart';
import 'package:sheserved/features/sport_club/book_court/domain/venue_local_time.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_availability_picker.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_detail_sheet.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';
import 'package:sheserved/shared/widgets/thai_buddhist_date_picker.dart';
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
  VenueOwnerPublicProfile? ownerProfile;
  Object? ownerProfileError;
  CourtAvailability? availability;
  Object? availabilityError;
  DateTime? availabilityFrom;
  DateTime? availabilityTo;
  final List<CourtAvailability> availabilityResponses = [];
  final List<String> availabilityCourtIds = [];
  List<VenueBooking> myBookings = const [];
  final List<String> cancelledBookingIds = [];
  Object? cancelError;

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
  Future<VenueOwnerPublicProfile?> getPublicVenueOwnerProfile(
    String venueId,
  ) async {
    if (ownerProfileError != null) throw ownerProfileError!;
    return ownerProfile;
  }

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
    if (availabilityResponses.isNotEmpty) {
      return availabilityResponses.removeAt(0);
    }
    return availability ?? CourtAvailability(courtId: courtId);
  }

  @override
  Future<List<VenueBooking>> listMyBookings(
    String userId, {
    List<String>? statuses,
  }) async => myBookings;

  @override
  Future<void> cancelBooking(
    String userId,
    String bookingId, {
    String? reason,
  }) async {
    if (cancelError != null) throw cancelError!;
    cancelledBookingIds.add(bookingId);
    myBookings = myBookings.where((b) => b.id != bookingId).toList();
  }
}

CourtAvailability _openAvailability({
  List<({DateTime startsAt, DateTime endsAt})> booked = const [],
  List<({DateTime startsAt, DateTime endsAt})> blocked = const [],
  DateTime? serverNow,
}) => CourtAvailability(
  courtId: 'court-1',
  serverNow: serverNow,
  booked: booked,
  blocked: blocked,
  hours: [
    for (var day = 0; day < 7; day++)
      VenueOperatingHours(
        dayOfWeek: day,
        openTime: '06:00',
        closeTime: '23:00',
      ),
  ],
);

/// One week of hours with a distinct window per weekday so a test can tell
/// which day's line is on screen.
List<VenueOperatingHours> _weekHours() => [
  for (var day = 0; day < 7; day++)
    VenueOperatingHours(
      dayOfWeek: day,
      openTime: '0$day:00',
      closeTime: '1$day:00',
    ),
];

Future<void> _selectAvailabilityDate(
  WidgetTester tester,
  DateTime date, {
  DateTime? fromDate,
}) async {
  final currentDate = fromDate ?? VenueLocalTime.today(_venue.timezone);
  await tester.tap(find.byKey(const ValueKey('court_availability_date')));
  await tester.pumpAndSettle();
  if (currentDate.year != date.year || currentDate.month != date.month) {
    await tester.tap(find.bySemanticsLabel('เดือนถัดไป'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('${date.day}'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('ยืนยัน'));
  await tester.pumpAndSettle();
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

VenueBooking _booking({
  required String id,
  required String venueName,
  required DateTime startsAt,
  required DateTime endsAt,
  VenueBookingStatus status = VenueBookingStatus.confirmed,
}) => VenueBooking(
  id: id,
  courtId: 'court-1',
  venueId: 'venue-1',
  sportId: 'sport-1',
  startsAt: startsAt,
  endsAt: endsAt,
  status: status,
  venueName: venueName,
  courtName: 'หลังจวนเก่าภูว้า',
  unitLabel: 'คอร์ท',
  priceTotal: 180,
);

Widget _harness(
  _FakeBookCourtRepository repo, {
  CourtBookingCallback? onBookCourt,
  DateTime? now,
  bool canManageAvailability = false,
  Future<void> Function()? onOpenMyBookings,
  String? userId = 'user-1',
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
              userId: userId,
              now: now,
              canManageAvailability: canManageAvailability,
              onBookCourt: onBookCourt,
              onWriteReview: () async {},
              onOpenMyBookings: onOpenMyBookings,
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

  testWidgets('operating hours collapse to today until the card is tapped', (
    tester,
  ) async {
    repo.hours = _weekHours();
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    final todayDow = VenueLocalTime.now(_venue.timezone).weekday % 7;
    final tomorrowDow = (todayDow + 1) % 7;

    expect(find.text('เวลาเปิด-ปิด'), findsOneWidget);
    expect(find.text('ดูทั้งสัปดาห์'), findsOneWidget);
    expect(find.text('0$todayDow.00 - 1$todayDow.00 น.'), findsOneWidget);
    expect(find.text('0$tomorrowDow.00 - 1$tomorrowDow.00 น.'), findsNothing);

    await tester.tap(find.text('ดูทั้งสัปดาห์'));
    await tester.pumpAndSettle();

    expect(find.text('ดูทั้งสัปดาห์'), findsNothing);
    expect(find.text('ซ่อน'), findsOneWidget);
    for (var day = 0; day < 7; day++) {
      expect(find.text('0$day.00 - 1$day.00 น.'), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.text('จันทร์')).dy,
      lessThan(tester.getTopLeft(find.text('อาทิตย์')).dy),
    );

    await tester.tap(find.text('ซ่อน'));
    await tester.pumpAndSettle();

    expect(find.text('ดูทั้งสัปดาห์'), findsOneWidget);
    expect(find.text('ซ่อน'), findsNothing);
    expect(find.text('0$tomorrowDow.00 - 1$tomorrowDow.00 น.'), findsNothing);
  });

  testWidgets("today's hours say near opening before opening time", (
    tester,
  ) async {
    final date = DateTime(2040, 1, 1);
    final now = VenueLocalTime.atWallTime(date, _venue.timezone, 11, 53);
    repo.hours = [
      VenueOperatingHours(
        dayOfWeek: now.weekday % 7,
        openTime: '14:00',
        closeTime: '22:00',
      ),
    ];
    await tester.pumpWidget(_harness(repo, now: now));
    await _openSheet(tester);

    expect(find.text('ใกล้เปิด'), findsOneWidget);
    expect(find.text('ปิดแล้ว'), findsNothing);
  });

  testWidgets("today's hours stay closed after closing time", (tester) async {
    final date = DateTime(2040, 1, 1);
    final now = VenueLocalTime.atWallTime(date, _venue.timezone, 23);
    repo.hours = [
      VenueOperatingHours(
        dayOfWeek: now.weekday % 7,
        openTime: '14:00',
        closeTime: '22:00',
      ),
    ];
    await tester.pumpWidget(_harness(repo, now: now));
    await _openSheet(tester);

    expect(find.text('ปิดแล้ว'), findsOneWidget);
    expect(find.text('ใกล้เปิด'), findsNothing);
  });

  testWidgets("only today's hours line carries a live open badge", (
    tester,
  ) async {
    repo.hours = [
      for (var day = 0; day < 7; day++)
        VenueOperatingHours(
          dayOfWeek: day,
          openTime: '00:00',
          closeTime: '24:00',
        ),
    ];
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    expect(find.text('เปิดอยู่'), findsOneWidget);
    expect(find.text('ปิดแล้ว'), findsNothing);

    await tester.tap(find.text('ดูทั้งสัปดาห์'));
    await tester.pumpAndSettle();

    // The whole week shows, but only today's row can claim a live status.
    expect(find.text('เปิดอยู่'), findsOneWidget);
  });

  testWidgets('court actions stay hidden until the row is swiped left', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        repo,
        onBookCourt: (_, {initialDate, initialSlotStart}) async {},
      ),
    );
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

  testWidgets('verified venue managers get a manage-time action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        repo,
        canManageAvailability: true,
        onBookCourt: (_, {initialDate, initialSlotStart}) async {},
      ),
    );
    await _openSheet(tester);

    expect(
      find.text('ปัดการ์ดสนามไปทางซ้ายเพื่อดูตารางว่างหรือจัดการเวลา'),
      findsOneWidget,
    );
    await _swipeCourt(tester, 'court-1');

    expect(find.text('จัดการเวลา'), findsOneWidget);
    expect(find.text('จองเลย'), findsNothing);
  });

  testWidgets('the courts section invites picking the shared resource unit', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    expect(find.text('เลือกคอร์ทเพื่อระบุเวลาจอง'), findsOneWidget);
    expect(find.text('รายการที่จองได้'), findsNothing);
  });

  testWidgets('mixed resource labels fall back to the generic รายการ wording', (
    tester,
  ) async {
    repo.courts = [
      _instantCourt,
      const VenueCourt(
        id: 'court-9',
        venueId: 'venue-1',
        sportId: 'sport-1',
        name: 'โต๊ะพูล 1',
        unitLabel: 'โต๊ะ',
      ),
    ];
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    expect(find.text('เลือกรายการเพื่อระบุเวลาจอง'), findsOneWidget);
    expect(find.text('เลือกคอร์ทเพื่อระบุเวลาจอง'), findsNothing);
  });

  testWidgets('the revealed booking action books that court', (tester) async {
    final booked = <String>[];
    await tester.pumpWidget(
      _harness(
        repo,
        onBookCourt: (court, {initialDate, initialSlotStart}) async =>
            booked.add(court.id),
      ),
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
    await tester.pumpWidget(
      _harness(
        repo,
        onBookCourt: (_, {initialDate, initialSlotStart}) async {},
      ),
    );
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
    await tester.pumpWidget(
      _harness(
        repo,
        onBookCourt: (_, {initialDate, initialSlotStart}) async {},
      ),
    );
    await _openSheet(tester);

    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(repo.availabilityCourtIds, ['court-1']);
    expect(find.byType(CourtAvailabilityPicker), findsOneWidget);
  });

  testWidgets('a finished booking reloads only the visible availability', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        repo,
        onBookCourt: (_, {initialDate, initialSlotStart}) async {},
      ),
    );
    await _openSheet(tester);
    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();
    expect(repo.availabilityCourtIds, ['court-1']);

    await _swipeCourt(tester, 'court-1');
    await tester.tap(find.text('จองเลย'));
    await tester.pumpAndSettle();

    expect(repo.availabilityCourtIds, ['court-1', 'court-1']);
    expect(find.byType(CourtAvailabilityPicker), findsOneWidget);
  });

  testWidgets('booking without a visible grid does not load availability', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        repo,
        onBookCourt: (_, {initialDate, initialSlotStart}) async {},
      ),
    );
    await _openSheet(tester);
    await _swipeCourt(tester, 'court-1');

    await tester.tap(find.text('จองเลย'));
    await tester.pumpAndSettle();

    expect(repo.availabilityCourtIds, isEmpty);
    expect(find.byType(CourtAvailabilityPicker), findsNothing);
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

  testWidgets('owners can open management by tapping a suspended slot', (
    tester,
  ) async {
    final date = VenueLocalTime.today(_venue.timezone);
    final slot = CourtAvailabilityPicker.hourlySlots(
      date,
      timezone: _venue.timezone,
    ).singleWhere((candidate) => candidate.start.hour == 18);
    repo.availability = _openAvailability(
      blocked: [(startsAt: slot.start, endsAt: slot.end)],
      serverNow: VenueLocalTime.atWallTime(date, _venue.timezone, 6),
    );
    final bookingRequests =
        <({String courtId, DateTime? date, DateTime? start})>[];
    await tester.pumpWidget(
      _harness(
        repo,
        canManageAvailability: true,
        onBookCourt: (court, {initialDate, initialSlotStart}) async {
          bookingRequests.add((
            courtId: court.id,
            date: initialDate,
            start: initialSlotStart,
          ));
        },
      ),
    );
    await _openSheet(tester);
    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(find.text('ระงับชั่วคราว'), findsOneWidget);
    expect(find.text('ไม่พร้อม'), findsNothing);
    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();

    expect(bookingRequests, hasLength(1));
    expect(bookingRequests.single.courtId, 'court-1');
    expect(bookingRequests.single.date, date);
    expect(bookingRequests.single.start!.isAtSameMomentAs(slot.start), isTrue);
  });

  testWidgets('regular users cannot tap a suspended slot', (tester) async {
    final date = VenueLocalTime.today(_venue.timezone);
    final slot = CourtAvailabilityPicker.hourlySlots(
      date,
      timezone: _venue.timezone,
    ).singleWhere((candidate) => candidate.start.hour == 18);
    repo.availability = _openAvailability(
      blocked: [(startsAt: slot.start, endsAt: slot.end)],
      serverNow: VenueLocalTime.atWallTime(date, _venue.timezone, 6),
    );
    var bookingCalls = 0;
    await tester.pumpWidget(
      _harness(
        repo,
        onBookCourt: (_, {initialDate, initialSlotStart}) async {
          bookingCalls++;
        },
      ),
    );
    await _openSheet(tester);
    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();

    expect(bookingCalls, 0);
  });

  testWidgets(
    'tapping a slot rechecks availability and opens booking with it selected',
    (tester) async {
      repo.availability = _openAvailability();
      final date = VenueLocalTime.addCalendarDays(
        VenueLocalTime.today(_venue.timezone),
        1,
      );
      final slot = CourtAvailabilityPicker.hourlySlots(
        date,
        timezone: _venue.timezone,
      ).singleWhere((candidate) => candidate.start.hour == 18);
      final bookingRequests =
          <({String courtId, DateTime? date, DateTime? start})>[];
      await tester.pumpWidget(
        _harness(
          repo,
          onBookCourt: (court, {initialDate, initialSlotStart}) async {
            bookingRequests.add((
              courtId: court.id,
              date: initialDate,
              start: initialSlotStart,
            ));
          },
        ),
      );
      await _openSheet(tester);
      await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
      await tester.pumpAndSettle();
      await _selectAvailabilityDate(tester, date);

      await tester.tap(find.text('18:00'));
      await tester.pumpAndSettle();

      expect(bookingRequests, hasLength(1));
      expect(bookingRequests.single.courtId, 'court-1');
      expect(bookingRequests.single.date, date);
      expect(
        bookingRequests.single.start!.isAtSameMomentAs(slot.start),
        isTrue,
      );
      expect(repo.availabilityCourtIds, [
        'court-1',
        'court-1',
        'court-1',
        'court-1',
      ]);
    },
  );

  testWidgets(
    'a slot no longer available is reported and only availability reloads',
    (tester) async {
      final date = VenueLocalTime.addCalendarDays(
        VenueLocalTime.today(_venue.timezone),
        1,
      );
      final slot = CourtAvailabilityPicker.hourlySlots(
        date,
        timezone: _venue.timezone,
      ).singleWhere((candidate) => candidate.start.hour == 18);
      final free = _openAvailability();
      final booked = _openAvailability(
        booked: [(startsAt: slot.start, endsAt: slot.end)],
      );
      repo.availability = free;
      repo.availabilityResponses.addAll([free, free, booked, booked]);
      var bookingCalls = 0;
      await tester.pumpWidget(
        _harness(
          repo,
          onBookCourt: (_, {initialDate, initialSlotStart}) async {
            bookingCalls++;
          },
        ),
      );
      await _openSheet(tester);
      await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
      await tester.pumpAndSettle();
      await _selectAvailabilityDate(tester, date);

      await tester.tap(find.text('18:00'));
      await tester.pumpAndSettle();

      expect(bookingCalls, 0);
      expect(repo.availabilityCourtIds, [
        'court-1',
        'court-1',
        'court-1',
        'court-1',
      ]);
      expect(
        find.text('เวลานี้ไม่ว่างแล้ว กรุณาเลือกเวลาอื่น'),
        findsOneWidget,
      );
      expect(find.byTooltip('ถูกจอง'), findsOneWidget);
    },
  );

  testWidgets('availability failures show an explicit retry instead of slots', (
    tester,
  ) async {
    repo.availabilityError = StateError('offline');
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(find.text('โหลดตารางว่างไม่สำเร็จ'), findsOneWidget);
    expect(find.byType(CourtAvailabilityPicker), findsNothing);
    expect(find.text('ลองใหม่'), findsOneWidget);
  });

  testWidgets('time-priced courts show their hourly starting price', (
    tester,
  ) async {
    repo.courts = [
      const VenueCourt(
        id: 'court-1',
        venueId: 'venue-1',
        sportId: 'sport-1',
        name: 'หลังจวนเก่าภูว้า',
        priceAmount: 100,
        pricingUnit: 'hour',
        startingPriceAmount: 65,
        hasTimePricing: true,
        unitLabel: 'คอร์ท',
      ),
    ];
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    expect(find.text('เริ่มต้น 65 ฿/ชม.'), findsOneWidget);
  });

  testWidgets('owner profile RPC failures keep venue details available', (
    tester,
  ) async {
    repo.ownerProfileError = StateError('RPC_NOT_FOUND');
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    expect(find.text('สนามหลังจวน'), findsOneWidget);
    expect(find.text('ยังไม่มีรีวิว'), findsOneWidget);
    expect(find.text('เจ้าของสถานที่'), findsNothing);
  });

  testWidgets('review section loads the owner avatar and name', (tester) async {
    repo.ownerProfile = const VenueOwnerPublicProfile(
      displayName: 'สมชาย ศ.',
      avatarUrl: 'https://example.invalid/avatar.png',
    );
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    expect(find.text('เจ้าของสถานที่'), findsOneWidget);
    expect(find.text('สมชาย ศ.'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('booking history button invokes its navigation callback', (
    tester,
  ) async {
    var openedHistory = false;
    await tester.pumpWidget(
      _harness(repo, onOpenMyBookings: () async => openedHistory = true),
    );
    await _openSheet(tester);

    final historyButton = find.text('ประวัติการจองของฉัน');
    expect(historyButton, findsOneWidget);
    await tester.ensureVisible(historyButton);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(historyButton).dy,
      greaterThan(tester.getBottomLeft(find.text('คอร์ท หลังจวนเก่าภูว้า')).dy),
    );

    await tester.tap(historyButton);
    await tester.pumpAndSettle();

    expect(openedHistory, isTrue);
  });

  testWidgets('the close button dismisses the sheet', (tester) async {
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    expect(find.byType(CourtDetailSheet), findsOneWidget);
    expect(find.byType(NeumorphicSheetCloseButton), findsOneWidget);

    await tester.tap(find.byType(NeumorphicSheetCloseButton));
    await tester.pumpAndSettle();

    expect(find.byType(CourtDetailSheet), findsNothing);
  });

  testWidgets('court rows are sunken fields that open their grid underneath', (
    tester,
  ) async {
    repo.availability = _openAvailability();
    await tester.pumpWidget(
      _harness(
        repo,
        onBookCourt: (_, {initialDate, initialSlotStart}) async {},
      ),
    );
    await _openSheet(tester);

    expect(find.text('ตารางว่าง'), findsNothing);
    expect(find.byType(NeumorphicInsetBox), findsOneWidget);

    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(find.byType(CourtAvailabilityPicker), findsOneWidget);
    expect(find.text('ตารางว่าง'), findsOneWidget);
    expect(find.text('เวลาเปิดรับจอง: 09:00'), findsNothing);
    expect(find.text('เปิดจองล่วงหน้าได้ไม่จำกัดวัน'), findsNothing);
    expect(find.textContaining('เวลาท้องถิ่นของ'), findsNothing);
    expect(
      tester.getTopLeft(find.text('ตารางว่าง')).dy,
      greaterThan(tester.getBottomLeft(find.text('คอร์ท หลังจวนเก่าภูว้า')).dy),
    );

    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(find.text('ตารางว่าง'), findsNothing);
    expect(find.byType(NeumorphicInsetBox), findsOneWidget);
  });

  testWidgets('availability date selector uses relative and weekday labels', (
    tester,
  ) async {
    final today = DateTime(2026, 10, 5);
    final tomorrow = VenueLocalTime.addCalendarDays(today, 1);
    final wednesday = VenueLocalTime.addCalendarDays(today, 2);
    final now = VenueLocalTime.atWallTime(today, _venue.timezone, 11, 53);
    repo.availability = _openAvailability();
    await tester.pumpWidget(_harness(repo, now: now));
    await _openSheet(tester);
    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(find.text('วันนี้'), findsOneWidget);
    final dateButton = find.byKey(const ValueKey('court_availability_date'));
    expect(tester.widget<NeumorphicPillButton>(dateButton).text, 'วันนี้');
    await _selectAvailabilityDate(tester, tomorrow, fromDate: today);
    expect(tester.widget<NeumorphicPillButton>(dateButton).text, 'พรุ่งนี้');
    await _selectAvailabilityDate(tester, wednesday, fromDate: tomorrow);
    expect(find.text('พ. 7 ต.ค.'), findsOneWidget);
    expect(find.text('พ. 7 ต.ค. 69'), findsNothing);
  });

  testWidgets('availability date in another Buddhist year keeps short year', (
    tester,
  ) async {
    final today = DateTime(2026, 12, 31);
    final nextYearDate = DateTime(2027, 1, 2);
    final now = VenueLocalTime.atWallTime(today, _venue.timezone, 11, 53);
    repo.availability = _openAvailability();
    await tester.pumpWidget(_harness(repo, now: now));
    await _openSheet(tester);
    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(find.text('วันนี้'), findsOneWidget);
    await _selectAvailabilityDate(tester, nextYearDate, fromDate: today);

    expect(find.text('ส. 2 ม.ค. 70'), findsOneWidget);
  });

  testWidgets(
    'venue release applies on weekdays and court override applies Saturday',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final today = VenueLocalTime.today(_venue.timezone);
      final venueDateOffset = List.generate(7, (offset) => offset).firstWhere((
        offset,
      ) {
        final day = VenueLocalTime.addCalendarDays(today, offset);
        final weekDay = day.weekday % DateTime.daysPerWeek;
        return weekDay >= 1 && weekDay <= 5;
      });
      final venueDate = VenueLocalTime.addCalendarDays(today, venueDateOffset);
      final saturdayOffset = List.generate(7, (offset) => offset + 1)
          .firstWhere(
            (offset) =>
                VenueLocalTime.addCalendarDays(venueDate, offset).weekday %
                    DateTime.daysPerWeek ==
                6,
          );
      final saturday = VenueLocalTime.addCalendarDays(
        venueDate,
        saturdayOffset,
      );
      CourtBookingRelease releaseForDate(String? selectedDayTime) =>
          CourtBookingRelease(
            mode: 'custom',
            dayOfWeek: 1,
            daysOfWeek: [1, 2, 3, 4, 5, 6],
            releaseTime: '10:00:00',
            windowDays: 7,
            selectedDayReleaseTime: selectedDayTime,
          );
      final hours = [
        for (var day = 0; day < DateTime.daysPerWeek; day++)
          VenueOperatingHours(
            dayOfWeek: day,
            openTime: '06:00',
            closeTime: '23:00',
          ),
      ];
      repo.courts = [_instantCourt];
      repo.availabilityResponses.addAll([
        CourtAvailability(
          courtId: 'court-1',
          hours: hours,
          release: releaseForDate(null),
        ),
        CourtAvailability(
          courtId: 'court-1',
          hours: hours,
          release: releaseForDate('09:00:00'),
        ),
        CourtAvailability(
          courtId: 'court-1',
          hours: hours,
          release: releaseForDate('10:00:00'),
        ),
      ]);
      await tester.pumpWidget(_harness(repo));
      await _openSheet(tester);

      await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
      await tester.pumpAndSettle();
      await _selectAvailabilityDate(tester, venueDate);

      expect(find.text('เวลาเปิดรับจอง: 09:00'), findsOneWidget);

      await _selectAvailabilityDate(tester, saturday, fromDate: venueDate);

      expect(find.text('เวลาเปิดรับจอง: 10:00'), findsOneWidget);
      expect(find.textContaining('Asia/Bangkok'), findsNothing);
    },
  );

  testWidgets(
    'sealed slots name the release date even when it is earlier than the date',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final today = VenueLocalTime.today(_venue.timezone);
      final releaseDate = VenueLocalTime.addCalendarDays(today, 1);
      final opensAt = VenueLocalTime.atWallTime(
        releaseDate,
        _venue.timezone,
        9,
      );
      repo.availability = CourtAvailability(
        courtId: 'court-1',
        serverNow: VenueLocalTime.now(_venue.timezone),
        hours: [
          for (var day = 0; day < DateTime.daysPerWeek; day++)
            VenueOperatingHours(
              dayOfWeek: day,
              openTime: '06:00',
              closeTime: '23:00',
            ),
        ],
        release: CourtBookingRelease(
          mode: 'inherit',
          dayOfWeek: 1,
          daysOfWeek: [1, 2, 3, 4, 5],
          releaseTime: '09:00:00',
          windowDays: 7,
          selectedDayReleaseTime: '09:00:00',
          selectedDayOpensAt: opensAt,
        ),
        notOpen: [
          for (var hour = 6; hour < 23; hour++)
            (
              slotStart: VenueLocalTime.atWallTime(
                today,
                _venue.timezone,
                hour,
              ),
              opensAt: opensAt,
            ),
        ],
      );
      await tester.pumpWidget(_harness(repo));
      await _openSheet(tester);

      await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'เปิดจองครั้งถัดไปในวันที่ '
          '${ThaiDateUtils.formatShortDateBE2Digit(releaseDate)} '
          'เริ่มเวลา 09:00 น.',
        ),
        findsOneWidget,
      );
      expect(find.text('เวลาเปิดรับจอง: 09:00'), findsNothing);
    },
  );

  testWidgets('all-closed availability shows the next release date and time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final today = VenueLocalTime.today(_venue.timezone);
    final nextReleaseDate = VenueLocalTime.addCalendarDays(today, 1);
    final nextReleaseDay = nextReleaseDate.weekday % DateTime.daysPerWeek;
    repo.availability = CourtAvailability(
      courtId: 'court-1',
      hours: [
        VenueOperatingHours(
          dayOfWeek: today.weekday % DateTime.daysPerWeek,
          isClosed: true,
        ),
      ],
      release: CourtBookingRelease(
        mode: 'inherit',
        dayOfWeek: nextReleaseDay,
        daysOfWeek: [nextReleaseDay],
        releaseTime: '09:00:00',
        windowDays: 7,
      ),
      nextReleaseAt: VenueLocalTime.atWallTime(
        nextReleaseDate,
        _venue.timezone,
        9,
      ),
    );
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'เปิดจองครั้งถัดไปในวันที่ '
        '${ThaiDateUtils.formatShortDateBE2Digit(nextReleaseDate)} '
        'เริ่มเวลา 09:00 น.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('เวลาเปิดรับจอง:'), findsNothing);
  });

  testWidgets('only one court grid stays open at a time', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    repo.courts = [_instantCourt, _approvalCourt];
    repo.availability = _openAvailability();
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    await tester.tap(find.text('คอร์ท หลังจวนเก่าภูว้า'));
    await tester.pumpAndSettle();

    expect(repo.availabilityCourtIds, ['court-1']);
    expect(find.byType(CourtAvailabilityPicker), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('ตารางว่าง')).dy,
      greaterThan(tester.getBottomLeft(find.text('คอร์ท หลังจวนเก่าภูว้า')).dy),
    );

    await tester.tap(find.text('คอร์ท คอร์ทในร่ม'));
    await tester.pumpAndSettle();

    expect(repo.availabilityCourtIds, ['court-1', 'court-2']);
    expect(find.byType(CourtAvailabilityPicker), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('ตารางว่าง')).dy,
      greaterThan(tester.getBottomLeft(find.text('คอร์ท คอร์ทในร่ม')).dy),
    );
    expect(
      tester.getTopLeft(find.text('ตารางว่าง')).dy,
      greaterThan(tester.getBottomLeft(find.text('คอร์ท หลังจวนเก่าภูว้า')).dy),
    );
  });

  testWidgets(
    'upcoming confirmed appointments sit above the my-bookings button',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      repo.myBookings = [
        _booking(
          id: 'booking-soon',
          venueName: 'สนามลาดพร้าว',
          startsAt: now.add(const Duration(hours: 2)),
          endsAt: now.add(const Duration(hours: 3)),
        ),
        _booking(
          id: 'booking-later',
          venueName: 'สนามบางนา',
          startsAt: now.add(const Duration(days: 1)),
          endsAt: now.add(const Duration(days: 1, hours: 1)),
        ),
        // Owner still has to approve this one.
        _booking(
          id: 'booking-pending',
          venueName: 'สนามรออนุมัติ',
          status: VenueBookingStatus.pending,
          startsAt: now.add(const Duration(hours: 4)),
          endsAt: now.add(const Duration(hours: 5)),
        ),
        // Confirmed but already finished — history, not an upcoming appointment.
        _booking(
          id: 'booking-done',
          venueName: 'สนามที่จบแล้ว',
          startsAt: now.subtract(const Duration(hours: 3)),
          endsAt: now.subtract(const Duration(hours: 2)),
        ),
      ];

      await tester.pumpWidget(_harness(repo, onOpenMyBookings: () async {}));
      await _openSheet(tester);

      expect(find.text('นัดหมายกำลังจะเริ่ม'), findsOneWidget);
      expect(find.text('สนามลาดพร้าว'), findsOneWidget);
      expect(find.text('สนามบางนา'), findsOneWidget);
      expect(find.text('สนามรออนุมัติ'), findsNothing);
      expect(find.text('สนามที่จบแล้ว'), findsNothing);
      expect(find.text('ยืนยันแล้ว'), findsNWidgets(2));
      // Soonest first.
      expect(
        tester.getTopLeft(find.text('สนามลาดพร้าว')).dy,
        lessThan(tester.getTopLeft(find.text('สนามบางนา')).dy),
      );
      // The section sits directly above the my-bookings entry point.
      expect(
        tester.getTopLeft(find.text('นัดหมายกำลังจะเริ่ม')).dy,
        lessThan(tester.getTopLeft(find.text('ประวัติการจองของฉัน')).dy),
      );
    },
  );

  testWidgets('appointment dates collapse to วันนี้/พรุ่งนี้ or a Thai date', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final later = now.add(const Duration(days: 5));
    repo.myBookings = [
      _booking(
        id: 'booking-today',
        venueName: 'สนามใกล้บ้าน',
        startsAt: VenueLocalTime.atWallTime(
          VenueLocalTime.today(_venue.timezone),
          _venue.timezone,
          0,
        ),
        endsAt: now.add(const Duration(hours: 2)),
      ),
      _booking(
        id: 'booking-tomorrow',
        venueName: 'สนามบางนา',
        startsAt: tomorrow,
        endsAt: tomorrow.add(const Duration(hours: 1)),
      ),
      _booking(
        id: 'booking-later',
        venueName: 'สนามอีกวัน',
        startsAt: later,
        endsAt: later.add(const Duration(hours: 1)),
      ),
    ];

    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    expect(find.textContaining('วันนี้'), findsOneWidget);
    expect(find.textContaining('พรุ่งนี้'), findsOneWidget);
    expect(
      find.textContaining(ThaiDateUtils.formatShortDateBE2Digit(later)),
      findsOneWidget,
    );
  });

  testWidgets('no upcoming section when the booker has nothing scheduled', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    expect(find.text('นัดหมายกำลังจะเริ่ม'), findsNothing);
  });

  testWidgets('swiping an upcoming appointment cancels it after confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    repo.myBookings = [
      _booking(
        id: 'booking-soon',
        venueName: 'สนามลาดพร้าว',
        startsAt: now.add(const Duration(hours: 2)),
        endsAt: now.add(const Duration(hours: 3)),
      ),
    ];

    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    expect(find.text('ยกเลิก'), findsNothing);
    expect(
      find.text('ปัดการ์ดนัดหมายไปทางซ้ายเพื่อยกเลิกการจอง'),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('upcoming_booking-soon')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันยกเลิก'));
    await tester.pumpAndSettle();

    expect(repo.cancelledBookingIds, ['booking-soon']);
    expect(find.text('ยกเลิกการจองแล้ว'), findsOneWidget);
    expect(find.text('สนามลาดพร้าว'), findsNothing);
    // The card keeps the section (and its notice) alive after the row goes,
    // so the booker sees why the appointment disappeared.
    expect(find.text('นัดหมายกำลังจะเริ่ม'), findsOneWidget);
    expect(
      find.text('ปัดการ์ดนัดหมายไปทางซ้ายเพื่อยกเลิกการจอง'),
      findsNothing,
    );
  });

  testWidgets('a failed cancel keeps the row and explains why', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    repo.myBookings = [
      _booking(
        id: 'booking-soon',
        venueName: 'สนามลาดพร้าว',
        startsAt: now.add(const Duration(hours: 2)),
        endsAt: now.add(const Duration(hours: 3)),
      ),
    ];
    repo.cancelError = Exception('CUTOFF_PASSED');

    await tester.pumpWidget(_harness(repo));
    await _openSheet(tester);

    await tester.drag(
      find.byKey(const ValueKey('upcoming_booking-soon')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันยกเลิก'));
    await tester.pumpAndSettle();

    expect(find.text('สนามลาดพร้าว'), findsOneWidget);
    expect(
      find.text('เลยเวลายกเลิกฟรีแล้ว กรุณาติดต่อเจ้าของสถานที่โดยตรง'),
      findsOneWidget,
    );
  });

  testWidgets('signed-out bookers never load their booking list', (
    tester,
  ) async {
    repo.myBookings = [
      _booking(
        id: 'booking-soon',
        venueName: 'สนามลาดพร้าว',
        startsAt: DateTime.now().add(const Duration(hours: 2)),
        endsAt: DateTime.now().add(const Duration(hours: 3)),
      ),
    ];

    await tester.pumpWidget(_harness(repo, userId: null));
    await _openSheet(tester);

    expect(find.text('นัดหมายกำลังจะเริ่ม'), findsNothing);
    expect(find.text('สนามลาดพร้าว'), findsNothing);
  });
}
