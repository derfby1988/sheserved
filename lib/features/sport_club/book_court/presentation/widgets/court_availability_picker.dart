import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/book_court_models.dart';
import '../../domain/venue_local_time.dart';

/// Availability view for one court on a given venue-local date.
///
/// This widget displays booked/blocked ranges and operating hours; owner
/// management mode can select slots for a separate one-time availability RPC.
/// It never creates or holds bookings, which start via [CourtBookingDialog].
class CourtAvailabilityPicker extends StatelessWidget {
  final CourtAvailability availability;
  final DateTime date;
  final String timezone;
  final DateTime? now;
  final bool freeOnly;
  final Set<DateTime> selectedStarts;
  final bool availabilityManagementMode;
  final Set<DateTime> selectedBlockedStarts;
  final void Function(DateTime start, DateTime end)? onSlotTap;
  final void Function(DateTime start, DateTime end)? onSuspendedSlotTap;

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
    this.availabilityManagementMode = false,
    this.selectedBlockedStarts = const {},
    this.onSlotTap,
    this.onSuspendedSlotTap,
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

  /// Owner-only candidates for creating a one-time suspension, including
  /// future slots whose recurring booking release has not arrived yet.
  List<({DateTime start, DateTime end})> get managerSuspendableSlots =>
      hourlySlots(date, timezone: timezone).where((slot) {
        if (slot.start.isBefore(now ?? VenueLocalTime.now(timezone))) {
          return false;
        }
        final state = _slotState(slot.start, slot.end);
        return state == _SlotState.free || state == _SlotState.notOpen;
      }).toList();

  /// Owner-only candidates for removing a one-time suspension.
  List<({DateTime start, DateTime end})> get managerSuspendedSlots =>
      hourlySlots(date, timezone: timezone).where((slot) {
        if (slot.start.isBefore(now ?? VenueLocalTime.now(timezone))) {
          return false;
        }
        return _slotState(slot.start, slot.end) == _SlotState.blocked;
      }).toList();

