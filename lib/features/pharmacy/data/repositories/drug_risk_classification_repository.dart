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
          .select()
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
          .select()
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

      return response.count;
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

  // ════════════════════════════════════════════════
  // Drug Risk Overrides (Org + Personal scope — v3.0)
  // ════════════════════════════════════════════════

  /// Upsert Override (ใช้ได้ทั้ง personal และ org scope)
  /// บันทึก History + Name Snapshot อัตโนมัติ
  Future<DrugRiskOverride> setOverride({
    String? userId,          // Personal scope
    String? professionId,    // Organization scope
    required String medicationId,
    String? overrideFdaRiskStatus,
    String? overrideSubCategory,
    String? overrideCustomRiskCode,
    bool? overrideIsTelemedicineProhibited,
    String? overrideNotes,
    required String performedBy,
    required String performedByName, // ชื่อจริงสำหรับ snapshot
    String? changeReason,
  }) async {
    assert(userId != null || professionId != null,
        'ต้องระบุ userId หรือ professionId');

    // กฎเหล็ก: N/P ห้าม override เป็น telemedicine allowed
    if (overrideIsTelemedicineProhibited == false &&
        (overrideFdaRiskStatus == 'N' || overrideFdaRiskStatus == 'P')) {
      throw Exception(
          'ไม่สามารถอนุญาต Telemedicine สำหรับยาประเภท N หรือ P ได้ (บังคับตามกฎหมาย)');
    }

    try {
      // 1. ดึงค่าเดิม (เพื่อ snapshot ใน History)
      final existing = await getOverride(
        userId: userId,
        professionId: professionId,
        medicationId: medicationId,
      );

      // 2. Insert or Update Active Override
      //    (Can't use upsert with onConflict because the unique indexes are partial)
      final data = <String, dynamic>{
        if (userId != null) 'user_id': userId,
        if (professionId != null) 'profession_id': professionId,
        'medication_id': medicationId,
        'override_fda_risk_status': overrideFdaRiskStatus,
        'override_sub_category': overrideSubCategory,
        'override_custom_risk_code': overrideCustomRiskCode,
        'override_is_telemedicine_prohibited': overrideIsTelemedicineProhibited,
        'override_notes': overrideNotes,
        'last_modified_by': performedBy,
        'last_modified_at': DateTime.now().toIso8601String(),
      };

      late final Map<String, dynamic> response;

      if (existing != null) {
        // Update existing override
        final updated = await _client
            .from('drug_risk_overrides')
            .update(data)
            .eq('id', existing.id)
            .select()
            .single();
        response = updated;
      } else {
        // Insert new override
        data['created_by'] = performedBy;
        final inserted = await _client
            .from('drug_risk_overrides')
            .insert(data)
            .select()
            .single();
        response = inserted;
      }

      final result = DrugRiskOverride.fromJson(response);

      // 3. บันทึก History (ทั้ง org และ personal scope)
      await _insertOverrideHistory(
        overrideId: result.id,
        professionId: professionId,
        userId: userId,
        medicationId: medicationId,
        existing: existing,
        overrideFdaRiskStatus: overrideFdaRiskStatus,
        overrideSubCategory: overrideSubCategory,
        overrideCustomRiskCode: overrideCustomRiskCode,
        overrideIsTelemedicineProhibited: overrideIsTelemedicineProhibited,
        overrideNotes: overrideNotes,
        action: existing == null ? 'create' : 'update',
        changedBy: performedBy,
        changedByName: performedByName,
        changeReason: changeReason,
      );

      // 4. Admin audit log
      await _logAdminAction(
        tableName: 'drug_risk_overrides',
        recordId: result.id,
        action: existing == null ? 'create' : 'update',
        oldData: existing?.toJson(),
        newData: result.toJson(),
        performedBy: performedBy,
      );

      return result;
    } catch (e) {
      debugPrint('Error setting override: $e');
      rethrow;
    }
  }

  /// ลบ Override → คืนค่า tier ที่ต่ำกว่า
  Future<void> removeOverride({
    String? userId,
    String? professionId,
    required String medicationId,
    required String performedBy,
    required String performedByName,
    String? changeReason,
  }) async {
    assert(userId != null || professionId != null);

    try {
      final existing = await getOverride(
        userId: userId,
        professionId: professionId,
        medicationId: medicationId,
      );
      if (existing == null) return;

      // บันทึก History ก่อน delete
      await _insertOverrideHistory(
        overrideId: existing.id,
        professionId: professionId,
        userId: userId,
        medicationId: medicationId,
        existing: existing,
        action: 'delete',
        changedBy: performedBy,
        changedByName: performedByName,
        changeReason: changeReason,
      );

      // ลบ record
      var query = _client.from('drug_risk_overrides').delete();
      if (userId != null) {
        query = query.eq('user_id', userId);
      }
      if (professionId != null) {
        query = query.eq('profession_id', professionId);
      }
      await query.eq('medication_id', medicationId);

      await _logAdminAction(
        tableName: 'drug_risk_overrides',
        recordId: existing.id,
        action: 'delete',
        oldData: existing.toJson(),
        performedBy: performedBy,
      );
    } catch (e) {
      debugPrint('Error removing override: $e');
      rethrow;
    }
  }

  /// ดึง Active Override ที่ตรงกับ scope (nullable ถ้าไม่มี)
  Future<DrugRiskOverride?> getOverride({
    String? userId,
    String? professionId,
    required String medicationId,
  }) async {
    try {
      var query = _client
          .from('drug_risk_overrides')
          .select()
          .eq('medication_id', medicationId);

      if (userId != null) {
        query = query.eq('user_id', userId);
      } else if (professionId != null) {
        query = query.eq('profession_id', professionId);
      } else {
        return null;
      }

      final response = await query.maybeSingle();
      if (response == null) return null;
      return DrugRiskOverride.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching override: $e');
      return null;
    }
  }

  /// ดึง History ของ Override (รองรับทั้ง org และ personal)
  Future<List<DrugRiskOverrideHistory>> getOverrideHistory({
    String? professionId,
    String? userId,
    String? medicationId,
    int limit = 20,
  }) async {
    try {
      var query = _client
          .from('drug_risk_override_history')
          .select();

      if (professionId != null) {
        query = query.eq('profession_id', professionId);
      }
      if (userId != null) {
        query = query.eq('user_id', userId);
      }
      if (medicationId != null) {
        query = query.eq('medication_id', medicationId);
      }

      final response = await query
          .order('changed_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((json) => DrugRiskOverrideHistory.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching override history: $e');
      return [];
    }
  }

  /// RPC: ดึงผู้รับผิดชอบที่ยังมีตัวตนและสิทธิ์ (Single DB call — ไม่มี N+1)
  Future<EffectiveModifierInfo> resolveEffectiveModifier({
    required String medicationId,
    String? professionId,
    String? userId,
  }) async {
    try {
      final result = await _client.rpc('resolve_effective_modifier', params: {
        'p_medication_id': medicationId,
        'p_profession_id': professionId,
        'p_user_id': userId,
      });
      return EffectiveModifierInfo.fromJson(
          Map<String, dynamic>.from(result as Map));
    } catch (e) {
      debugPrint('Error resolving effective modifier: $e');
      return const EffectiveModifierInfo(
        name: 'System Admin',
        status: 'fallback_system',
      );
    }
  }

  /// Merge ทุก Tier → effective risk สำหรับผู้ใช้คนนี้
  Future<Map<String, dynamic>> getMedicationRiskEffective({
    required String medicationId,
    String? currentUserId,
    String? professionId,
  }) async {
    try {
      // Tier 1+2: ค่ากลาง
      final base = await _client
          .from('medications')
          .select()
          .eq('id', medicationId)
          .single();

      Map<String, dynamic> result = {
        ...base,
        'has_override': false,
        'override_scope': null,
      };

      // Tier 3a: Organization Override
      if (professionId != null) {
        final orgOverride = await getOverride(
            professionId: professionId, medicationId: medicationId);
        if (orgOverride != null && orgOverride.hasAnyOverride) {
          result = _mergeOverride(result, orgOverride, 'organization');
        }
      }

      // Tier 3b: Personal Override (ชนะ Org)
      if (currentUserId != null) {
        final personalOverride = await getOverride(
            userId: currentUserId, medicationId: medicationId);
        if (personalOverride != null && personalOverride.hasAnyOverride) {
          result = _mergeOverride(result, personalOverride, 'personal');
        }
      }

      return result;
    } catch (e) {
      debugPrint('Error getting effective risk: $e');
      rethrow;
    }
  }

  // ─── Private Helpers ─────────────────────────────

  Map<String, dynamic> _mergeOverride(
    Map<String, dynamic> base,
    DrugRiskOverride override,
    String scope,
  ) {
    return {
      ...base,
      if (override.overrideFdaRiskStatus != null)
        'fda_risk_status': override.overrideFdaRiskStatus,
      if (override.overrideSubCategory != null)
        'dangerous_sub_category': override.overrideSubCategory,
      if (override.overrideIsTelemedicineProhibited != null)
        'is_telemedicine_prohibited': override.overrideIsTelemedicineProhibited,
      'has_override': true,
      'override_scope': scope,
      'override_notes': override.overrideNotes,
      'override_last_modified_by': override.lastModifiedBy,
      'override_last_modified_at': override.lastModifiedAt.toIso8601String(),
    };
  }

  Future<void> _insertOverrideHistory({
    required String overrideId,
    String? professionId,
    String? userId,
    required String medicationId,
    DrugRiskOverride? existing,
    String? overrideFdaRiskStatus,
    String? overrideSubCategory,
    String? overrideCustomRiskCode,
    bool? overrideIsTelemedicineProhibited,
    String? overrideNotes,
    required String action,
    required String changedBy,
    required String changedByName,
    String? changeReason,
  }) async {
    try {
      await _client.from('drug_risk_override_history').insert({
        'override_id': overrideId,
        if (professionId != null) 'profession_id': professionId,
        if (userId != null) 'user_id': userId,
        'medication_id': medicationId,
        'fda_risk_status_before': existing?.overrideFdaRiskStatus,
        'fda_risk_status_after': action == 'delete' ? null : overrideFdaRiskStatus,
        'sub_category_before': existing?.overrideSubCategory,
        'sub_category_after': action == 'delete' ? null : overrideSubCategory,
        'custom_risk_code_before': existing?.overrideCustomRiskCode,
        'custom_risk_code_after': action == 'delete' ? null : overrideCustomRiskCode,
        'is_telemedicine_prohibited_before':
            existing?.overrideIsTelemedicineProhibited,
        'is_telemedicine_prohibited_after':
            action == 'delete' ? null : overrideIsTelemedicineProhibited,
        'notes_before': existing?.overrideNotes,
        'notes_after': action == 'delete' ? null : overrideNotes,
        'action': action,
        'changed_by': changedBy,
        'changed_by_name': changedByName,
        'change_reason': changeReason,
      });
    } catch (e) {
      debugPrint('Error inserting override history: $e');
    }
  }
}
