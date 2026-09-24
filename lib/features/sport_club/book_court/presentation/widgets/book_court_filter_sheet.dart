import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../domain/book_court_filter.dart';

/// Advanced filter bottom sheet for Book Court.
///
/// Edits the domain filter only: booking date/time, duration, price range,
/// minimum rating, court type, amenities, indoor/open-now. Returns the
/// applied [BookCourtFilter] or null when cancelled. Follows the
/// interaction pattern of `advanced_filter_sheet.dart` but uses the Book
/// Court model exclusively — shared sport/location values are not edited
/// here.
class BookCourtFilterSheet {
  /// Amenity keys the venue supply schema supports.
  static const amenityOptions = <String, String>{
    'parking': 'ที่จอดรถ',
    'restroom': 'ห้องน้ำ',
    'shower': 'ห้องอาบน้ำ',
    'ev_charging': 'ที่ชาร์จ EV',
    'equipment_rental': 'เช่าอุปกรณ์',
    'lighting': 'ไฟส่องสว่าง',
    'locker': 'ตู้ล็อกเกอร์',
    'wifi': 'Wi-Fi',
    'cafe': 'คาเฟ่',
    'first_aid': 'ปฐมพยาบาล',
  };

  static Future<BookCourtFilter?> show(
    BuildContext context, {
    required BookCourtFilter current,
  }) {
    return showModalBottomSheet<BookCourtFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) =>
          _BookCourtFilterSheetBody(current: current),
    );
  }
}

class _BookCourtFilterSheetBody extends StatefulWidget {
  final BookCourtFilter current;
  const _BookCourtFilterSheetBody({required this.current});

  @override
  State<_BookCourtFilterSheetBody> createState() =>
      _BookCourtFilterSheetBodyState();
}

class _BookCourtFilterSheetBodyState
    extends State<_BookCourtFilterSheetBody> {
  late DateTime? _date = widget.current.date;
  late TimeOfDay? _startTime = widget.current.startTime;
  late Duration? _duration = widget.current.duration;
  late final TextEditingController _minPrice = TextEditingController(
    text: widget.current.minPrice?.toStringAsFixed(0) ?? '',
  );
  late final TextEditingController _maxPrice = TextEditingController(
    text: widget.current.maxPrice?.toStringAsFixed(0) ?? '',
  );
  late double? _minRating = widget.current.minRating;
  late Set<String> _amenityIds = {...widget.current.amenityIds};
  late String? _courtType = widget.current.courtType;
  late bool _indoorOnly = widget.current.indoorOnly;
  late bool _openNowOnly = widget.current.openNowOnly;

  static const _courtTypes = <String, String>{
    'standard': 'มาตรฐาน',
    'synthetic': 'พื้นสังเคราะห์',
    'grass': 'หญ้า',
    'clay': 'ดิน',
    'hard': 'พื้นแข็ง',
    'wood': 'ไม้',
  };

  static const _durations = <({Duration duration, String label})>[
    (duration: Duration(minutes: 60), label: '1 ชม.'),
    (duration: Duration(minutes: 90), label: '1.5 ชม.'),
    (duration: Duration(minutes: 120), label: '2 ชม.'),
    (duration: Duration(minutes: 180), label: '3 ชม.'),
  ];

  @override
  void dispose() {
    _minPrice.dispose();
    _maxPrice.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  String get _dateLabel {
    if (_date == null) return 'เลือกวันที่';
    return '${_date!.day}/${_date!.month}/${_date!.year + 543}';
  }

  BookCourtFilter _buildResult() {
    return BookCourtFilter(
      date: _date,
      startTime: _startTime,
      duration: _duration,
      minPrice: double.tryParse(_minPrice.text.trim()),
      maxPrice: double.tryParse(_maxPrice.text.trim()),
      minRating: _minRating,
      availableOnly: widget.current.availableOnly,
      bookedByMeOnly: widget.current.bookedByMeOnly,
      ownerOnly: widget.current.ownerOnly,
      amenityIds: _amenityIds,
      courtType: _courtType,
      indoorOnly: _indoorOnly,
      openNowOnly: _openNowOnly,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
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
              const Text(
                'ตัวกรองสนาม',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),

              // Booking date/time
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(_dateLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(
                        _startTime == null
                            ? 'เวลาเริ่ม'
                            : _startTime!.format(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in _durations)
                    ChoiceChip(
                      label: Text(entry.label),
                      selected: _duration == entry.duration,
                      onSelected: (sel) => setState(
                        () => _duration = sel ? entry.duration : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Price range
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minPrice,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ราคาต่ำสุด (บาท)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _maxPrice,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ราคาสูงสุด (บาท)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Rating
              Wrap(
                spacing: 8,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('คะแนนขั้นต่ำ'),
                  ),
                  for (final r in [3.0, 4.0, 4.5])
                    ChoiceChip(
                      label: Text('${r.toStringAsFixed(1)}+ ⭐'),
                      selected: _minRating == r,
                      onSelected: (sel) =>
                          setState(() => _minRating = sel ? r : null),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Court type + flags
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in _courtTypes.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _courtType == entry.key,
                      onSelected: (sel) => setState(
                        () => _courtType = sel ? entry.key : null,
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('เฉพาะสนามในร่ม'),
                value: _indoorOnly,
                onChanged: (v) => setState(() => _indoorOnly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('เปิดอยู่ตอนนี้'),
                value: _openNowOnly,
                onChanged: (v) => setState(() => _openNowOnly = v),
              ),
              const SizedBox(height: 8),

              // Amenities
              const Text(
                'สิ่งอำนวยความสะดวก',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in BookCourtFilterSheet
                      .amenityOptions
                      .entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: _amenityIds.contains(entry.key),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _amenityIds.add(entry.key);
                        } else {
                          _amenityIds.remove(entry.key);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _date = null;
                        _startTime = null;
                        _duration = null;
                        _minPrice.clear();
                        _maxPrice.clear();
                        _minRating = null;
                        _amenityIds = {};
                        _courtType = null;
                        _indoorOnly = false;
                        _openNowOnly = false;
                      });
                    },
                    child: const Text('ล้างทั้งหมด'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                    ),
                    onPressed: () => Navigator.pop(context, _buildResult()),
                    child: const Text('ใช้ตัวกรอง'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
