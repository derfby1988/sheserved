import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/book_court_models.dart';
import '../../domain/venue_local_time.dart';

/// Bottom sheet for choosing a booking slot on a court.
///
/// Returns `({DateTime start, DateTime end})` when confirmed, or null when
/// dismissed. Terms consent happens afterwards via [CourtUsageTermsDialog];
/// this sheet never submits the booking itself.
class CourtBookingSheet {
  static Future<({DateTime start, DateTime end})?> show(
    BuildContext context, {
    required VenueCourt court,
    required String venueName,
    required String timezone,
    DateTime? initialDate,
  }) {
    return showModalBottomSheet<({DateTime start, DateTime end})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: NeumorphicTheme.baseColor,
      builder: (sheetContext) => _CourtBookingSheetBody(
        court: court,
        venueName: venueName,
        timezone: timezone,
        initialDate: initialDate,
      ),
    );
  }
}

class _CourtBookingSheetBody extends StatefulWidget {
  final VenueCourt court;
  final String venueName;
  final String timezone;
  final DateTime? initialDate;

  const _CourtBookingSheetBody({
    required this.court,
    required this.venueName,
    required this.timezone,
    this.initialDate,
  });

  @override
  State<_CourtBookingSheetBody> createState() => _CourtBookingSheetBodyState();
}

class _CourtBookingSheetBodyState extends State<_CourtBookingSheetBody> {
  late DateTime _date;
  TimeOfDay? _start;
  int _hours = 1;

  @override
  void initState() {
    super.initState();
    final today = VenueLocalTime.today(widget.timezone);
    final lastDate = VenueLocalTime.addCalendarDays(today, 90);
    final requested = widget.initialDate;
    final requestedDate = requested == null
        ? today
        : DateTime(requested.year, requested.month, requested.day);
    _date = requestedDate.isBefore(today)
        ? today
        : requestedDate.isAfter(lastDate)
        ? lastDate
        : requestedDate;
  }

  Future<void> _pickDate() async {
    final today = VenueLocalTime.today(widget.timezone);
    final lastDate = VenueLocalTime.addCalendarDays(today, 90);
    final initialDate = _date.isBefore(today)
        ? today
        : _date.isAfter(lastDate)
        ? lastDate
        : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: lastDate,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _start ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked != null) setState(() => _start = picked);
  }

  @override
  Widget build(BuildContext context) {
    final court = widget.court;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'จอง${court.unitLabel ?? 'สนาม'} — ${court.name}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                widget.venueName,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              Text(
                'เวลาท้องถิ่นของสนาม (${widget.timezone})',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(
                        '${_date.day}/${_date.month}/${_date.year + 543}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickStart,
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(
                        _start == null ? 'เวลาเริ่ม' : _start!.format(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final h in [1, 2, 3])
                    ChoiceChip(
                      label: Text('$h ชม.'),
                      selected: _hours == h,
                      onSelected: (sel) =>
                          setState(() => _hours = sel ? h : _hours),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (court.priceAmount != null)
                Text(
                  'ราคา ${court.priceAmount!.toStringAsFixed(0)} บาท/${_pricingUnitLabel(court.pricingUnit)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (court.approvalMode == BookingApprovalMode.ownerApproval)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
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
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _start == null
                      ? null
                      : () {
                          final start = VenueLocalTime.atWallTime(
                            _date,
                            widget.timezone,
                            _start!.hour,
                            _start!.minute,
                          );
                          Navigator.pop(context, (
                            start: start,
                            end: start.add(Duration(hours: _hours)),
                          ));
                        },
                  child: const Text('ถัดไป — อ่านเงื่อนไข'),
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
