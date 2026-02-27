import 'package:supabase_flutter/supabase_flutter.dart';

/// ข้อมูลตำแหน่งผู้นำชุมชนตามรูปแบบการปกครอง
class CommunityLeaderRole {
  final String localGovType;
  final String govTypeNameTh;
  final String? govTypeNameEn;
  final String leaderTitleTh;
  final String? leaderTitleEn;
  final bool hasVillageHead;
  final bool hasKamnan;

  const CommunityLeaderRole({
    required this.localGovType,
    required this.govTypeNameTh,
    this.govTypeNameEn,
    required this.leaderTitleTh,
    this.leaderTitleEn,
    this.hasVillageHead = false,
    this.hasKamnan = false,
  });

  factory CommunityLeaderRole.fromJson(Map<String, dynamic> json) {
    return CommunityLeaderRole(
      localGovType: json['local_gov_type'] ?? '',
      govTypeNameTh: json['gov_type_name_th'] ?? '',
      govTypeNameEn: json['gov_type_name_en'],
      leaderTitleTh: json['leader_title_th'] ?? '',
      leaderTitleEn: json['leader_title_en'],
      hasVillageHead: json['has_village_head'] ?? false,
      hasKamnan: json['has_kamnan'] ?? false,
    );
  }
}

/// Repository สำหรับ Query ข้อมูลที่อยู่ไทย (Cascading Address Picker)
class ThaiAddressRepository {
  final SupabaseClient _client;

  ThaiAddressRepository(this._client);

  /// ค้นหาจังหวัดจากรหัสไปรษณีย์
  Future<List<String>> getProvincesByPostalCode(String postalCode) async {
    final response = await _client
        .from('thai_addresses')
        .select('province')
        .eq('postal_code', postalCode);

    final provinces = (response as List)
        .map((r) => r['province'] as String)
        .toSet()
        .toList();
    provinces.sort();
    return provinces;
  }

  /// ค้นหาอำเภอ/เขต จากรหัสไปรษณีย์และจังหวัด
  Future<List<String>> getDistrictsByPostalCodeAndProvince(String postalCode, String province) async {
    final response = await _client
        .from('thai_addresses')
        .select('district')
        .eq('postal_code', postalCode)
        .eq('province', province);

    final districts = (response as List)
        .map((r) => r['district'] as String)
        .toSet()
        .toList();
    districts.sort();
    return districts;
  }

  /// ค้นหาตำบล/แขวง จากรหัสไปรษณีย์ จังหวัด และอำเภอ
  Future<List<String>> getSubDistrictsByPostalCodeProvinceAndDistrict(
      String postalCode, String province, String district) async {
    final response = await _client
        .from('thai_addresses')
        .select('sub_district')
        .eq('postal_code', postalCode)
        .eq('province', province)
        .eq('district', district);

    final subDistricts = (response as List)
        .map((r) => r['sub_district'] as String)
        .toSet()
        .toList();
    subDistricts.sort();
    return subDistricts;
  }

  /// ดึงประเภทการปกครองท้องถิ่นจากที่อยู่ที่ระบุ
  Future<String?> getLocalGovType({
    required String postalCode,
    required String province,
    required String district,
    required String subDistrict,
  }) async {
    final response = await _client
        .from('thai_addresses')
        .select('local_gov_type')
        .eq('postal_code', postalCode)
        .eq('province', province)
        .eq('district', district)
        .eq('sub_district', subDistrict)
        .limit(1);

    if ((response as List).isEmpty) return null;
    return response.first['local_gov_type'] as String?;
  }

  /// ดึงข้อมูลตำแหน่งผู้นำชุมชนจากประเภทการปกครอง
  Future<CommunityLeaderRole?> getLeaderRole(String localGovType) async {
    final response = await _client
        .from('community_leader_roles')
        .select()
        .eq('local_gov_type', localGovType)
        .limit(1);

    if ((response as List).isEmpty) return null;
    return CommunityLeaderRole.fromJson(response.first);
  }

  /// ดึงข้อมูลผู้นำชุมชนจากที่อยู่ (รวม 2 query ข้างบน)
  Future<CommunityLeaderRole?> getLeaderRoleByAddress({
    required String postalCode,
    required String province,
    required String district,
    required String subDistrict,
  }) async {
    final govType = await getLocalGovType(
      postalCode: postalCode,
      province: province,
      district: district,
      subDistrict: subDistrict,
    );
    if (govType == null) return null;
    return getLeaderRole(govType);
  }

  /// ตรวจสอบว่ารหัสไปรษณีย์มีอยู่จริงหรือไม่
  Future<bool> isValidPostalCode(String postalCode) async {
    final response = await _client
        .from('thai_addresses')
        .select('id')
        .eq('postal_code', postalCode)
        .limit(1);

    return (response as List).isNotEmpty;
  }
}