  /// freeOnly view shows genuinely free slots and not-yet-released slots.
  /// Owner management additionally exposes active blocked slots for undo.
  List<({DateTime start, DateTime end})> get visibleSlots {
    if (!freeOnly) return hourlySlots(date, timezone: timezone);
    if (availabilityManagementMode) {
      return [...managerSuspendableSlots, ...managerSuspendedSlots]
        ..sort((a, b) => a.start.compareTo(b.start));
    }
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
            children: [for (final slot in slots) _buildSlotChip(slot)],
          ),
        ),
        if (!freeOnly) ...[
          const SizedBox(height: 8),
          _StatusLegend(alignment: wrapAlignment),
        ],
      ],
    );
  }

  /// Venue-local label for a not-yet-released slot's opensAt instant.
  String? _opensAtLabel(DateTime slotStart) {
    final opensAt = availability.opensAtFor(slotStart);
    if (opensAt == null) return null;
    return 'เปิดจอง ${VenueLocalTime.formatInstantWall(opensAt, timezone)}';
  }

  Widget _buildSlotChip(({DateTime start, DateTime end}) slot) {
    final state = _slotState(slot.start, slot.end);
    final onTap = state == _SlotState.blocked
        ? onSuspendedSlotTap ?? onSlotTap
        : onSlotTap;
    return _SlotChip(
      slot: slot,
      state: state,
      opensAtLabel: _opensAtLabel(slot.start),
      selected:
          selectedStarts.contains(slot.start) ||
          selectedBlockedStarts.contains(slot.start),
      selectedAsBlocked: selectedBlockedStarts.contains(slot.start),
      managementSelection: availabilityManagementMode,
      canSelect:
          state == _SlotState.free ||
          state == _SlotState.blocked && onSuspendedSlotTap != null ||
          availabilityManagementMode &&
              (state == _SlotState.notOpen || state == _SlotState.blocked),
      onTap: onTap == null ? null : () => onTap(slot.start, slot.end),
    );
  }

  _SlotState _slotState(DateTime start, DateTime end) {
    if (!_withinHours(start, end)) return _SlotState.closed;
    if (_overlaps(start, end, availability.booked)) return _SlotState.booked;
    if (!end.isAfter(now ?? VenueLocalTime.now(timezone))) {
      return _SlotState.elapsed;
    }
    if (_overlaps(start, end, availability.blocked)) {
      return _SlotState.blocked;
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

enum _SlotState { free, booked, closed, elapsed, blocked, notOpen }

/// The colour legend under the grid. Long-pressing an entry shows a
/// transient explanation of that slot state, then fades it out again.
class _StatusLegend extends StatefulWidget {
  final WrapAlignment alignment;

  const _StatusLegend({required this.alignment});

  @override
  State<_StatusLegend> createState() => _StatusLegendState();
}

class _StatusLegendState extends State<_StatusLegend> {
  /// How long an explanation stays on screen before it disappears.
  static const _visibleFor = Duration(seconds: 5);

  /// Order follows the grid's own state priority: free, booked, closed,
  /// elapsed or suspended, then not yet released.
  List<({Color color, String label, String explanation})> get _entries => [
    (
      color: Colors.green.shade100,
      label: 'ว่าง',
      explanation:
          'ว่าง — อยู่ในเวลาทำการ ไม่มีผู้จอง และถึงรอบเปิดรับจองแล้ว แตะช่องเวลาเพื่อเริ่มจอง',
    ),
    (
      color: Colors.red.shade100,
      label: 'ถูกจอง',
      explanation: 'ถูกจอง — มีผู้จองยืนยันแล้วในช่วงเวลานี้ จองซ้อนไม่ได้',
    ),
    (
      color: Colors.grey.shade300,
      label: 'ปิด',
      explanation:
          'ปิด — อยู่นอกเวลาทำการของวันที่เลือก (วันปิด หรือก่อน/หลังเวลาเปิด-ปิด)',
    ),
    (
      color: Colors.orange.shade100,
      label: 'ระงับชั่วคราว',
      explanation:
          'ระงับชั่วคราว — เจ้าของหรือผู้จัดการระงับช่วงนี้ไว้ ผู้มีสิทธิแตะสล็อตสีส้มเพื่อจัดการ',
    ),
    (
      color: Colors.grey.shade200,
      label: 'ผ่านแล้ว',
      explanation: 'ผ่านแล้ว — เวลานี้สิ้นสุดแล้ว จึงจองหรือจัดการไม่ได้',
    ),
    (
      color: Colors.blueGrey.shade100,
      label: 'ยังไม่เปิดจอง',
      explanation:
          'ยังไม่เปิดจอง — อยู่ในเวลาทำการแต่ยังไม่ถึงรอบเปิดรับจอง แตะค้างที่ช่องเวลาเพื่อดูวันและเวลาที่จะเปิด',
    ),
  ];

  String? _explanation;
  Timer? _hideTimer;

  void _explain(String explanation) {
    _hideTimer?.cancel();
    setState(() => _explanation = explanation);
    _hideTimer = Timer(_visibleFor, _hide);
  }

  void _hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (mounted) setState(() => _explanation = null);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final explanation = _explanation;
    return Column(
      crossAxisAlignment: widget.alignment == WrapAlignment.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: widget.alignment,
            children: [for (final entry in _entries) _legendItem(entry)],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: explanation == null
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(explanation),
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _hide,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueGrey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: Colors.blueGrey.shade700,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              explanation,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.blueGrey.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _legendItem(({Color color, String label, String explanation}) entry) {
    return Semantics(
      button: true,
      label: '${entry.label} — แตะค้างเพื่อดูคำอธิบายสถานะ',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _explain(entry.explanation),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: entry.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 4),
            Text(entry.label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final ({DateTime start, DateTime end}) slot;
  final _SlotState state;
  final String? opensAtLabel;
  final bool selected;
  final bool selectedAsBlocked;
  final bool managementSelection;
  final bool canSelect;
  final VoidCallback? onTap;

  const _SlotChip({
    required this.slot,
    required this.state,
    this.opensAtLabel,
    this.selected = false,
    this.selectedAsBlocked = false,
    this.managementSelection = false,
    this.canSelect = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
      _SlotState.elapsed => (
        Colors.grey.shade200,
        Colors.grey.shade400,
        Colors.grey.shade700,
        'เวลานี้ผ่านไปแล้ว',
      ),
      _SlotState.blocked => (
        Colors.orange.shade100,
        Colors.orange.shade400,
        Colors.orange.shade900,
        onTap != null && canSelect && !managementSelection
            ? 'ระงับชั่วคราว — แตะเพื่อจัดการ'
            : 'ระงับชั่วคราว',
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
        button: onTap != null && canSelect,
        label:
            state == _SlotState.notOpen ||
                state == _SlotState.blocked && canSelect
            ? message
            : null,
        child: InkWell(
          onTap: canSelect ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? selectedAsBlocked
                        ? Colors.green.shade700
                        : managementSelection
                        ? Colors.deepOrange.shade700
                        : Colors.green.shade700
                  : background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? selectedAsBlocked
                          ? Colors.green.shade800
                          : managementSelection
                          ? Colors.deepOrange.shade800
                          : border
                    : border,
              ),
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
