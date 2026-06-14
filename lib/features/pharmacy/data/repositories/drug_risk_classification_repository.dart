import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/drug_risk_classification_models.dart';

class DrugRiskClassificationRepository {
  final SupabaseClient _client;

  DrugRiskClassificationRepository(this._client);

  // ════════════════════════════════════════════════
  // Helper: Audit Log
  // ════════════════════════════════════════════════

  Future<void> _logAdminAction({
    required String tableName,
    required String recordId,
    required String action,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    String? performedBy,
  }) async {
    try {
      await _client.from('drug_risk_admin_logs').insert({
        'table_name': tableName,
        'record_id': recordId,
        'action': action,
        'old_data': oldData,
        'new_data': newData,
        'performed_by': performedBy,
      });
    } catch (e) {
      debugPrint('Error writing audit log: $e');
    }
  }

  // ════════════════════════════════════════════════
  // Dangerous Drug Subcategories
  // ════════════════════════════════════════════════

  Future<List<DangerousDrugSubcategory>> getAllSubcategories({bool includeDeleted = false}) async {
    try {
      final response = await _client
          .from('dangerous_drug_subcategories')
          .select()
          .order('sort_order', ascending: true);

      var list = (response as List)
          .map((json) => DangerousDrugSubcategory.fromJson(json))
          .toList();

      if (!includeDeleted) {
        list = list.where((item) => item.deletedAt == null).toList();
      }

      return list;
    } catch (e) {
      debugPrint('Error fetching subcategories: $e');
      throw Exception('ไม่สามารถดึงข้อมูลหมวดหมู่ยาอันตรายย่อยได้: $e');
    }
  }

  Future<DangerousDrugSubcategory> createSubcategory({
    required String code,
    required String nameTh,
    String? nameEn,
    String? description,
    bool isTelemedicineProhibited = false,
    int sortOrder = 0,
    String? performedBy,
  }) async {
    try {
      final response = await _client
          .from('dangerous_drug_subcategories')
          .insert({
            'code': code,
            'name_th': nameTh,
            'name_en': nameEn,
            'description': description,
            'is_telemedicine_prohibited': isTelemedicineProhibited,
            'sort_order': sortOrder,
          })
          .select()
          .single();

      final result = DangerousDrugSubcategory.fromJson(response);

      await _logAdminAction(
        tableName: 'dangerous_drug_subcategories',
        recordId: result.id,
        action: 'create',
        newData: result.toJson(),
        performedBy: performedBy,
      );

      return result;
    } catch (e) {
      debugPrint('Error creating subcategory: $e');
      throw Exception('ไม่สามารถสร้างหมวดหมู่ยาอันตรายย่อยได้: $e');
    }
  }

  Future<DangerousDrugSubcategory> updateSubcategory(
    String id, {
    String? code,
    String? nameTh,
    String? nameEn,
    String? description,
    bool? isTelemedicineProhibited,
    int? sortOrder,
    bool? isActive,
    String? performedBy,
  }) async {
    try {
      final old = await _client
          .from('dangerous_drug_subcategories')
          .select()
          .eq('id', id)
          .single();

      final data = <String, dynamic>{};
      if (code != null) data['code'] = code;
      if (nameTh != null) data['name_th'] = nameTh;
      if (nameEn != null) data['name_en'] = nameEn;
      if (description != null) data['description'] = description;
      if (isTelemedicineProhibited != null) {
        data['is_telemedicine_prohibited'] = isTelemedicineProhibited;
      }
      if (sortOrder != null) data['sort_order'] = sortOrder;
      if (isActive != null) data['is_active'] = isActive;

      final response = await _client
          .from('dangerous_drug_subcategories')
          .update(data)
          .eq('id', id)
          .select()
          .single();

      final result = DangerousDrugSubcategory.fromJson(response);

      await _logAdminAction(
        tableName: 'dangerous_drug_subcategories',
        recordId: id,
        action: 'update',
        oldData: old,
        newData: result.toJson(),
        performedBy: performedBy,
      );

      return result;
    } catch (e) {
      debugPrint('Error updating subcategory: $e');
      throw Exception('ไม่สามารถอัปเดตหมวดหมู่ยาอันตรายย่อยได้: $e');
    }
  }

