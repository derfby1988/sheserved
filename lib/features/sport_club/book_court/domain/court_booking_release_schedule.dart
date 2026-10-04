/// Validates and formats recurring release schedules selected by weekday.
class CourtBookingReleaseSchedule {
  /// Maximum days representable by the database's `SMALLINT` window field.
  static const maxWindowDays = 32767;

  /// Venue-local weekday labels, with Sunday represented by `0`.
  static const weekdayLabels = {
    0: 'อาทิตย์',
    1: 'จันทร์',
    2: 'อังคาร',
    3: 'พุธ',
    4: 'พฤหัสบดี',
    5: 'ศุกร์',
    6: 'เสาร์',
  };

  /// Returns a sorted copy of [days].
  static List<int> sortedDays(Iterable<int> days) => days.toList()..sort();

  /// Returns the minimum gap-free window for [days], or null for invalid days.
  static int? minimumWindowDays(Iterable<int> days) {
    final selected = days.toList();
    if (selected.isEmpty ||
        selected.length > 7 ||
        selected.toSet().length != selected.length ||
        selected.any((day) => day < 0 || day > 6)) {
      return null;
    }
    selected.sort();
    var largestGap = 0;
    for (var i = 0; i < selected.length; i++) {
      final next = i + 1 < selected.length
          ? selected[i + 1]
          : selected.first + 7;
      final gap = next - selected[i];
      if (gap > largestGap) largestGap = gap;
    }
    return largestGap;
  }

  /// Formats a weekday set for owner-facing schedule summaries.
  static String describeDays(Iterable<int> days) {
    final selected = sortedDays(days);
    if (selected.isEmpty) return 'ยังไม่ได้เลือกวัน';
    if (selected.length == 7) return 'ทุกวัน';
    final labels = selected.map((day) => weekdayLabels[day] ?? '').toList();
    final selectedLabel = labels.length < 2
        ? 'วัน${labels.first}'
        : '${labels.take(labels.length - 1).map((day) => 'วัน$day').join(', ')}'
              ' และวัน${labels.last}';
    return 'ทุกสัปดาห์ $selectedLabel';
  }
}
