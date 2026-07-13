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
}
