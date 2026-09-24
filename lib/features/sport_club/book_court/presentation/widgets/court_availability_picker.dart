import 'package:flutter/material.dart';

import '../../data/book_court_models.dart';

/// Read-only availability view for one court on a given venue-local date.
///
/// Discovery phase contract: this widget displays booked/blocked ranges and
/// operating hours only; it never creates or holds bookings. Booking is
/// started separately via [CourtBookingSheet].
class CourtAvailabilityPicker extends StatelessWidget {
  final CourtAvailability availability;
  final DateTime date;
  final void Function(DateTime start, DateTime end)? onSlotTap;

  const CourtAvailabilityPicker({
    super.key,
    required this.availability,
    required this.date,
    this.onSlotTap,
  });

  /// One-hour candidate slots between 06:00 and 23:00 venue-local time.
  static List<({DateTime start, DateTime end})> hourlySlots(DateTime day) {
    final base = DateTime(day.year, day.month, day.day);
    return [
      for (var h = 6; h < 23; h++)
        (start: base.add(Duration(hours: h)),
         end: base.add(Duration(hours: h + 1))),
    ];
  }

  bool _overlaps(
    DateTime start,
    DateTime end,
    List<({DateTime startsAt, DateTime endsAt})> ranges,
  ) {
    return ranges.any((r) => r.startsAt.isBefore(end) && r.endsAt.isAfter(start));
  }

  bool _withinHours(DateTime start, DateTime end) {
    if (availability.hours.isEmpty) return true;
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

  @override
  Widget build(BuildContext context) {
    final slots = hourlySlots(date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ตารางเวลา',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final slot in slots)
              _SlotChip(
                slot: slot,
                state: _slotState(slot.start, slot.end),
                onTap: onSlotTap == null
                    ? null
                    : () => onSlotTap!(slot.start, slot.end),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _legend(Colors.green.shade100, 'ว่าง'),
            const SizedBox(width: 12),
            _legend(Colors.red.shade100, 'ถูกจอง/ปิด'),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
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
    if (end.isBefore(DateTime.now())) return _SlotState.unavailable;
    if (!_withinHours(start, end)) return _SlotState.unavailable;
    if (_overlaps(start, end, availability.blocked)) {
      return _SlotState.unavailable;
    }
    if (_overlaps(start, end, availability.booked)) {
      return _SlotState.booked;
    }
    return _SlotState.free;
  }
}

enum _SlotState { free, booked, unavailable }

class _SlotChip extends StatelessWidget {
  final ({DateTime start, DateTime end}) slot;
  final _SlotState state;
  final VoidCallback? onTap;

  const _SlotChip({required this.slot, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final free = state == _SlotState.free;
    final label =
        '${slot.start.hour.toString().padLeft(2, '0')}:00';
    return Tooltip(
      message: free ? 'ว่าง' : 'ไม่ว่าง',
      child: InkWell(
        onTap: free ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: free ? Colors.green.shade100 : Colors.red.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: free ? Colors.green.shade400 : Colors.red.shade300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: free ? Colors.green.shade900 : Colors.red.shade900,
            ),
          ),
        ),
      ),
    );
  }
}
