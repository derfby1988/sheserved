import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/shared/widgets/thai_address_picker/thai_address_repository.dart';

/// Current values of the sport-club feed filter, edited by
/// [AdvancedFilterSheet].
class AdvancedFilterValues {
  String q;
  String? province;
  String? district;
  bool openOnly;
  bool joinedOnly;
  bool managedOnly;
  bool allLevelsOnly;
  bool genderAnyOnly;
  bool noFeesOnly;
  bool locationEnabled;
  double radiusKm;
  bool locationReady;

  AdvancedFilterValues({
    this.q = '',
    this.province,
    this.district,
    this.openOnly = false,
    this.joinedOnly = false,
    this.managedOnly = false,
    this.allLevelsOnly = false,
    this.genderAnyOnly = false,
    this.noFeesOnly = false,
    this.locationEnabled = false,
    this.radiusKm = 10,
    this.locationReady = false,
  });
}

/// Advanced filter sheet: free-text search, province/district,
/// quick-filter toggles, and radius selection. Returns the applied
/// [AdvancedFilterValues], or null when cancelled.
class AdvancedFilterSheet {
  static Future<AdvancedFilterValues?> show(
    BuildContext context, {
    required AdvancedFilterValues currentFilter,
    required Future<bool> Function() onRequestLocation,
    required Future<bool> Function() onRequireLogin,
  }) {
    return showModalBottomSheet<AdvancedFilterValues>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: NeumorphicTheme.baseColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _AdvancedFilterSheetBody(
        currentFilter: currentFilter,
        onRequestLocation: onRequestLocation,
        onRequireLogin: onRequireLogin,
      ),
    );
  }
}

class _AdvancedFilterSheetBody extends StatefulWidget {
  final AdvancedFilterValues currentFilter;
  final Future<bool> Function() onRequestLocation;
  final Future<bool> Function() onRequireLogin;

  const _AdvancedFilterSheetBody({
    required this.currentFilter,
    required this.onRequestLocation,
    required this.onRequireLogin,
  });

  @override
  State<_AdvancedFilterSheetBody> createState() =>
      _AdvancedFilterSheetBodyState();
}

class _AdvancedFilterSheetBodyState extends State<_AdvancedFilterSheetBody> {
  late final TextEditingController _qController;
  late final ThaiAddressRepository _addressRepository;
  List<String> _provinces = [];
  List<String> _districts = [];
  bool _loadingProvinces = false;
  bool _loadingDistricts = false;
  String? _currentProvince;
  String? _currentDistrict;
  late bool _openOnly;
  late bool _joinedOnly;
  late bool _managedOnly;
  late bool _allLevelsOnly;
  late bool _genderAnyOnly;
  late bool _noFeesOnly;
  late bool _locationEnabled;
  late double _radiusKm;
  late bool _locationReady;

  @override
  void initState() {
    super.initState();
    final current = widget.currentFilter;
    _qController = TextEditingController(text: current.q);
    _addressRepository = ThaiAddressRepository(Supabase.instance.client);
    _currentProvince = current.province;
    _currentDistrict = current.district;
    _openOnly = current.openOnly;
    _joinedOnly = current.joinedOnly;
    _managedOnly = current.managedOnly;
    _allLevelsOnly = current.allLevelsOnly;
    _genderAnyOnly = current.genderAnyOnly;
    _noFeesOnly = current.noFeesOnly;
    _locationEnabled = current.locationEnabled;
    _radiusKm = current.radiusKm;
    _locationReady = current.locationReady;
    _loadProvinces(initialProvince: current.province);
  }

  @override
  void dispose() {
    _qController.dispose();
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

  AdvancedFilterValues buildValues() {
    final query = _qController.text.trim();
    final province = _currentProvince;
    final district = _currentDistrict;
    return AdvancedFilterValues(
      q: query,
      province: province,
      district: district,
      openOnly: _openOnly,
      joinedOnly: _joinedOnly,
      managedOnly: _managedOnly,
      allLevelsOnly: _allLevelsOnly,
      genderAnyOnly: _genderAnyOnly,
      noFeesOnly: _noFeesOnly,
      locationEnabled: _locationEnabled && _locationReady,
      radiusKm: _radiusKm,
      locationReady: _locationReady,
    );
  }

  Future<void> _enableLocation() async {
    final ok = await widget.onRequestLocation();
    if (!ok || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ไม่สามารถเข้าถึงตำแหน่งได้ กรุณาอนุญาตสิทธิ์ตำแหน่ง',
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _locationReady = true;
      _locationEnabled = true;
    });
  }

