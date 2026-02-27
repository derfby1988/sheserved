import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import 'thai_address_repository.dart';

/// ข้อมูลที่อยู่ที่เลือกแล้ว
class ThaiAddress {
  final String postalCode;
  final String province;
  final String district;
  final String subDistrict;
  final String? localGovType;
  final CommunityLeaderRole? leaderRole;

  const ThaiAddress({
    required this.postalCode,
    required this.province,
    required this.district,
    required this.subDistrict,
    this.localGovType,
    this.leaderRole,
  });

  String get fullAddress => 'ต.$subDistrict อ.$district จ.$province $postalCode';

  @override
  String toString() => fullAddress;
}

/// Cascading Thai Address Picker Widget
/// Flow: รหัสไปรษณีย์ → จังหวัด → อำเภอ → ตำบล
class ThaiAddressPicker extends StatefulWidget {
  final void Function(ThaiAddress address)? onAddressSelected;
  final ThaiAddress? initialAddress;

  const ThaiAddressPicker({
    super.key,
    this.onAddressSelected,
    this.initialAddress,
  });

  @override
  State<ThaiAddressPicker> createState() => _ThaiAddressPickerState();
}

class _ThaiAddressPickerState extends State<ThaiAddressPicker> {
  late ThaiAddressRepository _repository;
  final TextEditingController _postalCodeController = TextEditingController();

  // State
  String? _postalCode;
  String? _selectedProvince;
  String? _selectedDistrict;
  String? _selectedSubDistrict;

  List<String> _provinces = [];
  List<String> _districts = [];
  List<String> _subDistricts = [];

  bool _isLoadingProvinces = false;
  bool _isLoadingDistricts = false;
  bool _isLoadingSubDistricts = false;
  bool _isLoadingLeaderRole = false;
  String? _postalCodeError;
  CommunityLeaderRole? _leaderRole;

  @override
  void initState() {
    super.initState();
    _repository = ThaiAddressRepository(Supabase.instance.client);
    if (widget.initialAddress != null) {
      _postalCodeController.text = widget.initialAddress!.postalCode;
      _postalCode = widget.initialAddress!.postalCode;
      _selectedProvince = widget.initialAddress!.province;
      _selectedDistrict = widget.initialAddress!.district;
      _selectedSubDistrict = widget.initialAddress!.subDistrict;
    }
  }

  @override
  void dispose() {
    _postalCodeController.dispose();
    super.dispose();
  }

  /// เมื่อกรอกรหัสไปรษณีย์ครบ 5 หลัก
  Future<void> _onPostalCodeChanged(String value) async {
    // Reset ทุกอย่าง
    setState(() {
      _selectedProvince = null;
      _selectedDistrict = null;
      _selectedSubDistrict = null;
      _provinces = [];
      _districts = [];
      _subDistricts = [];
      _postalCodeError = null;
      _leaderRole = null;
    });

    if (value.length != 5) return;

    setState(() {
      _postalCode = value;
      _isLoadingProvinces = true;
    });

    try {
      final provinces = await _repository.getProvincesByPostalCode(value);
      if (provinces.isEmpty) {
        setState(() {
          _postalCodeError = 'ไม่พบรหัสไปรษณีย์นี้';
          _isLoadingProvinces = false;
        });
        return;
      }
      setState(() {
        _provinces = provinces;
        _isLoadingProvinces = false;
        // ถ้ามีจังหวัดเดียว เลือกให้อัตโนมัติ
        if (provinces.length == 1) {
          _selectedProvince = provinces.first;
          _loadDistricts();
        }
      });
    } catch (e) {
      setState(() {
        _postalCodeError = 'เกิดข้อผิดพลาด';
        _isLoadingProvinces = false;
      });
    }
  }

  /// โหลดอำเภอจากจังหวัดที่เลือก
  Future<void> _loadDistricts() async {
    if (_postalCode == null || _selectedProvince == null) return;
    setState(() {
      _selectedDistrict = null;
      _selectedSubDistrict = null;
      _districts = [];
      _subDistricts = [];
      _isLoadingDistricts = true;
    });

    try {
      final districts = await _repository.getDistrictsByPostalCodeAndProvince(
          _postalCode!, _selectedProvince!);
      setState(() {
        _districts = districts;
        _isLoadingDistricts = false;
        // ถ้ามีอำเภอเดียว เลือกให้อัตโนมัติ
        if (districts.length == 1) {
          _selectedDistrict = districts.first;
          _loadSubDistricts();
        }
      });
    } catch (e) {
      setState(() => _isLoadingDistricts = false);
    }
  }

  /// โหลดตำบลจากอำเภอที่เลือก
  Future<void> _loadSubDistricts() async {
    if (_postalCode == null || _selectedProvince == null || _selectedDistrict == null) return;
    setState(() {
      _selectedSubDistrict = null;
      _subDistricts = [];
      _isLoadingSubDistricts = true;
    });

    try {
      final subDistricts = await _repository
          .getSubDistrictsByPostalCodeProvinceAndDistrict(
              _postalCode!, _selectedProvince!, _selectedDistrict!);
      setState(() {
        _subDistricts = subDistricts;
        _isLoadingSubDistricts = false;
        // ถ้ามีตำบลเดียว เลือกให้อัตโนมัติ
        if (subDistricts.length == 1) {
          _selectedSubDistrict = subDistricts.first;
          _loadLeaderRole();
        }
      });
    } catch (e) {
      setState(() => _isLoadingSubDistricts = false);
    }
  }

