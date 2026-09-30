import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/domain/venue_local_time.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_booking_sheet.dart';

void main() {
  testWidgets('booking selection resolves wall time in venue timezone', (
    tester,
  ) async {
    const timezone = 'Asia/Bangkok';
    final date = VenueLocalTime.addCalendarDays(
      VenueLocalTime.today(timezone),
      1,
    );
    ({DateTime start, DateTime end})? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await CourtBookingSheet.show(
                  context,
                  court: const VenueCourt(
                    id: 'court-1',
                    venueId: 'venue-1',
                    sportId: 'sport-1',
                    name: 'คอร์ท A',
                  ),
                  venueName: 'สนามทดสอบ',
                  timezone: timezone,
                  initialDate: date,
                );
              },
              child: const Text('เปิดฟอร์มจอง'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดฟอร์มจอง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เวลาเริ่ม'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ถัดไป — อ่านเงื่อนไข'));
    await tester.pumpAndSettle();

    expect(
      result!.start.toUtc(),
      VenueLocalTime.atWallTime(date, timezone, 18).toUtc(),
    );
    expect(result!.end.difference(result!.start), const Duration(hours: 1));
  });

  test('dateOfInstant uses the venue-local calendar date', () {
    expect(
      VenueLocalTime.dateOfInstant(
        DateTime.utc(2026, 9, 30, 18),
        'Asia/Bangkok',
      ),
      DateTime(2026, 10, 1),
    );
  });
}
