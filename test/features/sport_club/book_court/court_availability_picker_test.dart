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
}
