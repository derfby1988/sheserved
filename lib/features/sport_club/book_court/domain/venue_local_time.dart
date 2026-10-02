import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class VenueLocalTime {
  static bool _initialized = false;

  static timezone.Location _location(String timeZone) {
    if (!_initialized) {
      timezone_data.initializeTimeZones();
      _initialized = true;
    }
    return timezone.getLocation(timeZone);
  }

  static timezone.TZDateTime now(String timeZone) =>
      timezone.TZDateTime.now(_location(timeZone));

  static DateTime today(String timeZone) {
    final current = now(timeZone);
    return DateTime(current.year, current.month, current.day);
  }

  static DateTime dateOfInstant(DateTime instant, String timeZone) {
    final local = timezone.TZDateTime.from(instant, _location(timeZone));
    return DateTime(local.year, local.month, local.day);
  }

  /// Wall-clock instant in the venue's timezone. Booking timestamps are
  /// stored as UTC, so their UTC fields must never be rendered directly —
  /// 21:00 in Asia/Bangkok would otherwise show up as 14:00.
  static timezone.TZDateTime wallTimeOfInstant(
    DateTime instant,
    String timeZone,
  ) => timezone.TZDateTime.from(instant, _location(timeZone));

  static timezone.TZDateTime atWallTime(
    DateTime date,
    String timeZone,
    int hour, [
    int minute = 0,
  ]) => timezone.TZDateTime(
    _location(timeZone),
    date.year,
    date.month,
    date.day,
    hour,
    minute,
  );

  static DateTime addCalendarDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);
}
