import 'package:flutter/material.dart';

import '../../data/book_court_models.dart';
import '../../domain/venue_local_time.dart';

/// Read-only availability view for one court on a given venue-local date.
///
/// Discovery phase contract: this widget displays booked/blocked ranges and
/// operating hours only; it never creates or holds bookings. Booking is
/// started separately via [CourtBookingDialog].
class CourtAvailabilityPicker extends StatelessWidget {
  final CourtAvailability availability;
  final DateTime date;
  final String timezone;
  final DateTime? now;
  final bool freeOnly;
  final Set<DateTime> selectedStarts;
  final void Function(DateTime start, DateTime end)? onSlotTap;

  /// Centers the header, slot grid and legend horizontally when true.
  final bool centered;

  const CourtAvailabilityPicker({
    super.key,
    required this.availability,
    required this.date,
    required this.timezone,
    this.now,
    this.freeOnly = false,
    this.selectedStarts = const {},
    this.onSlotTap,
    this.centered = false,
  });

  /// One-hour candidate slots between 06:00 and 23:00 venue-local time.
  static List<({DateTime start, DateTime end})> hourlySlots(
    DateTime day, {
    required String timezone,
  }) {
    return [
      for (var h = 6; h < 23; h++)
        (
          start: VenueLocalTime.atWallTime(day, timezone, h),
          end: VenueLocalTime.atWallTime(day, timezone, h + 1),
        ),
    ];
  }

  bool _overlaps(
    DateTime start,
    DateTime end,
    List<({DateTime startsAt, DateTime endsAt})> ranges,
  ) {
    return ranges.any(
      (r) => r.startsAt.isBefore(end) && r.endsAt.isAfter(start),
    );
  }

  bool _withinHours(DateTime start, DateTime end) {
    final dow = start.weekday % 7; // DateTime weekday: Mon=1..Sun=7 -> 0-6
    for (final h in availability.hours) {
      if (h.dayOfWeek != dow || h.isClosed) continue;
      final open = _minutesOf(h.openTime);
      final close = _minutesOf(h.closeTime);
      final s = start.hour * 60 + start.minute;
      final e = end.hour * 60 + end.minute;
      if (open != null && close != null && open <= s && close >= e) {
        return true;
      }
    }
    return false;
  }

  int? _minutesOf(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// Slots the user can actually book — genuinely free and not past.
  /// Not-yet-released slots are deliberately excluded; they render via
  /// [visibleSlots] so the user can see when they open.
  List<({DateTime start, DateTime end})> get freeSlots =>
      hourlySlots(date, timezone: timezone)
          .where(
            (slot) =>
                _slotState(slot.start, slot.end) == _SlotState.free &&
                !slot.start.isBefore(now ?? VenueLocalTime.now(timezone)),
          )
          .toList();

  /// freeOnly view: free slots plus not-yet-released slots (shown
  /// disabled with their opensAt so the user can see them coming).
  List<({DateTime start, DateTime end})> get visibleSlots {
    if (!freeOnly) return hourlySlots(date, timezone: timezone);
    final nowRef = now ?? VenueLocalTime.now(timezone);
    return hourlySlots(date, timezone: timezone).where((slot) {
      if (slot.start.isBefore(nowRef)) return false;
      final state = _slotState(slot.start, slot.end);
      return state == _SlotState.free || state == _SlotState.notOpen;
    }).toList();
  }

  bool get allSlotsClosed {
    final slots = hourlySlots(date, timezone: timezone);
    return slots.isNotEmpty &&
        slots.every(
          (slot) => _slotState(slot.start, slot.end) == _SlotState.closed,
        );
  }

  @override
  Widget build(BuildContext context) {
    final slots = visibleSlots;
    final wrapAlignment = centered ? WrapAlignment.center : WrapAlignment.start;
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        /*         const Text(
          'ตารางเวลา',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ), */
        const SizedBox(height: 8),
        if (slots.isEmpty)
          Text(
            'ไม่มีเวลาว่างในวันที่เลือก',
            textAlign: centered ? TextAlign.center : null,
          ),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: wrapAlignment,
            children: [
              for (final slot in slots)
                _SlotChip(
                  slot: slot,
                  state: _slotState(slot.start, slot.end),
                  opensAtLabel: _opensAtLabel(slot.start),
                  selected: selectedStarts.contains(slot.start),
                  onTap: onSlotTap == null
                      ? null
                      : () => onSlotTap!(slot.start, slot.end),
                ),
            ],
          ),
        ),
        if (!freeOnly) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: wrapAlignment,
              children: [
                _legend(Colors.green.shade100, 'ว่าง'),
                _legend(Colors.red.shade100, 'ถูกจอง'),
                _legend(Colors.grey.shade300, 'ปิด'),
                _legend(Colors.orange.shade100, 'ไม่พร้อม'),
                _legend(Colors.blueGrey.shade100, 'ยังไม่เปิดจอง'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  /// Venue-local label for a not-yet-released slot's opensAt instant.
  String? _opensAtLabel(DateTime slotStart) {
    final opensAt = availability.opensAtFor(slotStart);
    if (opensAt == null) return null;
    return 'เปิดจอง ${VenueLocalTime.formatInstantWall(opensAt, timezone)}';
  }

  _SlotState _slotState(DateTime start, DateTime end) {
    if (!_withinHours(start, end)) return _SlotState.closed;
    if (_overlaps(start, end, availability.booked)) return _SlotState.booked;
    if (_overlaps(start, end, availability.blocked) ||
        !end.isAfter(now ?? VenueLocalTime.now(timezone))) {
      return _SlotState.unavailable;
    }
    // 21.7.18: recurring release gate — the server lists which candidate
    // slots are still sealed and when they open (venue-local instant).
    final opensAt = availability.opensAtFor(start);
    if (opensAt != null &&
        opensAt.isAfter(now ?? VenueLocalTime.now(timezone))) {
      return _SlotState.notOpen;
    }
    return _SlotState.free;
  }
}

enum _SlotState { free, booked, closed, unavailable, notOpen }

class _SlotChip extends StatelessWidget {
  final ({DateTime start, DateTime end}) slot;
  final _SlotState state;
  final String? opensAtLabel;
  final bool selected;
  final VoidCallback? onTap;

  const _SlotChip({
    required this.slot,
    required this.state,
    this.opensAtLabel,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final free = state == _SlotState.free;
    final (background, border, foreground, message) = switch (state) {
      _SlotState.free => (
        Colors.green.shade100,
        Colors.green.shade400,
        Colors.green.shade900,
        'ว่าง',
      ),
      _SlotState.booked => (
        Colors.red.shade100,
        Colors.red.shade300,
        Colors.red.shade900,
        'ถูกจอง',
      ),
      _SlotState.closed => (
        Colors.grey.shade300,
        Colors.grey.shade500,
        Colors.grey.shade800,
        'ปิด',
      ),
      _SlotState.unavailable => (
        Colors.orange.shade100,
        Colors.orange.shade400,
        Colors.orange.shade900,
        'ไม่พร้อมให้จอง',
      ),
      _SlotState.notOpen => (
        Colors.blueGrey.shade100,
        Colors.blueGrey.shade300,
        Colors.blueGrey.shade800,
        opensAtLabel ?? 'ยังไม่เปิดจอง',
      ),
    };
    final label = '${slot.start.hour.toString().padLeft(2, '0')}:00';
    return Tooltip(
      message: message,
      child: Semantics(
        selected: selected,
        button: onTap != null,
        label: state == _SlotState.notOpen ? message : null,
        child: InkWell(
          onTap: free ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? Colors.green.shade700 : background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
