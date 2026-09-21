import 'package:flutter/material.dart';

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
  late final TextEditingController _provinceController;
  late final TextEditingController _districtController;
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
    _provinceController = TextEditingController(text: current.province ?? '');
    _districtController = TextEditingController(text: current.district ?? '');
    _openOnly = current.openOnly;
    _joinedOnly = current.joinedOnly;
    _managedOnly = current.managedOnly;
    _allLevelsOnly = current.allLevelsOnly;
    _genderAnyOnly = current.genderAnyOnly;
    _noFeesOnly = current.noFeesOnly;
    _locationEnabled = current.locationEnabled;
    _radiusKm = current.radiusKm;
    _locationReady = current.locationReady;
  }

  @override
  void dispose() {
    _qController.dispose();
    _provinceController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  AdvancedFilterValues buildValues() {
    final query = _qController.text.trim();
    final province = _provinceController.text.trim();
    final district = _districtController.text.trim();
    return AdvancedFilterValues(
      q: query,
      province: province.isEmpty ? null : province,
      district: district.isEmpty ? null : district,
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
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'ตัวกรอง "เฉพาะก๊วน"',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _qController.clear();
                    _provinceController.clear();
                    _districtController.clear();
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
                  child: const Text('ล้างทั้งหมด'),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  TextField(
                    controller: _qController,
                    decoration: const InputDecoration(
                      labelText: 'ค้นหาก๊วน / สถานที่',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _provinceController,
                    decoration: const InputDecoration(labelText: 'จังหวัด'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _districtController,
                    decoration: const InputDecoration(labelText: 'อำเภอ'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('เป็นก๊วน "เปิด" เข้าร่วมได้ทันที'),
                    subtitle: const Text('ไม่ต้องรอเจ้าของอนุมัติ'),
                    value: _openOnly,
                    onChanged: (value) => setState(() => _openOnly = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ที่เป็นสมาชิก'),
                    value: _joinedOnly,
                    onChanged: (value) => _togglePersonal(value, false),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ที่ดูแล'),
                    value: _managedOnly,
                    onChanged: (value) => _togglePersonal(value, true),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ทุกระดับ'),
                    subtitle: const Text('เปิดรับผู้เล่นทุกระดับ'),
                    value: _allLevelsOnly,
                    onChanged: (value) =>
                        setState(() => _allLevelsOnly = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('เปิดรับทุกเพศ'),
                    subtitle: const Text('เฉพาะก๊วนที่ไม่จำกัดเพศผู้เล่น'),
                    value: _genderAnyOnly,
                    onChanged: (value) =>
                        setState(() => _genderAnyOnly = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ไม่ระบุค่าใช้จ่าย'),
                    subtitle: const Text(
                      'เฉพาะก๊วนที่ไม่มีค่าก๊วนหรือค่าใช้จ่ายเฉพาะรอบ',
                    ),
                    value: _noFeesOnly,
                    onChanged: (value) => setState(() => _noFeesOnly = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ใช้ตำแหน่งปัจจุบัน'),
                    subtitle: Text(
                      _locationEnabled && _locationReady
                          ? 'กรองก๊วนภายในรัศมี'
                          : 'ต้องอนุญาตสิทธิ์ตำแหน่งก่อน',
                    ),
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
                    Row(
                      children: [
                        const Text('รัศมี'),
                        Expanded(
                          child: Slider(
                            value: _radiusKm.clamp(1, 50).toDouble(),
                            min: 1,
                            max: 50,
                            divisions: 49,
                            label: '${_radiusKm.round()} กม.',
                            onChanged: (value) =>
                                setState(() => _radiusKm = value),
                          ),
                        ),
                        Text('${_radiusKm.round()} กม.'),
                      ],
                    ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ยกเลิก'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, buildValues()),
                    child: const Text('แสดงผลลัพธ์'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