  void _notifyAddress() {
    if (_postalCode != null &&
        _selectedProvince != null &&
        _selectedDistrict != null &&
        _selectedSubDistrict != null) {
      widget.onAddressSelected?.call(ThaiAddress(
        postalCode: _postalCode!,
        province: _selectedProvince!,
        district: _selectedDistrict!,
        subDistrict: _selectedSubDistrict!,
        localGovType: _leaderRole?.localGovType,
        leaderRole: _leaderRole,
      ));
    }
  }

  /// โหลดข้อมูลผู้นำชุมชนตามรูปแบบการปกครอง
  Future<void> _loadLeaderRole() async {
    if (_postalCode == null || _selectedProvince == null ||
        _selectedDistrict == null || _selectedSubDistrict == null) return;
    setState(() => _isLoadingLeaderRole = true);
    try {
      final role = await _repository.getLeaderRoleByAddress(
        postalCode: _postalCode!,
        province: _selectedProvince!,
        district: _selectedDistrict!,
        subDistrict: _selectedSubDistrict!,
      );
      setState(() {
        _leaderRole = role;
        _isLoadingLeaderRole = false;
      });
      _notifyAddress();
    } catch (e) {
      setState(() => _isLoadingLeaderRole = false);
      _notifyAddress();
    }
  }

  InputDecoration _buildFieldDecoration({required String hintText, required IconData icon}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: Colors.grey[400]),
      prefixIcon: Icon(icon, color: AppColors.primary.withOpacity(0.5), size: 22),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── รหัสไปรษณีย์ (เริ่มต้นที่นี่) ──
        TextFormField(
          controller: _postalCodeController,
          decoration: _buildFieldDecoration(
            hintText: 'รหัสไปรษณีย์ 5 หลัก',
            icon: Icons.local_post_office_rounded,
          ).copyWith(
            errorText: _postalCodeError,
            suffixIcon: _isLoadingProvinces
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : (_postalCode != null && _provinces.isNotEmpty)
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 22)
                    : null,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          style: AppTextStyles.bodyMedium.copyWith(fontSize: 18, letterSpacing: 4, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          onChanged: _onPostalCodeChanged,
          validator: (val) {
            if (val == null || val.length != 5) return 'กรุณากรอกรหัสไปรษณีย์ 5 หลัก';
            return null;
          },
        ),

        // ── แสดง Cascading Dropdowns เมื่อจังหวัดพร้อม ──
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 350),
          crossFadeState: _provinces.isEmpty
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              const SizedBox(height: 16),

              // ── จังหวัด ──
              DropdownButtonFormField<String>(
                decoration: _buildFieldDecoration(hintText: 'จังหวัด', icon: Icons.map_rounded),
                value: _selectedProvince,
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[500]),
                items: _provinces.map((p) => DropdownMenuItem(value: p, child: Text(p, style: AppTextStyles.bodyMedium))).toList(),
                onChanged: (val) {
                  setState(() => _selectedProvince = val);
                  _loadDistricts();
                },
                validator: (val) => val == null ? 'กรุณาเลือกจังหวัด' : null,
              ),

              // ── อำเภอ/เขต ──
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: _selectedProvince == null
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  children: [
                    const SizedBox(height: 16),
                    _isLoadingDistricts
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                          )
                        : DropdownButtonFormField<String>(
                            decoration: _buildFieldDecoration(hintText: 'อำเภอ/เขต', icon: Icons.location_city_rounded),
                            value: _selectedDistrict,
                            icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[500]),
                            items: _districts.map((d) => DropdownMenuItem(value: d, child: Text(d, style: AppTextStyles.bodyMedium))).toList(),
                            onChanged: (val) {
                              setState(() => _selectedDistrict = val);
                              _loadSubDistricts();
                            },
                            validator: (val) => val == null ? 'กรุณาเลือกอำเภอ/เขต' : null,
                          ),

                    // ── ตำบล/แขวง ──
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 300),
                      crossFadeState: _selectedDistrict == null
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: [
                          const SizedBox(height: 16),
                          _isLoadingSubDistricts
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                                )
                              : DropdownButtonFormField<String>(
                                  decoration: _buildFieldDecoration(hintText: 'ตำบล/แขวง', icon: Icons.holiday_village_rounded),
                                  value: _selectedSubDistrict,
                                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[500]),
                                  items: _subDistricts.map((s) => DropdownMenuItem(value: s, child: Text(s, style: AppTextStyles.bodyMedium))).toList(),
                                  onChanged: (val) {
                                    setState(() => _selectedSubDistrict = val);
                                    _loadLeaderRole();
                                  },
                                  validator: (val) => val == null ? 'กรุณาเลือกตำบล/แขวง' : null,
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── สรุปที่อยู่ที่เลือก ──
              if (_selectedSubDistrict != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'ต.$_selectedSubDistrict อ.$_selectedDistrict จ.$_selectedProvince $_postalCode',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // แสดงรูปแบบการปกครอง + ตำแหน่งผู้นำ
                      if (_isLoadingLeaderRole)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (_leaderRole != null) ...[
                        const Divider(height: 20),
                        Row(
                          children: [
                            Icon(Icons.account_balance_rounded, size: 16, color: Colors.deepPurple[400]),
                            const SizedBox(width: 8),
                            Text(
                              _leaderRole!.govTypeNameTh,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.deepPurple[600],
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.person_pin_rounded, size: 16, color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ผู้ยืนยันคำร้อง: ${_leaderRole!.leaderTitleTh}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.orange[800],
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
