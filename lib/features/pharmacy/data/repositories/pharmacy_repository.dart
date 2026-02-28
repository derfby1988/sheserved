import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/medication_models.dart';

class PharmacyRepository {
  final SupabaseClient _client;

  PharmacyRepository(this._client);

  /// ดึงข้อมูลยาและเวชภัณฑ์ทั้งหมด รองรับ Pagination
  /// เป็นไปตาม Auth Guidelines: รับ userId เข้ามาเป็น parameter
  Future<List<MedicationModel>> getMedications({
    String? userId,
    int page = 1,
    int pageSize = 20,
    String? searchQuery,
  }) async {
    try {
      final startIndex = (page - 1) * pageSize;
      final endIndex = startIndex + pageSize - 1;

      // เริ่มสร้าง Query สำหรับดึงข้อมูลยา พร้อมดึงรายละเอียดจากตารางอื่นๆ มาด้วย
      // ใช้ inner join แบบมีเงื่อนไข (Foreign Key) 
      var query = _client.from('medications').select('''
        *,
        tmt_details:tmt_details(*),
        unregistered_details:unregistered_details(*)
      ''').eq('status', 'ACTIVE');

      // ถ้ามีการค้นหา
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('trade_name.ilike.%$searchQuery%,generic_name.ilike.%$searchQuery%');
      }

      // เรียงลำดับและแบ่งหน้า
      final response = await query
          .order('trade_name', ascending: true)
          .range(startIndex, endIndex);

      return (response as List).map((json) => MedicationModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching medications: $e');
      throw Exception('ไม่สามารถดึงข้อมูลยาได้: $e');
    }
  }

  /// ดึงรายละเอียดเจาะจงของยาพร้อมข้อมูลเชิงลึก
  Future<MedicationModel?> getMedicationDetails({
    required String medicationId,
    String? userId, // userId สำรองไว้ใช้ตรวจสอบกรณีบันทึกประวัติการเข้าดู
  }) async {
    try {
      final response = await _client.from('medications').select('''
        *,
        tmt_details(*),
        unregistered_details(*)
      ''').eq('id', medicationId).maybeSingle();

      if (response == null) return null;

      // ดึงข้อมูล clinical_knowledge เพิ่มเติมโดยใช้ generic_name อ้างอิง
      final genericName = response['generic_name'];
      if (genericName != null && genericName.toString().isNotEmpty) {
        final ckResponse = await _client.from('clinical_knowledge')
            .select()
            .eq('generic_name', genericName)
            .limit(1)
            .maybeSingle();
        
        if (ckResponse != null) {
          response['clinical_knowledge'] = [ckResponse];
        }
      }

      return MedicationModel.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching medication details: $e');
      throw Exception('ไม่สามารถดึงรายละเอียดข้อมูลยาได้: $e');
    }
  }
}
