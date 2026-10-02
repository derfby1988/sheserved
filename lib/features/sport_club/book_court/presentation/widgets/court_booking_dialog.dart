import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/thai_address_picker/glass_date_time_picker.dart';
import 'package:sheserved/shared/widgets/thai_buddhist_date_picker.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../data/book_court_models.dart';
import '../../domain/venue_local_time.dart';
import 'court_availability_picker.dart';

/// Glass dialog for choosing a booking slot on a court.
///
/// Returns `({DateTime start, DateTime end})` when confirmed, or null when
/// dismissed. Terms consent happens afterwards via [CourtUsageTermsDialog];
/// this dialog never submits the booking itself.
class CourtBookingDialog {
  static Future<List<({DateTime start, DateTime end})>?> show(
    BuildContext context, {
    required VenueCourt court,
    required String venueName,
    required String timezone,
    required Future<CourtAvailability> Function(
      String courtId,
      DateTime from,
      DateTime to,
    )
    loadAvailability,
    DateTime? initialDate,
    DateTime? initialSlotStart,
    bool allowDisjoint = true,
  }) {
    return GlassDialog.show<List<({DateTime start, DateTime end})>>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => _CourtBookingDialogBody(
        court: court,
        venueName: venueName,
        timezone: timezone,
        loadAvailability: loadAvailability,
        initialDate: initialDate,
        initialSlotStart: initialSlotStart,
        allowDisjoint: allowDisjoint,
      ),
    );
  }

  static List<({DateTime start, DateTime end})> mergeSlots(
    Iterable<({DateTime start, DateTime end})> slots,
  ) {
    final sorted = slots.toList()..sort((a, b) => a.start.compareTo(b.start));
    final ranges = <({DateTime start, DateTime end})>[];
    for (final slot in sorted) {
      if (ranges.isNotEmpty && ranges.last.end.isAtSameMomentAs(slot.start)) {
        ranges[ranges.length - 1] = (start: ranges.last.start, end: slot.end);
      } else {
        ranges.add(slot);
      }
    }
    return ranges;
  }
}

class _CourtBookingDialogBody extends StatefulWidget {
  final VenueCourt court;
  final String venueName;
  final String timezone;
  final DateTime? initialDate;
  final DateTime? initialSlotStart;
  final Future<CourtAvailability> Function(
    String courtId,
    DateTime from,
    DateTime to,
  )
  loadAvailability;
  final bool allowDisjoint;

  const _CourtBookingDialogBody({
    required this.court,
    required this.venueName,
    required this.timezone,
    required this.loadAvailability,
    required this.allowDisjoint,
    this.initialDate,
    this.initialSlotStart,
  });

  @override
  State<_CourtBookingDialogBody> createState() =>
      _CourtBookingDialogBodyState();
}