  Future<void> softDeleteSubcategory(String id, {String? performedBy}) async {
    try {
      final old = await _client
          .from('dangerous_drug_subcategories')
          .select()
          .eq('id', id)
          .single();

      await _client
          .from('dangerous_drug_subcategories')
          .update({'deleted_at': DateTime.now().toIso8601String(), 'is_active': false})
          .eq('id', id);

      await _logAdminAction(
        tableName: 'dangerous_drug_subcategories',
        recordId: id,
        action: 'soft_delete',
        oldData: old,
        performedBy: performedBy,
      );
    } catch (e) {
      debugPrint('Error soft-deleting subcategory: $e');
      throw Exception('ไม่สามารถลบหมวดหมู่ยาอันตรายย่อยได้: $e');
    }
  }

  Future<void> reactivateSubcategory(String id, {String? performedBy}) async {
    try {
      final old = await _client
          .from('dangerous_drug_subcategories')
          .select()
          .eq('id', id)
          .single();

      await _client
          .from('dangerous_drug_subcategories')
          .update({'deleted_at': null, 'is_active': true})
          .eq('id', id);

      await _logAdminAction(
        tableName: 'dangerous_drug_subcategories',
        recordId: id,
        action: 'reactivate',
        oldData: old,
        performedBy: performedBy,
      );
    } catch (e) {
      debugPrint('Error reactivating subcategory: $e');
      throw Exception('ไม่สามารถคืนค่าหมวดหมู่ยาอันตรายย่อยได้: $e');
    }
  }

  Future<List<String>> resetSubcategorySeed({String? performedBy}) async {
    final inserted = <String>[];
    final seeds = [
      {'code': 'hormone_injection', 'name_th': 'ฮอร์โมนฉีด', 'name_en': 'Hormone Injection', 'is_telemedicine_prohibited': true, 'sort_order': 1},
      {'code': 'chemotherapy', 'name_th': 'ยาเคมีบำบัด', 'name_en': 'Chemotherapy', 'is_telemedicine_prohibited': true, 'sort_order': 2},
      {'code': 'abortifacient', 'name_th': 'ยาขับเลือด/ยาทำแท้ง', 'name_en': 'Abortifacient', 'is_telemedicine_prohibited': true, 'sort_order': 3},
      {'code': 'antibiotic_injection', 'name_th': 'ยาปฏิชีวนะฉีด', 'name_en': 'Antibiotic Injection', 'is_telemedicine_prohibited': false, 'sort_order': 4},
      {'code': 'contrast_media', 'name_th': 'สารทึบรังสี', 'name_en': 'Contrast Media', 'is_telemedicine_prohibited': false, 'sort_order': 5},
    ];

    for (final seed in seeds) {
      try {
        final response = await _client
            .from('dangerous_drug_subcategories')
            .upsert(seed, onConflict: 'code')
            .select()
            .single();
        inserted.add(response['code'] as String);
      } catch (e) {
        debugPrint('Error upserting seed ${seed['code']}: $e');
      }
    }

    await _logAdminAction(
      tableName: 'dangerous_drug_subcategories',
      recordId: 'ALL',
      action: 'reset_seed',
      performedBy: performedBy,
    );

    return inserted;
  }

  // ════════════════════════════════════════════════
  // Custom Risk Levels
  // ════════════════════════════════════════════════

  Future<List<CustomRiskLevel>> getAllRiskLevels({bool includeDeleted = false}) async {
    try {
      final response = await _client
          .from('custom_risk_levels')
          .select()
          .order('sort_order', ascending: true);

      var list = (response as List)
          .map((json) => CustomRiskLevel.fromJson(json))
          .toList();

      if (!includeDeleted) {
        list = list.where((item) => item.deletedAt == null).toList();
      }

      return list;
    } catch (e) {
      debugPrint('Error fetching risk levels: $e');
      throw Exception('ไม่สามารถดึงข้อมูลระดับความเสี่ยงได้: $e');
    }
  }

