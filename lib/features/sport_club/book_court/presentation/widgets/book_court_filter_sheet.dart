import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';
import 'package:sheserved/shared/widgets/thai_address_picker/thai_address_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/book_court_filter.dart';

class BookCourtFilterSheetResult {
  const BookCourtFilterSheetResult({
    required this.filter,
    required this.query,
    this.province,
    this.district,
  });

  final BookCourtFilter filter;
  final String query;
  final String? province;
  final String? district;
}

/// Advanced filter bottom sheet for Book Court.
///
/// Edits Book Court filters, the shared keyword query and the shared
/// province/district. Booking date/time, duration, price range, minimum
/// rating, court type, amenities, and indoor/open-now remain
/// domain-specific; the shared sport value is not edited here. Follows the
/// interaction pattern of `advanced_filter_sheet.dart`.
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

  static Future<BookCourtFilterSheetResult?> show(
    BuildContext context, {
    required BookCourtFilter current,
    required String currentQuery,
    String? currentProvince,
    String? currentDistrict,
    ThaiAddressRepository? addressRepository,
  }) {
    return showModalBottomSheet<BookCourtFilterSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: NeumorphicTheme.baseColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _BookCourtFilterSheetBody(
        current: current,
        currentQuery: currentQuery,
        currentProvince: currentProvince,
        currentDistrict: currentDistrict,
        addressRepository: addressRepository,
      ),
    );
  }
}

class _BookCourtFilterSheetBody extends StatefulWidget {
  final BookCourtFilter current;
  final String currentQuery;
  final String? currentProvince;
  final String? currentDistrict;
  final ThaiAddressRepository? addressRepository;

  const _BookCourtFilterSheetBody({
    required this.current,
    required this.currentQuery,
    this.currentProvince,
    this.currentDistrict,
    this.addressRepository,
  });

  @override
  State<_BookCourtFilterSheetBody> createState() =>
      _BookCourtFilterSheetBodyState();
}

class _BookCourtFilterSheetBodyState extends State<_BookCourtFilterSheetBody> {
  late final TextEditingController _queryController;
  late final ThaiAddressRepository _addressRepository =
      widget.addressRepository ??
      ThaiAddressRepository(Supabase.instance.client);
  List<String> _provinces = [];
  List<String> _districts = [];
  bool _loadingProvinces = false;
  bool _loadingDistricts = false;
  String? _currentProvince;
  String? _currentDistrict;
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

  bool get _hasPriceInput =>
      _minPrice.text.trim().isNotEmpty || _maxPrice.text.trim().isNotEmpty;

  bool get _hasPriceSlot =>
      _date != null && _startTime != null && _duration != null;

  bool get _priceSlotFitsDay =>
      _startTime != null &&
      _duration != null &&
      _startTime!.hour * 60 + _startTime!.minute + _duration!.inMinutes <= 1440;

  bool get _validPriceInputs {
    final minRaw = _minPrice.text.trim();
    final maxRaw = _maxPrice.text.trim();
    final min = minRaw.isEmpty ? null : double.tryParse(minRaw);
    final max = maxRaw.isEmpty ? null : double.tryParse(maxRaw);
    return (minRaw.isEmpty || min != null && min >= 0) &&
        (maxRaw.isEmpty || max != null && max >= 0) &&
        (min == null || max == null || min <= max);
  }

