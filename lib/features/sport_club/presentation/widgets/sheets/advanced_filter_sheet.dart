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
  }) async {
    final qController = TextEditingController(text: currentFilter.q);
    final provinceController = TextEditingController(
      text: currentFilter.province ?? '',
    );
    final districtController = TextEditingController(
      text: currentFilter.district ?? '',
    );
    var openOnly = currentFilter.openOnly;
    var joinedOnly = currentFilter.joinedOnly;
    var managedOnly = currentFilter.managedOnly;
    var allLevelsOnly = currentFilter.allLevelsOnly;
    var genderAnyOnly = currentFilter.genderAnyOnly;
    var noFeesOnly = currentFilter.noFeesOnly;
    var locationEnabled = currentFilter.locationEnabled;
    var radiusKm = currentFilter.radiusKm;
    var locationReady = currentFilter.locationReady;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> enableLocation() async {
            final ok = await onRequestLocation();
            if (!ok || !sheetContext.mounted) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'ไม่สามารถเข้าถึงตำแหน่งได้ กรุณาอนุญาตสิทธิ์ตำแหน่ง',
                    ),
                  ),
                );
              }
              return;
            }
            setSheetState(() {
              locationReady = true;
              locationEnabled = true;
            });
          }

          Future<void> togglePersonal(bool value, bool managed) async {
            if (value) {
              final loggedIn = await onRequireLogin();
              if (!loggedIn || !sheetContext.mounted) return;
            }
            setSheetState(() {
              if (managed) {
                managedOnly = value;
              } else {
                joinedOnly = value;
              }
            });
          }

          return FractionallySizedBox(
            heightFactor: 0.9,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          qController.clear();
                          provinceController.clear();
                          districtController.clear();
                          setSheetState(() {
                            openOnly = false;
                            joinedOnly = false;
                            managedOnly = false;
                            allLevelsOnly = false;
                            genderAnyOnly = false;
                            noFeesOnly = false;
                            locationEnabled = false;
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
                          controller: qController,
                          decoration: const InputDecoration(
                            labelText: 'ค้นหาก๊วน / สถานที่',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: provinceController,
                          decoration: const InputDecoration(
                            labelText: 'จังหวัด',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: districtController,
                          decoration: const InputDecoration(labelText: 'อำเภอ'),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('เป็นก๊วน "เปิด" เข้าร่วมได้ทันที'),
                          subtitle: const Text('ไม่ต้องรอเจ้าของอนุมัติ'),
                          value: openOnly,
                          onChanged: (value) =>
                              setSheetState(() => openOnly = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('ที่เป็นสมาชิก'),
                          value: joinedOnly,
                          onChanged: (value) => togglePersonal(value, false),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('ที่ดูแล'),
                          value: managedOnly,
                          onChanged: (value) => togglePersonal(value, true),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('ทุกระดับ'),
                          subtitle: const Text('เปิดรับผู้เล่นทุกระดับ'),
                          value: allLevelsOnly,
                          onChanged: (value) =>
                              setSheetState(() => allLevelsOnly = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('เปิดรับทุกเพศ'),
                          subtitle: const Text(
                            'เฉพาะก๊วนที่ไม่จำกัดเพศผู้เล่น',
                          ),
                          value: genderAnyOnly,
                          onChanged: (value) =>
                              setSheetState(() => genderAnyOnly = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('ไม่ระบุค่าใช้จ่าย'),
                          subtitle: const Text(
                            'เฉพาะก๊วนที่ไม่มีค่าก๊วนหรือค่าใช้จ่ายเฉพาะรอบ',
                          ),
                          value: noFeesOnly,
                          onChanged: (value) =>
                              setSheetState(() => noFeesOnly = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('ใช้ตำแหน่งปัจจุบัน'),
                          subtitle: Text(
                            locationEnabled && locationReady
                                ? 'กรองก๊วนภายในรัศมี'
                                : 'ต้องอนุญาตสิทธิ์ตำแหน่งก่อน',
                          ),
                          value: locationEnabled && locationReady,
                          onChanged: (value) {
                            if (value) {
                              enableLocation();
                            } else {
                              setSheetState(() => locationEnabled = false);
                            }
                          },
                        ),
                        if (locationEnabled && locationReady)
                          Row(
                            children: [
                              const Text('รัศมี'),
                              Expanded(
                                child: Slider(
                                  value: radiusKm.clamp(1, 50).toDouble(),
                                  min: 1,
                                  max: 50,
                                  divisions: 49,
                                  label: '${radiusKm.round()} กม.',
                                  onChanged: (value) =>
                                      setSheetState(() => radiusKm = value),
                                ),
                              ),
                              Text('${radiusKm.round()} กม.'),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('ยกเลิก'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          child: const Text('แสดงผลลัพธ์'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    final query = qController.text.trim();
    final province = provinceController.text.trim();
    final district = districtController.text.trim();
    qController.dispose();
    provinceController.dispose();
    districtController.dispose();
    if (applied != true) return null;
    return AdvancedFilterValues(
      q: query,
      province: province.isEmpty ? null : province,
      district: district.isEmpty ? null : district,
      openOnly: openOnly,
      joinedOnly: joinedOnly,
      managedOnly: managedOnly,
      allLevelsOnly: allLevelsOnly,
      genderAnyOnly: genderAnyOnly,
      noFeesOnly: noFeesOnly,
      locationEnabled: locationEnabled && locationReady,
      radiusKm: radiusKm,
      locationReady: locationReady,
    );
  }
}