  Future<void> _togglePersonal(bool value, bool managed) async {
    if (value) {
      final loggedIn = await widget.onRequireLogin();
      if (!loggedIn || !mounted) return;
    }
    setState(() {
      if (managed) {
        _managedOnly = value;
      } else {
        _joinedOnly = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicSheetShell(
      title: 'ตัวกรอง "เฉพาะก๊วน"',
      icon: Icons.filter_alt_rounded,
      onClearAll: () {
        _qController.clear();
        _currentProvince = null;
        _currentDistrict = null;
        _districts = [];
        setState(() {
          _openOnly = false;
          _joinedOnly = false;
          _managedOnly = false;
          _allLevelsOnly = false;
          _genderAnyOnly = false;
          _noFeesOnly = false;
          _locationEnabled = false;
        });
      },
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
              onPressed: () => Navigator.pop(context, buildValues()),
              text: 'แสดงผลลัพธ์',
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
            controller: _qController,
            decoration: const InputDecoration(
              labelText: 'ค้นหา "ชื่อก๊วน"',
              prefixIcon: Icon(Icons.search),
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
        const SizedBox(height: 8),
        NeumorphicSwitchTile(
          title: 'เป็นก๊วน "เปิด" เข้าร่วมได้ทันที',
          subtitle: 'ไม่ต้องรอเจ้าของอนุมัติ',
          value: _openOnly,
          onChanged: (value) => setState(() => _openOnly = value),
        ),
        NeumorphicSwitchTile(
          title: 'ที่เป็นสมาชิก',
          value: _joinedOnly,
          onChanged: (value) => _togglePersonal(value, false),
        ),
        NeumorphicSwitchTile(
          title: 'ที่ดูแล',
          value: _managedOnly,
          onChanged: (value) => _togglePersonal(value, true),
        ),
        NeumorphicSwitchTile(
          title: 'ทุกระดับ',
          subtitle: 'เปิดรับผู้เล่นทุกระดับ',
          value: _allLevelsOnly,
          onChanged: (value) => setState(() => _allLevelsOnly = value),
        ),
        NeumorphicSwitchTile(
          title: 'เปิดรับทุกเพศ',
          subtitle: 'เฉพาะก๊วนที่ไม่จำกัดเพศผู้เล่น',
          value: _genderAnyOnly,
          onChanged: (value) => setState(() => _genderAnyOnly = value),
        ),
        NeumorphicSwitchTile(
          title: 'ไม่ระบุค่าใช้จ่าย',
          subtitle: 'เฉพาะก๊วนที่ไม่มีค่าก๊วนหรือค่าใช้จ่ายเฉพาะรอบ',
          value: _noFeesOnly,
          onChanged: (value) => setState(() => _noFeesOnly = value),
        ),
        NeumorphicSwitchTile(
          title: 'ใช้ตำแหน่งปัจจุบัน',
          subtitle: _locationEnabled && _locationReady
              ? 'กรองก๊วนภายในรัศมี'
              : 'ต้องอนุญาตสิทธิ์ตำแหน่งก่อน',
          value: _locationEnabled && _locationReady,
          onChanged: (value) {
            if (value) {
              _enableLocation();
            } else {
              setState(() => _locationEnabled = false);
            }
          },
        ),
        if (_locationEnabled && _locationReady)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Text('รัศมี', style: NeumorphicTheme.sectionLabel),
                Expanded(
                  child: Slider(
                    value: _radiusKm.clamp(1, 50).toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '${_radiusKm.round()} กม.',
                    onChanged: (value) => setState(() => _radiusKm = value),
                  ),
                ),
                Text(
                  '${_radiusKm.round()} กม.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: NeumorphicTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