class _CourtBookingDialogBodyState extends State<_CourtBookingDialogBody> {
  late DateTime _date;
  final _selectedStarts = <DateTime>{};
  CourtAvailability? _availability;
  bool _loading = true;
  bool _initialSlotResolved = false;
  String? _error;
  String? _initialSlotNotice;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    final today = VenueLocalTime.today(widget.timezone);
    final lastDate = VenueLocalTime.addCalendarDays(today, 90);
    final requested =
        widget.initialDate ??
        (widget.initialSlotStart == null
            ? null
            : VenueLocalTime.dateOfInstant(
                widget.initialSlotStart!,
                widget.timezone,
              ));
    final requestedDate = requested == null
        ? today
        : DateTime(requested.year, requested.month, requested.day);
    _date = requestedDate.isBefore(today)
        ? today
        : requestedDate.isAfter(lastDate)
        ? lastDate
        : requestedDate;
    _loadAvailability();
  }

  void _applyInitialSlot(CourtAvailability availability) {
    final initialSlotStart = widget.initialSlotStart;
    if (_initialSlotResolved || initialSlotStart == null) return;
    _initialSlotResolved = true;
    if (!DateUtils.isSameDay(
      VenueLocalTime.dateOfInstant(initialSlotStart, widget.timezone),
      _date,
    )) {
      _initialSlotNotice = 'เวลาที่เลือกไม่อยู่ในวันที่กำลังแสดง';
      return;
    }
    final matchingSlot =
        CourtAvailabilityPicker(
              availability: availability,
              date: _date,
              timezone: widget.timezone,
            ).freeSlots
            .where((slot) => slot.start.isAtSameMomentAs(initialSlotStart))
            .firstOrNull;
    if (matchingSlot == null) {
      _initialSlotNotice = 'เวลาที่เลือกไม่ว่างแล้ว กรุณาเลือกเวลาใหม่';
      return;
    }
    _selectedStarts.add(matchingSlot.start);
  }

  Future<void> _loadAvailability() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      _initialSlotNotice = null;
      _availability = null;
      _selectedStarts.clear();
    });
    try {
      final availability = await widget.loadAvailability(
        widget.court.id,
        VenueLocalTime.atWallTime(_date, widget.timezone, 0),
        VenueLocalTime.atWallTime(
          VenueLocalTime.addCalendarDays(_date, 1),
          widget.timezone,
          0,
        ),
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _availability = availability;
        _loading = false;
        _applyInitialSlot(availability);
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = 'โหลดตารางว่างไม่สำเร็จ';
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final today = VenueLocalTime.today(widget.timezone);
    final lastDate = VenueLocalTime.addCalendarDays(today, 90);
    final initialDate = _date.isBefore(today)
        ? today
        : _date.isAfter(lastDate)
        ? lastDate
        : _date;
    final picked = await GlassDatePicker.show(
      context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: lastDate,
    );
    if (picked == null || !mounted || picked == _date) return;
    setState(() => _date = picked);
    await _loadAvailability();
  }

  List<({DateTime start, DateTime end})> get _ranges {
    final availability = _availability;
    if (availability == null) return [];
    return CourtBookingDialog.mergeSlots(
      CourtAvailabilityPicker(
        availability: availability,
        date: _date,
        timezone: widget.timezone,
      ).freeSlots.where((slot) => _selectedStarts.contains(slot.start)),
    );
  }

  String _time(DateTime instant) =>
      '${instant.hour.toString().padLeft(2, '0')}:${instant.minute.toString().padLeft(2, '0')}';

  void _confirm() {
    final ranges = _ranges;
    if (ranges.isEmpty || (!widget.allowDisjoint && ranges.length > 1)) {
      setState(() => _selectedStarts.clear());
      return;
    }
    Navigator.pop(context, ranges);
  }

  @override
  Widget build(BuildContext context) {
    final court = widget.court;
    final ranges = _ranges;
    final hours =
        ranges.fold<int>(
          0,
          (sum, range) => sum + range.end.difference(range.start).inMinutes,
        ) /
        60;
    final canConfirm =
        !_loading &&
        ranges.isNotEmpty &&
        (widget.allowDisjoint || ranges.length == 1);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 400,
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'จอง${court.unitLabel ?? 'สนาม'} — ${court.name}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                widget.venueName,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              Text(
                'เวลาท้องถิ่นของสนาม (${widget.timezone})',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 14),
              LitGlassSurface.frosted(
                borderRadius: 12,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                        ),
                        label: Text(
                          ThaiDateUtils.formatShortDateBE2Digit(_date),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.allowDisjoint
                            ? 'เลือกเวลาว่างได้หลายช่อง แตะซ้ำเพื่อยกเลิก'
                            : 'เลือกเวลาว่างที่ต่อเนื่องกันเพื่อเปลี่ยนเวลา',
                      ),
                      if (_initialSlotNotice != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _initialSlotNotice!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (_loading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                            color: AppColors.primaryDark,
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.15,
                            ),
                          ),
                        )
                      else if (_error != null) ...[
                        Text(_error!),
                        TextButton.icon(
                          onPressed: _loadAvailability,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('ลองใหม่'),
                        ),
                      ] else if (_availability != null)
                        CourtAvailabilityPicker(
                          availability: _availability!,
                          date: _date,
                          timezone: widget.timezone,
                          freeOnly: true,
                          selectedStarts: _selectedStarts,
                          onSlotTap: (start, end) => setState(() {
                            _initialSlotNotice = null;
                            if (!_selectedStarts.remove(start)) {
                              _selectedStarts.add(start);
                            }
                          }),
                        ),
                      const SizedBox(height: 12),
                      if (ranges.isEmpty)
                        const Text('ยังไม่ได้เลือกเวลา')
                      else ...[
                        Text(
                          'รวม ${hours == hours.roundToDouble() ? hours.toInt() : hours} ชั่วโมง • ${ranges.length} ช่วงเวลา',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        for (final range in ranges)
                          Text('${_time(range.start)}–${_time(range.end)}'),
                        if (widget.allowDisjoint && ranges.length > 1)
                          Text(
                            'จะสร้าง ${ranges.length} รายการจองแยกกัน ไม่จองเวลาคั่นกลาง',
                          ),
                        if (!widget.allowDisjoint && ranges.length > 1)
                          const Text(
                            'กรุณาเลือกเวลาต่อเนื่องกัน',
                            style: TextStyle(color: Colors.red),
                          ),
                      ],
                      if (court.priceAmount != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'ราคา ${court.priceAmount!.toStringAsFixed(0)} บาท/${_pricingUnitLabel(court.pricingUnit)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (court.approvalMode ==
                          BookingApprovalMode.ownerApproval) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.hourglass_top_rounded,
                              size: 16,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'สนามนี้ต้องรอเจ้าของอนุมัติ',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: GlassActionButton(
                  label: 'ถัดไป — อ่านเงื่อนไข',
                  isFilled: canConfirm,
                  fillColor: AppColors.primaryDark,
                  onTap: canConfirm ? _confirm : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pricingUnitLabel(String unit) => switch (unit) {
    'session' => 'รอบ',
    'match' => 'แมตช์',
    'day' => 'วัน',
    _ => 'ชั่วโมง',
  };
}
