import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';
import 'package:sheserved/shared/widgets/thai_address_picker/thai_address_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/find_coach_filter.dart';

class CoachFilterSheetResult {
  const CoachFilterSheetResult({
    required this.filter,
    required this.query,
    this.province,
    this.district,
  });

  final FindCoachFilter filter;
  final String query;
  final String? province;
  final String? district;
}

/// Advanced filter sheet for Find Coach: keyword, province/district, skill
/// level, max rate, teaching mode, specialties, verified/available toggles.
/// Returns the applied filters or null when cancelled.
class CoachFilterSheet {
  static const skillLevels = <String, String>{
    'beginner': 'เริ่มต้น',
    'intermediate': 'ระดับกลาง',
    'advanced': 'ขั้นสูง',
    'pro': 'อาชีพ',
  };

  static Future<CoachFilterSheetResult?> show(
    BuildContext context, {
    required FindCoachFilter current,
    required String currentQuery,
    String? currentProvince,
    String? currentDistrict,
    List<String> specialtyOptions = const [],
    bool signedIn = false,
    ThaiAddressRepository? addressRepository,
  }) {
    return showModalBottomSheet<CoachFilterSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: NeumorphicTheme.baseColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _CoachFilterSheetBody(
        current: current,
        currentQuery: currentQuery,
        currentProvince: currentProvince,
        currentDistrict: currentDistrict,
        specialtyOptions: specialtyOptions,
        signedIn: signedIn,
        addressRepository: addressRepository,
      ),
    );
  }
}

class _CoachFilterSheetBody extends StatefulWidget {
  final FindCoachFilter current;
  final String currentQuery;
  final String? currentProvince;
  final String? currentDistrict;
  final List<String> specialtyOptions;
  final bool signedIn;
  final ThaiAddressRepository? addressRepository;

  const _CoachFilterSheetBody({
    required this.current,
    required this.currentQuery,
    this.currentProvince,
    this.currentDistrict,
    required this.specialtyOptions,
    required this.signedIn,
    this.addressRepository,
  });

  @override
  State<_CoachFilterSheetBody> createState() => _CoachFilterSheetBodyState();
}

