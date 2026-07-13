import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service สำหรับตรวจสอบสิทธิ์เข้าถึง ERP Dashboard
///
/// ใช้ employee_roles เป็น source of truth สำหรับการเข้าถึง ERP
/// ไม่ใช้ isConsultationProvider เนื่องจากเป็นความสามารถด้านการปรึกษา
/// ไม่ใช่สิทธิ์การเข้าถึง ERP
class ErpAccessService {
  final SupabaseClient _client;

  ErpAccessService(this._client);

  /// ตรวจสอบว่า user มีสิทธิ์เข้าถึง ERP Dashboard หรือไม่
  ///
  /// Admin มีสิทธิ์เข้าถึง ERP เสมอ (global admin mode)
  /// Non-admin ต้องมี active employee_roles ใน profession นั้น
  Future<bool> canAccess({
    required String userId,
    required String? professionId,
    bool isAdmin = false,
  }) async {
    if (isAdmin) return true;
    if (professionId == null || professionId.isEmpty) return false;

    try {
      final rows = await _client
          .from('employee_roles')
          .select('id, organization_roles!inner(id)')
          .eq('user_id', userId)
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .limit(1);
      return rows is List && rows.isNotEmpty;
    } catch (error, stackTrace) {
      debugPrint('[ERPAccess] access check failed: $error');
      debugPrint('[ERPAccess] stackTrace: $stackTrace');
      return false;
    }
  }

  /// ตรวจสอบว่า user มี active employee_roles ใน profession ใดๆ หรือไม่
  /// ใช้สำหรับ Home Page ที่ต้องแสดง ERP card แม้ user.professionId ไม่ตรงกับ profession ที่ถูกเชิญ
  Future<bool> canAccessAnyProfession(String userId) async {
    try {
      final rows = await _client
          .from('employee_roles')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .limit(1);
      return rows is List && rows.isNotEmpty;
    } catch (error, stackTrace) {
      debugPrint('[ERPAccess] any profession access check failed: $error');
      debugPrint('[ERPAccess] stackTrace: $stackTrace');
      return false;
    }
  }

  /// ดึง profession_id แรกที่ user มี active employee_roles
  /// ใช้เมื่อ user.professionId ไม่ตรงกับ profession ที่ถูกเชิญ (เช่น invitee ที่เพิ่ง accept)
  Future<String?> getActiveProfessionId(String userId) async {
    try {
      final rows = await _client
          .from('employee_roles')
          .select('profession_id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .limit(1);
      if (rows is List && rows.isNotEmpty) {
        return rows[0]['profession_id'] as String?;
      }
      return null;
    } catch (error, stackTrace) {
      debugPrint('[ERPAccess] getActiveProfessionId failed: $error');
      debugPrint('[ERPAccess] stackTrace: $stackTrace');
      return null;
    }
  }
}