  Future<CustomRiskLevel> createRiskLevel({
    required String code,
    required String nameTh,
    String? nameEn,
    String? description,
    bool isTelemedicineProhibited = false,
    int sortOrder = 0,
    String? performedBy,
  }) async {
    try {
      final response = await _client
          .from('custom_risk_levels')
          .insert({
            'code': code,
            'name_th': nameTh,
            'name_en': nameEn,
            'description': description,
            'is_telemedicine_prohibited': isTelemedicineProhibited,
            'sort_order': sortOrder,
          })
          .select()
          .single();

      final result = CustomRiskLevel.fromJson(response);

      await _logAdminAction(
        tableName: 'custom_risk_levels',
        recordId: result.id,
        action: 'create',
        newData: result.toJson(),
        performedBy: performedBy,
      );

      return result;
    } catch (e) {
      debugPrint('Error creating risk level: $e');
      throw Exception('ไม่สามารถสร้างระดับความเสี่ยงได้: $e');
    }
  }

  Future<CustomRiskLevel> updateRiskLevel(
    String id, {
    String? code,
    String? nameTh,
    String? nameEn,
    String? description,
    bool? isTelemedicineProhibited,
    int? sortOrder,
    bool? isActive,
    String? performedBy,
  }) async {
    try {
      final old = await _client
          .from('custom_risk_levels')
          .select()
          .eq('id', id)
          .single();

      final data = <String, dynamic>{};
      if (code != null) data['code'] = code;
      if (nameTh != null) data['name_th'] = nameTh;
      if (nameEn != null) data['name_en'] = nameEn;
      if (description != null) data['description'] = description;
      if (isTelemedicineProhibited != null) {
        data['is_telemedicine_prohibited'] = isTelemedicineProhibited;
      }
      if (sortOrder != null) data['sort_order'] = sortOrder;
      if (isActive != null) data['is_active'] = isActive;

      final response = await _client
          .from('custom_risk_levels')
          .update(data)
          .eq('id', id)
          .select()
          .single();

      final result = CustomRiskLevel.fromJson(response);

      await _logAdminAction(
        tableName: 'custom_risk_levels',
        recordId: id,
        action: 'update',
        oldData: old,
        newData: result.toJson(),
        performedBy: performedBy,
      );

      return result;
    } catch (e) {
      debugPrint('Error updating risk level: $e');
      throw Exception('ไม่สามารถอัปเดตระดับความเสี่ยงได้: $e');
    }
  }

  Future<void> softDeleteRiskLevel(String id, {String? performedBy}) async {
    try {
      final old = await _client
          .from('custom_risk_levels')
          .select()
          .eq('id', id)
          .single();

      await _client
          .from('custom_risk_levels')
          .update({'deleted_at': DateTime.now().toIso8601String(), 'is_active': false})
          .eq('id', id);

      await _logAdminAction(
        tableName: 'custom_risk_levels',
        recordId: id,
        action: 'soft_delete',
        oldData: old,
        performedBy: performedBy,
      );
    } catch (e) {
      debugPrint('Error soft-deleting risk level: $e');
      throw Exception('ไม่สามารถลบระดับความเสี่ยงได้: $e');
    }
  }

  Future<void> reactivateRiskLevel(String id, {String? performedBy}) async {
    try {
      final old = await _client
          .from('custom_risk_levels')
          .select()
          .eq('id', id)
          .single();

      await _client
          .from('custom_risk_levels')
          .update({'deleted_at': null, 'is_active': true})
          .eq('id', id);

      await _logAdminAction(
        tableName: 'custom_risk_levels',
        recordId: id,
        action: 'reactivate',
        oldData: old,
        performedBy: performedBy,
      );
    } catch (e) {
      debugPrint('Error reactivating risk level: $e');
      throw Exception('ไม่สามารถคืนค่าระดับความเสี่ยงได้: $e');
    }
  }