class _CoachFilterSheetBodyState extends State<_CoachFilterSheetBody> {
  late final _queryController = TextEditingController(
    text: widget.currentQuery,
  );
  late final ThaiAddressRepository _addressRepository =
      widget.addressRepository ??
      ThaiAddressRepository(Supabase.instance.client);
  List<String> _provinces = [];
  List<String> _districts = [];
  bool _loadingProvinces = false;
  bool _loadingDistricts = false;
  late String? _currentProvince;
  late String? _currentDistrict;
  late String? _skillLevel = widget.current.skillLevel;
  late final _maxRate = TextEditingController(
    text: widget.current.maxHourlyRate?.toStringAsFixed(0) ?? '',
  );
  late String? _teachingMode = widget.current.teachingMode;
  late bool _verifiedOnly = widget.current.verifiedOnly;
  late bool _availableOnly = widget.current.availableOnly;
  late double? _minRating10 = widget.current.minRating10;
  late bool _favoritesOnly = widget.current.favoritesOnly;
  late bool _myCoachesOnly = widget.current.myCoachesOnly;
  late String? _offeringType = widget.current.offeringType;
  late List<String> _specialties = [...widget.current.specialties];
  final _specialtyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentProvince = widget.currentProvince;
    _currentDistrict = widget.currentDistrict;
    _loadProvinces(initialProvince: widget.currentProvince);
  }

  @override
  void dispose() {
    _queryController.dispose();
    _maxRate.dispose();
    _specialtyController.dispose();
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

  void _addSpecialty([String? value]) {
    final label = (value ?? _specialtyController.text).trim();
    if (label.isEmpty || _specialties.contains(label)) return;
    _specialtyController.clear();
    setState(() => _specialties.add(label));
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicSheetShell(
      title: 'ตัวกรองโค้ช',
      icon: Icons.sports_rounded,
      onClearAll: () => setState(() {
        _queryController.clear();
        _currentProvince = null;
        _currentDistrict = null;
        _districts = [];
        _skillLevel = null;
        _teachingMode = null;
        _maxRate.clear();
        _verifiedOnly = false;
        _availableOnly = false;
        _minRating10 = null;
        _favoritesOnly = false;
        _myCoachesOnly = false;
        _offeringType = null;
        _specialties = [];
      }),
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
              onPressed: () => Navigator.pop(
                context,
                CoachFilterSheetResult(
                  query: _queryController.text.trim(),
                  province: _currentProvince,
                  district: _currentDistrict,
                  filter: FindCoachFilter(
                    skillLevel: _skillLevel,
                    specialties: _specialties,
                    maxHourlyRate: double.tryParse(_maxRate.text.trim()),
                    verifiedOnly: _verifiedOnly,
                    availableOnly: _availableOnly,
                    teachingMode: _teachingMode,
                    minRating10: _minRating10,
                    favoritesOnly: _favoritesOnly,
                    myCoachesOnly: _myCoachesOnly,
                    offeringType: _offeringType,
                  ),
                ),
              ),
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
            key: const ValueKey('coach_filter_search_query'),
            controller: _queryController,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'ค้นหาโค้ช',
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
            value: _currentProvince ?? '',
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
            value: _currentDistrict ?? '',
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
        const Text('ระดับผู้เล่น', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in CoachFilterSheet.skillLevels.entries)
              NeumorphicChoiceChip(
                label: entry.value,
                selected: _skillLevel == entry.key,
                onSelected: (sel) =>
                    setState(() => _skillLevel = sel ? entry.key : null),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('รูปแบบการสอน', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (mode, label) in [
              ('onsite', 'ออนไซต์'),
              ('online', 'ออนไลน์'),
            ])
              NeumorphicChoiceChip(
                label: label,
                selected: _teachingMode == mode,
                onSelected: (sel) =>
                    setState(() => _teachingMode = sel ? mode : null),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('ประเภทบริการ', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (type, label) in [
              ('one_on_one', 'สอนตัวต่อตัว'),
              ('group_class', 'คลาสกลุ่ม'),
              ('course', 'หลักสูตร'),
            ])
              NeumorphicChoiceChip(
                label: label,
                selected: _offeringType == type,
                onSelected: (sel) =>
                    setState(() => _offeringType = sel ? type : null),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('คะแนนขั้นต่ำ (1–10)', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _minRating10 ?? 0,
                min: 0,
                max: 10,
                divisions: 10,
                label: _minRating10 == null
                    ? 'ไม่จำกัด'
                    : _minRating10!.toStringAsFixed(0),
                onChanged: (v) =>
                    setState(() => _minRating10 = v <= 0 ? null : v),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                _minRating10 == null
                    ? 'ทั้งหมด'
                    : '≥ ${_minRating10!.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        NeumorphicInsetBox(
          height: null,
          borderRadius: 14,
          child: TextField(
            controller: _maxRate,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'ราคาต่อชั่วโมงสูงสุด (บาท)',
              prefixIcon: Icon(Icons.payments_rounded),
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
        const SizedBox(height: 8),
        NeumorphicSwitchTile(
          title: 'เฉพาะโค้ชที่ยืนยันตัวตน',
          value: _verifiedOnly,
          onChanged: (v) => setState(() => _verifiedOnly = v),
        ),
        NeumorphicSwitchTile(
          title: 'มีตารางว่าง',
          value: _availableOnly,
          onChanged: (v) => setState(() => _availableOnly = v),
        ),
        if (widget.signedIn) ...[
          NeumorphicSwitchTile(
            title: 'เฉพาะโค้ชที่บันทึกไว้',
            value: _favoritesOnly,
            onChanged: (v) => setState(() => _favoritesOnly = v),
          ),
          NeumorphicSwitchTile(
            title: 'เฉพาะโค้ชที่เคยเรียนด้วย',
            value: _myCoachesOnly,
            onChanged: (v) => setState(() => _myCoachesOnly = v),
          ),
        ],
        const SizedBox(height: 12),
        const Text('ความเชี่ยวชาญ', style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final spec in _specialties)
              NeumorphicTagChip(
                label: spec,
                onDeleted: () => setState(() => _specialties.remove(spec)),
              ),
          ],
        ),
        if (widget.specialtyOptions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final spec in widget.specialtyOptions)
                NeumorphicChoiceChip(
                  label: spec,
                  selected: _specialties.contains(spec),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _specialties.add(spec);
                    } else {
                      _specialties.remove(spec);
                    }
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: NeumorphicInsetBox(
                height: null,
                borderRadius: 14,
                child: TextField(
                  controller: _specialtyController,
                  decoration: const InputDecoration(
                    hintText: 'เช่น วิ่ง, สมาธิ, ฟื้นฟู',
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
                  onSubmitted: _addSpecialty,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'เพิ่มความเชี่ยวชาญ',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _addSpecialty,
                  borderRadius: BorderRadius.circular(22),
                  child: NeumorphicContainer(
                    width: 44,
                    height: 44,
                    shape: BoxShape.circle,
                    depth: 3,
                    blur: 6,
                    child: const Icon(
                      Icons.add_rounded,
                      color: NeumorphicTheme.primaryBlue,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
