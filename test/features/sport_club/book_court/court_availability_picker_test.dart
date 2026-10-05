import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/domain/venue_local_time.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_availability_picker.dart';

void main() {
  group('VenueLocalTime', () {
    test('resolves wall-clock time in the venue timezone', () {
      final start = VenueLocalTime.atWallTime(
        DateTime(2030, 1, 1),
        'Asia/Bangkok',
        14,
      );

      expect(start.toUtc(), DateTime.utc(2030, 1, 1, 7));
    });

    test('maps a UTC booking instant back to venue wall time', () {
      final wall = VenueLocalTime.wallTimeOfInstant(
        DateTime.utc(2030, 1, 1, 14),
        'Asia/Bangkok',
      );

      expect(wall.hour, 21);
      expect(wall.day, 1);
    });

    test('uses calendar-day boundaries across daylight-saving changes', () {
      final date = DateTime(2024, 3, 10);
      final start = VenueLocalTime.atWallTime(date, 'America/New_York', 0);
      final nextDate = VenueLocalTime.addCalendarDays(date, 1);
      final end = VenueLocalTime.atWallTime(nextDate, 'America/New_York', 0);

      expect(end.difference(start), const Duration(hours: 23));
    });
  });

  testWidgets('shows closed slots separately from booked slots', (
    tester,
  ) async {
    const timezone = 'Asia/Bangkok';
    final date = DateTime(2040, 1, 1);
    final day = VenueLocalTime.atWallTime(date, timezone, 0).weekday % 7;
    final bookedStart = VenueLocalTime.atWallTime(date, timezone, 15);
    final bookedEnd = VenueLocalTime.atWallTime(date, timezone, 16);
    final availability = CourtAvailability(
      courtId: 'court-1',
      booked: [(startsAt: bookedStart, endsAt: bookedEnd)],
      hours: [
        VenueOperatingHours(
          dayOfWeek: day,
          openTime: '14:00',
          closeTime: '22:00',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourtAvailabilityPicker(
            availability: availability,
            date: date,
            timezone: timezone,
            now: DateTime.utc(2030),
          ),
        ),
      ),
    );

    expect(find.byTooltip('ถูกจอง'), findsOneWidget);
    expect(find.byTooltip('ปิด'), findsNWidgets(9));
    expect(find.byTooltip('ว่าง'), findsNWidgets(7));
    expect(find.text('ถูกจอง'), findsOneWidget);
    expect(find.text('ปิด'), findsOneWidget);
  });

  testWidgets('free-only hides booked, blocked, closed and started slots', (
    tester,
  ) async {
    const timezone = 'Asia/Bangkok';
    final date = DateTime(2040, 1, 1);
    DateTime at(int hour, [int minute = 0]) =>
        VenueLocalTime.atWallTime(date, timezone, hour, minute);
    final availability = CourtAvailability(
      courtId: 'court-1',
      booked: [(startsAt: at(15), endsAt: at(16))],
      blocked: [(startsAt: at(17, 30), endsAt: at(18, 30))],
      hours: [
        VenueOperatingHours(
          dayOfWeek: at(0).weekday % 7,
          openTime: '14:00',
          closeTime: '22:00',
        ),
      ],
    );
    DateTime? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourtAvailabilityPicker(
            availability: availability,
            date: date,
            timezone: timezone,
            now: at(14, 30),
            freeOnly: true,
            selectedStarts: {at(19)},
            onSlotTap: (start, end) => tapped = start,
          ),
        ),
      ),
    );
    expect(find.text('14:00'), findsNothing);
    expect(find.text('15:00'), findsNothing);
    expect(find.text('17:00'), findsNothing);
    expect(find.text('18:00'), findsNothing);
    expect(find.byTooltip('ว่าง'), findsNWidgets(4));
    expect(find.text('ถูกจอง'), findsNothing);
    expect(find.text('ปิด'), findsNothing);
    await tester.tap(find.text('19:00'));
    expect(tapped, at(19));
  });

  testWidgets('elapsed slots are shown separately from suspensions', (
    tester,
  ) async {
    const timezone = 'Asia/Bangkok';
    final date = DateTime(2040, 1, 1);
    DateTime at(int hour) => VenueLocalTime.atWallTime(date, timezone, hour);
    final availability = CourtAvailability(
      courtId: 'court-1',
      serverNow: at(15),
      hours: [
        VenueOperatingHours(
          dayOfWeek: at(0).weekday % 7,
          openTime: '14:00',
          closeTime: '18:00',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourtAvailabilityPicker(
            availability: availability,
            date: date,
            timezone: timezone,
            now: at(15),
          ),
        ),
      ),
    );

    expect(find.byTooltip('เวลานี้ผ่านไปแล้ว'), findsOneWidget);
    expect(find.text('ผ่านแล้ว'), findsOneWidget);
    expect(find.text('ระงับชั่วคราว'), findsOneWidget);
  });

  testWidgets(
    'owner management mode exposes blocked and unreleased future slots',
    (tester) async {
      const timezone = 'Asia/Bangkok';
      final date = DateTime(2040, 1, 1);
      DateTime at(int hour) => VenueLocalTime.atWallTime(date, timezone, hour);
      final availability = CourtAvailability(
        courtId: 'court-1',
        blocked: [(startsAt: at(14), endsAt: at(15))],
        notOpen: [(slotStart: at(16), opensAt: at(18))],
        hours: [
          VenueOperatingHours(
            dayOfWeek: at(0).weekday % 7,
            openTime: '14:00',
            closeTime: '22:00',
          ),
        ],
      );
      final tapped = <DateTime>[];
      final picker = CourtAvailabilityPicker(
        availability: availability,
        date: date,
        timezone: timezone,
        now: at(13),
        freeOnly: true,
        availabilityManagementMode: true,
        onSlotTap: (start, end) => tapped.add(start),
      );

      expect(picker.managerSuspendedSlots.map((slot) => slot.start), [at(14)]);
      expect(
        picker.managerSuspendableSlots.map((slot) => slot.start),
        containsAll([at(16), at(17)]),
      );
      expect(
        picker.visibleSlots.map((slot) => slot.start),
        containsAll([at(14), at(16), at(17)]),
      );

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: picker)));
      await tester.tap(find.text('14:00'));
      await tester.tap(find.text('16:00'));

      expect(tapped, [at(14), at(16)]);
      expect(find.text('ถูกจอง'), findsNothing);
      expect(find.text('ปิด'), findsNothing);
    },
  );

  testWidgets('free-only with missing hours shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourtAvailabilityPicker(
            availability: const CourtAvailability(courtId: 'court-1'),
            date: DateTime(2040, 1, 1),
            timezone: 'Asia/Bangkok',
            freeOnly: true,
          ),
        ),
      ),
    );
    expect(find.text('ไม่มีเวลาว่างในวันที่เลือก'), findsOneWidget);
    expect(find.byTooltip('ว่าง'), findsNothing);
  });

  testWidgets('closed and missing schedules fail closed', (tester) async {
    const timezone = 'Asia/Bangkok';
    final date = DateTime(2040, 1, 1);
    final day = VenueLocalTime.atWallTime(date, timezone, 0).weekday % 7;

    for (final availability in [
      CourtAvailability(
        courtId: 'court-1',
        hours: [VenueOperatingHours(dayOfWeek: day, isClosed: true)],
      ),
      const CourtAvailability(courtId: 'court-1'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourtAvailabilityPicker(
              availability: availability,
              date: date,
              timezone: timezone,
              now: DateTime.utc(2030),
            ),
          ),
        ),
      );

      expect(find.byTooltip('ปิด'), findsNWidgets(17));
      expect(find.byTooltip('ว่าง'), findsNothing);
      expect(find.byTooltip('ถูกจอง'), findsNothing);
    }
  });

  group('booking release (21.7.18)', () {
    test('decodes serverNow, notOpen slots and the effective rule', () {
      final a = CourtAvailability.fromJson({
        'courtId': 'c1',
        'serverNow': '2040-01-01T02:00:00Z',
        'nextReleaseAt': '2040-01-02T03:00:00Z',
        'booked': [],
        'blocked': [],
        'hours': [],
        'notOpen': [
          {
            'slotStart': '2040-01-05T03:00:00Z',
            'opensAt': '2040-01-02T02:00:00Z',
          },
        ],
        'release': {
          'mode': 'inherit',
          'dayOfWeek': 1,
          'daysOfWeek': [1, 3],
          'releaseTime': '09:00',
          'windowDays': 14,
          'selectedDayReleaseTime': '10:00',
          'selectedDayOpensAt': '2040-01-01T02:00:00Z',
        },
      });

      expect(a.serverNow, DateTime.utc(2040, 1, 1, 2));
      expect(a.nextReleaseAt, DateTime.utc(2040, 1, 2, 3));
      expect(a.notOpen.single.slotStart, DateTime.utc(2040, 1, 5, 3));
      expect(
        a.opensAtFor(DateTime.utc(2040, 1, 5, 3)),
        DateTime.utc(2040, 1, 2, 2),
      );
      expect(a.opensAtFor(DateTime.utc(2040, 1, 5, 4)), isNull);
      expect(a.release?.mode, 'inherit');
      expect(a.release?.selectedDayReleaseTime, '10:00');
      expect(a.release?.selectedDayOpensAt, DateTime.utc(2040, 1, 1, 2));
      expect(a.release?.effectiveDaysOfWeek, [1, 3]);
      expect(a.release?.windowDays, 14);
    });

    test('court details parse selected release weekdays', () {
      final court = VenueCourt.fromJson({
        'id': 'c1',
        'venue_id': 'v1',
        'sport_id': 's1',
        'name': 'Court 1',
        'booking_release_mode': 'custom',
        'booking_release_day_of_week': 0,
        'booking_release_days': [0, 1, 2, 3, 4, 5, 6],
        'booking_release_time': '09:00',
        'booking_release_window_days': 1,
      });
      expect(court.effectiveBookingReleaseDays, [0, 1, 2, 3, 4, 5, 6]);
    });

    test('legacy one-day release payload maps to one selected day', () {
      final release = CourtBookingRelease.fromJson({
        'mode': 'custom',
        'dayOfWeek': 5,
        'releaseTime': '09:00',
        'windowDays': 7,
      });
      expect(release.effectiveDaysOfWeek, [5]);
      expect(release.selectedDayOpensAt, isNull);
    });

    test('older payloads without release fields still decode', () {
      final a = CourtAvailability.fromJson({
        'courtId': 'c1',
        'booked': [],
        'blocked': [],
        'hours': [],
      });

      expect(a.serverNow, isNull);
      expect(a.notOpen, isEmpty);
      expect(a.release, isNull);
    });

    testWidgets('sealed slots keep button size, stay visible and reject taps', (
      tester,
    ) async {
      const timezone = 'Asia/Bangkok';
      final date = DateTime(2040, 1, 1);
      DateTime at(int hour, [int minute = 0]) =>
          VenueLocalTime.atWallTime(date, timezone, hour, minute);
      final opensAt = at(20);
      final availability = CourtAvailability(
        courtId: 'court-1',
        hours: [
          VenueOperatingHours(
            dayOfWeek: at(0).weekday % 7,
            openTime: '14:00',
            closeTime: '22:00',
          ),
        ],
        notOpen: [(slotStart: at(15), opensAt: opensAt)],
      );
      DateTime? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourtAvailabilityPicker(
              availability: availability,
              date: date,
              timezone: timezone,
              now: at(14, 30),
              freeOnly: true,
              onSlotTap: (start, end) => tapped = start,
            ),
          ),
        ),
      );

      // The sealed slot is shown for discovery but is not bookable.
      expect(find.text('15:00'), findsOneWidget);
      expect(find.textContaining('เปิดจอง '), findsNothing);
      expect(
        find.byTooltip(
          'เปิดจอง ${VenueLocalTime.formatInstantWall(opensAt, timezone)}',
        ),
        findsOneWidget,
      );
      final sealedChip = find.ancestor(
        of: find.text('15:00'),
        matching: find.byType(InkWell),
      );
      final freeChip = find.ancestor(
        of: find.text('16:00'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(sealedChip), tester.getSize(freeChip));
      final picker = CourtAvailabilityPicker(
        availability: availability,
        date: date,
        timezone: timezone,
        now: at(14, 30),
        freeOnly: true,
      );
      // freeSlots stays bookable-only; visibleSlots keeps the sealed
      // chip for discovery.
      expect(picker.freeSlots.map((s) => s.start), isNot(contains(at(15))));
      expect(picker.visibleSlots.map((s) => s.start), contains(at(15)));
      await tester.tap(find.text('15:00'));
      expect(tapped, isNull);
    });

    testWidgets('a slot becomes free once its opensAt has passed', (
      tester,
    ) async {
      const timezone = 'Asia/Bangkok';
      final date = DateTime(2040, 1, 1);
      DateTime at(int hour, [int minute = 0]) =>
          VenueLocalTime.atWallTime(date, timezone, hour, minute);
      final availability = CourtAvailability(
        courtId: 'court-1',
        hours: [
          VenueOperatingHours(
            dayOfWeek: at(0).weekday % 7,
            openTime: '14:00',
            closeTime: '22:00',
          ),
        ],
        // Stale entry: the release instant is behind serverNow, so the
        // slot must render free — server time wins over a cached payload.
        notOpen: [(slotStart: at(15), opensAt: at(14))],
      );
      DateTime? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourtAvailabilityPicker(
              availability: availability,
              date: date,
              timezone: timezone,
              now: at(14, 30),
              freeOnly: true,
              onSlotTap: (start, end) => tapped = start,
            ),
          ),
        ),
      );

      expect(find.byTooltip('ว่าง'), findsNWidgets(7));
      await tester.tap(find.text('15:00'));
      expect(tapped, at(15));
    });
  });

  group('status legend long-press', () {
    const timezone = 'Asia/Bangkok';
    final date = DateTime(2040, 1, 1);

    Future<void> pumpLegend(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourtAvailabilityPicker(
              availability: CourtAvailability(
                courtId: 'court-1',
                hours: [
                  VenueOperatingHours(
                    dayOfWeek:
                        VenueLocalTime.atWallTime(date, timezone, 0).weekday %
                        7,
                    openTime: '14:00',
                    closeTime: '22:00',
                  ),
                ],
              ),
              date: date,
              timezone: timezone,
              now: DateTime.utc(2030),
            ),
          ),
        ),
      );
    }

    testWidgets('long-pressing a legend entry explains it, then hides again', (
      tester,
    ) async {
      await pumpLegend(tester);

      expect(find.textContaining('ยังไม่เปิดจอง — '), findsNothing);

      await tester.longPress(find.text('ยังไม่เปิดจอง'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ยังไม่เปิดจอง — '), findsOneWidget);
      // The legend entry itself stays on screen while the note shows.
      expect(find.text('ยังไม่เปิดจอง'), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.textContaining('ยังไม่เปิดจอง — '), findsNothing);
    });

    testWidgets('a later long-press replaces the note and restarts its timer', (
      tester,
    ) async {
      await pumpLegend(tester);

      await tester.longPress(find.text('ปิด'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ปิด — '), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.longPress(find.text('ระงับชั่วคราว'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ระงับชั่วคราว — '), findsOneWidget);
      expect(find.textContaining('ปิด — '), findsNothing);

      // Restarted, so it outlives the first note's original deadline.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.textContaining('ระงับชั่วคราว — '), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.textContaining('ระงับชั่วคราว — '), findsNothing);
    });

    testWidgets('tapping the note dismisses it early', (tester) async {
      await pumpLegend(tester);

      await tester.longPress(find.text('ถูกจอง'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ถูกจอง — '), findsOneWidget);

      await tester.tap(find.textContaining('ถูกจอง — '));
      await tester.pumpAndSettle();

      expect(find.textContaining('ถูกจอง — '), findsNothing);
    });

    testWidgets('every legend status carries its own explanation', (
      tester,
    ) async {
      await pumpLegend(tester);

      for (final label in [
        'ว่าง',
        'ถูกจอง',
        'ปิด',
        'ระงับชั่วคราว',
        'ผ่านแล้ว',
        'ยังไม่เปิดจอง',
      ]) {
        await tester.longPress(find.text(label));
        await tester.pumpAndSettle();
        expect(find.textContaining('$label — '), findsOneWidget);
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('free-only view keeps the legend and its notes off', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourtAvailabilityPicker(
              availability: const CourtAvailability(courtId: 'court-1'),
              date: date,
              timezone: timezone,
              freeOnly: true,
            ),
          ),
        ),
      );

      expect(find.text('ว่าง'), findsNothing);
      expect(find.textContaining('ว่าง — '), findsNothing);
    });
  });
}