  Future<List<String>> resetRiskLevelSeed({String? performedBy}) async {
    final inserted = <String>[];
    final seeds = [
      {'code': 'low', 'name_th': 'ความเสี่ยงต่ำ', 'name_en': 'Low Risk', 'is_telemedicine_prohibited': false, 'sort_order': 1},
      {'code': 'medium', 'name_th': 'ความเสี่ยงปานกลาง', 'name_en': 'Medium Risk', 'is_telemedicine_prohibited': false, 'sort_order': 2},
      {'code': 'high', 'name_th': 'ความเสี่ยงสูง', 'name_en': 'High Risk', 'is_telemedicine_prohibited': true, 'sort_order': 3},
      {'code': 'very_high', 'name_th': 'ความเสี่ยงสูงมาก', 'name_en': 'Very High Risk', 'is_telemedicine_prohibited': true, 'sort_order': 4},
      {'code': 'prohibited', 'name_th': 'ห้ามใช้', 'name_en': 'Prohibited', 'is_telemedicine_prohibited': true, 'sort_order': 5},
    ];

    for (final seed in seeds) {
      try {
        final response = await _client
            .from('custom_risk_levels')
            .upsert(seed, onConflict: 'code')
            .select()
            .single();
        inserted.add(response['code'] as String);
      } catch (e) {
        debugPrint('Error upserting seed ${seed['code']}: $e');
      }
    }

    await _logAdminAction(
      tableName: 'custom_risk_levels',
      recordId: 'ALL',
      action: 'reset_seed',
      performedBy: performedBy,
    );

    return inserted;
  }

  // ════════════════════════════════════════════════
  // Admin Logs
  // ════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAdminLogs({
    String? tableName,
    int limit = 50,
  }) async {
    try {
      var query = _client.from('drug_risk_admin_logs').select();

      if (tableName != null) {
        query = query.eq('table_name', tableName);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error fetching admin logs: $e');
      return [];
    }
  }

  // ════════════════════════════════════════════════
  // Medication Override (Tab 3)
  // ════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> searchMedications(String query) async {
    try {
      final response = await _client
          .from('medications')
          .select('id, trade_name, generic_name, fda_risk_status, dangerous_sub_category')
          .or('trade_name.ilike.%$query%,generic_name.ilike.%$query%')
          .limit(50);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error searching medications: $e');
      return [];
    }
  }

  Future<void> updateMedicationClassification({
    required String medicationId,
    String? fdaRiskStatus,
    String? dangerousSubCategory,
    required String reason,
    required String overriddenBy,
  }) async {
    try {
      // 1. ดึงค่าเดิม
      final old = await _client
          .from('medications')
          .select('fda_risk_status, dangerous_sub_category')
          .eq('id', medicationId)
          .single();

      // 2. บันทึก audit log
      await _client.from('medication_risk_override_logs').insert({
        'medication_id': medicationId,
        'old_fda_risk_status': old['fda_risk_status'],
        'new_fda_risk_status': fdaRiskStatus,
        'old_sub_category': old['dangerous_sub_category'],
        'new_sub_category': dangerousSubCategory,
        'reason': reason,
        'overridden_by': overriddenBy,
      });

      // 3. อัปเดต medications
      final updateData = <String, dynamic>{};
      if (fdaRiskStatus != null) updateData['fda_risk_status'] = fdaRiskStatus;
      if (dangerousSubCategory != null) {
        updateData['dangerous_sub_category'] = dangerousSubCategory;
      }

      if (updateData.isNotEmpty) {
        await _client
            .from('medications')
            .update(updateData)
            .eq('id', medicationId);
      }
    } catch (e) {
      debugPrint('Error overriding medication: $e');
      throw Exception('ไม่สามารถ Override การจำแนกยาได้: $e');
    }
  }

  // ─────────────────────────────────────────────
  // Reports & Audit (Tab 4)
  // ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getBlockedPrescriptionsMonthly() async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);

      final response = await _client
          .from('prescriptions')
          .select('status, pharmacy_status, medications')
          .gte('issued_at', startOfMonth.toIso8601String())
          .eq('source_type', 'telemedicine');

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error fetching blocked prescriptions: $e');
      return [];
    }
  }

  Future<int> getCustomMedicationsWithoutRiskLevel() async {
    try {
      final response = await _client
          .from('custom_medications')
          .select()
          .isFilter('custom_risk_level', null)
          .count(CountOption.exact);

      return response.count ?? 0;
    } catch (e) {
      debugPrint('Error counting custom meds without risk: $e');
      return 0;
    }
  }

  Future<List<MedicationRiskOverrideLog>> getRecentOverrides({int limit = 20}) async {
    try {
      final response = await _client
          .from('medication_risk_override_logs')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((json) => MedicationRiskOverrideLog.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching override logs: $e');
      return [];
    }
  }
}
