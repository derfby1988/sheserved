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

  const CourtAvailabilityPicker({
    super.key,
    required this.availability,
    required this.date,
    required this.timezone,
    this.now,
    this.freeOnly = false,
    this.selectedStarts = const {},
    this.onSlotTap,
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

  List<({DateTime start, DateTime end})> get freeSlots =>
      hourlySlots(date, timezone: timezone)
          .where(
            (slot) =>
                _slotState(slot.start, slot.end) == _SlotState.free &&
                !slot.start.isBefore(now ?? VenueLocalTime.now(timezone)),
          )
          .toList();

  @override
  Widget build(BuildContext context) {
    final slots = freeOnly ? freeSlots : hourlySlots(date, timezone: timezone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ตารางเวลา',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 8),
        if (slots.isEmpty) const Text('ไม่มีเวลาว่างในวันที่เลือก'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final slot in slots)
              _SlotChip(
                slot: slot,
                state: _slotState(slot.start, slot.end),
                selected: selectedStarts.contains(slot.start),
                onTap: onSlotTap == null
                    ? null
                    : () => onSlotTap!(slot.start, slot.end),
              ),
          ],
        ),
        if (!freeOnly) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _legend(Colors.green.shade100, 'ว่าง'),
              _legend(Colors.red.shade100, 'ถูกจอง'),
              _legend(Colors.grey.shade300, 'ปิด'),
              _legend(Colors.orange.shade100, 'ไม่พร้อม'),
            ],
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

  _SlotState _slotState(DateTime start, DateTime end) {
    if (!_withinHours(start, end)) return _SlotState.closed;
    if (_overlaps(start, end, availability.booked)) return _SlotState.booked;
    if (_overlaps(start, end, availability.blocked) ||
        !end.isAfter(now ?? VenueLocalTime.now(timezone))) {
      return _SlotState.unavailable;
    }
    return _SlotState.free;
  }
}

enum _SlotState { free, booked, closed, unavailable }

class _SlotChip extends StatelessWidget {
  final ({DateTime start, DateTime end}) slot;
  final _SlotState state;
  final bool selected;
  final VoidCallback? onTap;

  const _SlotChip({
    required this.slot,
    required this.state,
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
    };
    final label = '${slot.start.hour.toString().padLeft(2, '0')}:00';
    return Tooltip(
      message: message,
      child: Semantics(
        selected: selected,
        button: onTap != null,
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
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