  bool get _canApply =>
      _validPriceInputs &&
      (!_hasPriceInput || (_hasPriceSlot && _priceSlotFitsDay));

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.currentQuery);
    _currentProvince = widget.currentProvince;
    _currentDistrict = widget.currentDistrict;
    _loadProvinces(initialProvince: widget.currentProvince);
  }

  @override
  void dispose() {
    _queryController.dispose();
    _minPrice.dispose();
    _maxPrice.dispose();
    super.dispose();
  }

  Future<void> _loadProvinces({String? initialProvince}) async {
    setState(() => _loadingProvinces = true);
    try {
      final provinces = await _addressRepository.getAllProvinces();
      if (!mounted) return;
      setState(() {
        _provinces = provinces;
        _loadingProvinces = false;
        if (initialProvince != null && !provinces.contains(initialProvince)) {
          _currentProvince = null;
          _currentDistrict = null;
        }
      });
      if (initialProvince != null && provinces.contains(initialProvince)) {
        await _selectProvince(
          initialProvince,
          initialDistrict: _currentDistrict,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProvinces = false);
    }
  }

  Future<void> _selectProvince(
    String? province, {
    String? initialDistrict,
  }) async {
    setState(() {
      _currentProvince = province;
      _currentDistrict = null;
      _districts = [];
      _loadingDistricts = province != null;
    });
    if (province == null) return;
    try {
      final districts = await _addressRepository.getDistrictsByProvince(
        province,
      );
      if (!mounted || _currentProvince != province) return;
      setState(() {
        _districts = districts;
        _loadingDistricts = false;
        if (initialDistrict != null && districts.contains(initialDistrict)) {
          _currentDistrict = initialDistrict;
        }
      });
    } catch (_) {
      if (mounted && _currentProvince == province) {
        setState(() => _loadingDistricts = false);
      }
    }
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

  BookCourtFilterSheetResult _buildResult() {
    return BookCourtFilterSheetResult(
      query: _queryController.text.trim(),
      province: _currentProvince,
      district: _currentDistrict,
      filter: BookCourtFilter(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicSheetShell(
      title: 'ตัวกรองสนาม',
      icon: Icons.stadium_rounded,
      onClearAll: () {
        setState(() {
          _queryController.clear();
          _currentProvince = null;
          _currentDistrict = null;
          _districts = [];
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
      onClose: () => Navigator.of(context).pop(),
      footer: Row(
        children: [
          Expanded(
            child: NeumorphicPillButton(
              text: 'ยกเลิก',
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: NeumorphicVerifyButton(
              onPressed: _canApply
                  ? () => Navigator.pop(context, _buildResult())
                  : null,
              isEnabled: _canApply,
              text: 'ใช้ตัวกรอง',
              height: 48,
            ),
          ),
        ],
      ),
      children: [
        NeumorphicInsetBox(
          height: null,
          borderRadius: 14,
          child: TextField(
            key: const ValueKey('book_court_search_query'),
            controller: _queryController,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'ค้นหาสนาม',
              prefixIcon: Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        NeumorphicInsetBox(
          height: null,
          borderRadius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonFormField<String>(
            initialValue: _currentProvince ?? '',
            menuMaxHeight: 320,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'จังหวัด',
              helperText: _loadingProvinces ? 'กำลังโหลด...' : null,
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('ทุกจังหวัด'),
              ),
              if (_currentProvince != null &&
                  !_provinces.contains(_currentProvince))
                DropdownMenuItem<String>(
                  value: _currentProvince,
                  child: Text(_currentProvince!),
                ),
              ..._provinces.map(
                (province) => DropdownMenuItem<String>(
                  value: province,
                  child: Text(province),
                ),
              ),
            ],
            onChanged: _loadingProvinces
                ? null
                : (province) => _selectProvince(
                    province?.isEmpty == true ? null : province,
                  ),
          ),
        ),
        const SizedBox(height: 12),
        NeumorphicInsetBox(
          height: null,
          borderRadius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonFormField<String>(
            initialValue: _currentDistrict ?? '',
            menuMaxHeight: 320,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'อำเภอ/เขต',
              helperText: _currentProvince == null
                  ? 'เลือกจังหวัดก่อน'
                  : (_loadingDistricts ? 'กำลังโหลด...' : null),
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('ทุกอำเภอ/เขต'),
              ),
              if (_currentDistrict != null &&
                  !_districts.contains(_currentDistrict))
                DropdownMenuItem<String>(
                  value: _currentDistrict,
                  child: Text(_currentDistrict!),
                ),
              ..._districts.map(
                (district) => DropdownMenuItem<String>(
                  value: district,
                  child: Text(district),
                ),
              ),
            ],
            onChanged: _currentProvince == null || _loadingDistricts
                ? null
                : (district) => setState(
                    () => _currentDistrict = district?.isEmpty == true
                        ? null
                        : district,
                  ),
          ),
        ),
        const SizedBox(height: 18),

        // Booking date/time
        const Text('วันและเวลา', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: NeumorphicPillButton(
                text: _dateLabel,
                icon: Icons.calendar_today_rounded,
                active: _date != null,
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: NeumorphicPillButton(
                text: _startTime == null
                    ? 'เวลาเริ่ม'
                    : _startTime!.format(context),
                icon: Icons.schedule_rounded,
                active: _startTime != null,
                onPressed: _pickTime,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _durations)
              NeumorphicChoiceChip(
                label: entry.label,
                selected: _duration == entry.duration,
                onSelected: (sel) =>
                    setState(() => _duration = sel ? entry.duration : null),
              ),
          ],
        ),
        const SizedBox(height: 18),

        // Price range
        const Text('ช่วงราคา', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: NeumorphicInsetBox(
                height: null,
                borderRadius: 14,
                child: TextField(
                  controller: _minPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ราคาต่ำสุด',
                    suffixText: 'บาท',
                    filled: true,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: NeumorphicInsetBox(
                height: null,
                borderRadius: 14,
                child: TextField(
                  controller: _maxPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ราคาสูงสุด',
                    suffixText: 'บาท',
                    filled: true,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          !_validPriceInputs
              ? 'กรุณาตรวจสอบช่วงราคาที่กรอก'
              : _hasPriceInput && !_hasPriceSlot
              ? 'เลือกวันที่ เวลาเริ่ม และระยะเวลาเพื่อกรองราคาของช่วงที่เลือก'
              : _hasPriceInput && !_priceSlotFitsDay
              ? 'เวลาและระยะเวลาต้องสิ้นสุดภายในวันเดียวกัน'
              : 'ราคาเทียบกับยอดรวม ณ วันและเวลาที่เลือก ตามเวลาท้องถิ่นของแต่ละสนาม',
          style: TextStyle(
            fontSize: 12,
            color:
                !_validPriceInputs ||
                    (_hasPriceInput && (!_hasPriceSlot || !_priceSlotFitsDay))
                ? Colors.red.shade700
                : NeumorphicTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 18),

        // Rating
        const Text('คะแนนขั้นต่ำ', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in [5.0, 7.0, 9.0])
              NeumorphicChoiceChip(
                label: '${r.toStringAsFixed(1)}+',
                icon: Icons.star_rounded,
                selected: _minRating == r,
                onSelected: (sel) =>
                    setState(() => _minRating = sel ? r : null),
              ),
          ],
        ),
        const SizedBox(height: 18),

        // Court type + flags
        const Text('ประเภทสนาม', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _courtTypes.entries)
              NeumorphicChoiceChip(
                label: entry.value,
                selected: _courtType == entry.key,
                onSelected: (sel) =>
                    setState(() => _courtType = sel ? entry.key : null),
              ),
          ],
        ),
        const SizedBox(height: 8),
        NeumorphicSwitchTile(
          title: 'เฉพาะสนามในร่ม',
          value: _indoorOnly,
          onChanged: (v) => setState(() => _indoorOnly = v),
        ),
        NeumorphicSwitchTile(
          title: 'เปิดอยู่ตอนนี้',
          value: _openNowOnly,
          onChanged: (v) => setState(() => _openNowOnly = v),
        ),
        const SizedBox(height: 12),

        // Amenities
        const Text('สิ่งอำนวยความสะดวก', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in BookCourtFilterSheet.amenityOptions.entries)
              NeumorphicChoiceChip(
                label: entry.value,
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
      ],
    );
  }
}
