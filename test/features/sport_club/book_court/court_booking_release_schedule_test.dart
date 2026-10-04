import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/domain/court_booking_release_schedule.dart';

void main() {
  test('a weekly single-day schedule needs a seven-day window', () {
    expect(CourtBookingReleaseSchedule.minimumWindowDays([1]), 7);
  });

  test('daily schedules need only a one-day window', () {
    expect(
      CourtBookingReleaseSchedule.minimumWindowDays([0, 1, 2, 3, 4, 5, 6]),
      1,
    );
  });

  test('the minimum window is the largest circular gap between days', () {
    expect(CourtBookingReleaseSchedule.minimumWindowDays([1, 3]), 5);
  });

  test('empty, duplicate and out-of-range weekday sets are invalid', () {
    expect(CourtBookingReleaseSchedule.minimumWindowDays([]), isNull);
    expect(CourtBookingReleaseSchedule.minimumWindowDays([1, 1]), isNull);
    expect(CourtBookingReleaseSchedule.minimumWindowDays([7]), isNull);
  });

  test('day descriptions distinguish daily from selected weekly days', () {
    expect(
      CourtBookingReleaseSchedule.describeDays([0, 1, 2, 3, 4, 5, 6]),
      'ทุกวัน',
    );
    expect(
      CourtBookingReleaseSchedule.describeDays([1, 3]),
      'ทุกสัปดาห์ วันจันทร์ และวันพุธ',
    );
  });
}
