import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/profession.dart';
import '../../models/registration_field_config.dart';
import '../repositories/registration_repository.dart';

/// Repository สำหรับจัดการอาชีพ
class ProfessionRepository {
  final SupabaseClient _client;

  ProfessionRepository(this._client);

  // =====================================================
  // USER CATEGORY CRUD
  // =====================================================

  /// ดึงรายการหมวดหมู่ผู้ใช้ทั้งหมด
  Future<List<UserCategory>> getAllUserCategories() async {
    try {
      final response = await _client
          .from('user_categories')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true)
          .order('name', ascending: true);
      
      return (response as List).map((e) => UserCategory.fromJson(e)).toList();
    } catch (e) {
      debugPrint('ProfessionRepository.getAllUserCategories error: $e');
      // Fallback
      return [
        const UserCategory(id: 'consumer', name: 'ผู้ซื้อ/ผู้รับบริการ'),
        const UserCategory(id: 'provider', name: 'ผู้ให้บริการ'),
      ];
    }
  }

  /// สร้างหมวดหมู่ผู้ใช้ใหม่
  Future<UserCategory> createUserCategory(Map<String, dynamic> data) async {
    data['created_at'] = DateTime.now().toIso8601String();
    data['updated_at'] = DateTime.now().toIso8601String();
    final response = await _client
        .from('user_categories')
        .insert(data)
        .select()
        .single();
    return UserCategory.fromJson(response);
  }

  /// อัปเดตหมวดหมู่ผู้ใช้
  Future<UserCategory> updateUserCategory(String id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    final response = await _client
        .from('user_categories')
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return UserCategory.fromJson(response);
  }

  /// ลบหมวดหมู่ผู้ใช้ (Soft Delete)
  Future<void> deleteUserCategory(String id) async {
    // ป้องกันการลบหมวดพื้นฐาน
    if (id == UserCategory.consumerId || id == UserCategory.providerId) {
      throw Exception('ไม่สามารถลบหมวดหมู่พื้นฐานได้');
    }
    
    await _client
        .from('user_categories')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  /// บันทึกลำดับการแสดงผลใหม่ (Bulk Update)
  Future<void> reorderUserCategories(List<UserCategory> categories) async {
    final now = DateTime.now().toIso8601String();
    final data = <Map<String, dynamic>>[];
    
    for (int i = 0; i < categories.length; i++) {
      data.add({
        'id': categories[i].id,
        'name': categories[i].name, // เพิ่มฟิลด์นี้เพื่อไม่ให้ติด Not-Null Constraint
        'display_order': i,
        'updated_at': now,
      });
    }

    // ใช้ upsert เพื่ออัปเดตข้อมูลหลายบรรทัดในคำสั่งเดียว
    await _client.from('user_categories').upsert(data);
  }


  // =====================================================
  // PROFESSION CRUD
  // =====================================================

  /// ดึงรายการอาชีพทั้งหมด
  Future<List<Profession>> getAllProfessions({bool activeOnly = true}) async {
    try {
      var query = _client.from('professions').select('''
        *,
        category_data:user_categories!professions_category_fkey(*),
        field_count:registration_field_configs(count),
        member_count:users(count)
      ''');

      if (activeOnly) {
        query = query.eq('is_active', true);
      }
      
      final response = await query
          .order('display_order', ascending: true)
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 10));

      return (response as List).map((json) {
        // Handle field_count
        if (json['field_count'] is List && (json['field_count'] as List).isNotEmpty) {
          json['field_count'] = (json['field_count'] as List).first['count'] ?? 0;
        } else {
          json['field_count'] = 0;
        }
        
        // Handle member_count
        if (json['member_count'] is List && (json['member_count'] as List).isNotEmpty) {
          json['member_count'] = (json['member_count'] as List).first['count'] ?? 0;
        } else {
          json['member_count'] = 0;
        }

        return Profession.fromJson(json);
      }).toList();
    } catch (e) {
      debugPrint('ProfessionRepository.getAllProfessions error: $e');
      // If aggregate fails, try simple select as fallback to at least show professions
      try {
        final simpleResponse = await _client.from('professions')
            .select()
            .order('display_order');
        return (simpleResponse as List).map((e) => Profession.fromJson(e)).toList();
      } catch (e2) {
        debugPrint('Fallback getAllProfessions error: $e2');
        rethrow;
      }
    }
  }

  /// ดึงอาชีพตาม ID
  Future<Profession?> getProfessionById(String id) async {
    try {
      final response = await _client
          .from('professions')
          .select('*, category_data:user_categories!professions_category_fkey(*)')
          .eq('id', id)
          .single();
      return Profession.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// ดึงอาชีพตาม category
  Future<List<Profession>> getProfessionsByCategory(UserCategory category) async {
    final response = await _client
        .from('professions')
        .select()
        .eq('category', category.value)
        .eq('is_active', true)
        .order('display_order');

    return (response as List).map((e) => Profession.fromJson(e)).toList();
  }

  /// สร้างอาชีพใหม่
  Future<Profession> createProfession({
    required String name,
    String? nameEn,
    String? description,
    String? iconName,
    required UserCategory category,
    String? colorHex,
    bool requiresVerification = true,
    bool requiresSheservedApproval = false,
    bool isVolunteer = false,
    bool canPrescribeMedication = false,
    bool canDispenseMedication = false,
    bool canManageDrugRisk = false,
    bool requiresTelemedicineLicense = false,
    List<String> approvalRequiredLicenseTypes = const [],
    String? professionCode,
    int displayOrder = 0,
  }) async {
    final now = DateTime.now();
    final data = {
      'profession_code': professionCode,
      'name': name,
      'name_en': nameEn,
      'description': description,
      'icon_name': iconName,
      'category': category.value,
      'color_hex': colorHex,
      'is_built_in': false,
      'is_active': true,
      'is_volunteer': isVolunteer,
      'requires_verification': requiresVerification,
      'requires_sheserved_approval': requiresSheservedApproval,
      'can_prescribe_medication': canPrescribeMedication,
      'can_dispense_medication': canDispenseMedication,
      'can_manage_drug_risk': canManageDrugRisk,
      'requires_telemedicine_license': requiresTelemedicineLicense,
      'approval_required_license_types': approvalRequiredLicenseTypes,
      'display_order': displayOrder,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    final response =
        await _client.from('professions').insert(data).select().single();
    return Profession.fromJson(response);
  }

  /// อัพเดทอาชีพ
  Future<Profession> updateProfession(String id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    try {
      final response = await _client.rpc(
        'update_profession_bypass_rls',
        params: {'p_id': id, 'p_data': data},
      );
      if (response == null) {
        throw Exception('ไม่พบอาชีพที่ต้องการอัปเดต (id: $id)');
      }
      return Profession.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      debugPrint('RPC update failed: $e, falling back to direct update');
      // Fallback: direct update (for local dev or when RPC not available)
      final response = await _client
          .from('professions')
          .update(data)
          .eq('id', id)
          .select()
          .maybeSingle();
      if (response == null) {
        throw Exception('ไม่พบอาชีพที่ต้องการอัปเดต (id: $id) — ตรวจสอบ RLS policy');
      }
      return Profession.fromJson(response);
    }
  }

  /// ลบอาชีพ (soft delete)
  Future<void> deleteProfession(String id) async {
    // Check if built-in
    final profession = await getProfessionById(id);
    if (profession?.isBuiltIn == true) {
      throw Exception('ไม่สามารถลบอาชีพ Built-in ได้');
    }

    await _client
        .from('professions')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  /// เรียงลำดับอาชีพใหม่ (Bulk Update)
  Future<void> reorderProfessions(List<Profession> professions) async {
    final now = DateTime.now().toIso8601String();
    final data = <Map<String, dynamic>>[];
    
    for (int i = 0; i < professions.length; i++) {
      data.add({
        'id': professions[i].id,
        'name': professions[i].name, // Safe for upsert NOT-NULL constraint
        'category': professions[i].category.value, // Required field
        'display_order': i,
        'updated_at': now,
      });
    }

    await _client.from('professions').upsert(data);
  }

  /// คัดลอก fields จากอาชีพหนึ่งไปยังอีกอาชีพ
  Future<void> copyFieldsFromProfession(
    String sourceProfessionId,
    String targetProfessionId,
  ) async {
    // Get source fields
    final sourceFields = await _client
        .from('registration_field_configs')
        .select()
        .eq('profession_id', sourceProfessionId)
        .eq('is_active', true)
        .order('field_order');

    // Copy fields to target
    final now = DateTime.now().toIso8601String();
    for (final field in sourceFields) {
      final newField = Map<String, dynamic>.from(field);
      newField.remove('id');
      newField['profession_id'] = targetProfessionId;
      newField['created_at'] = now;
      newField['updated_at'] = now;

      await _client.from('registration_field_configs').insert(newField);
    }
  }

  // =====================================================
  // REGISTRATION FIELD CONFIGS
  // =====================================================

  /// ดึง field configs ของอาชีพ
  Future<List<RegistrationFieldConfig>> getFieldConfigsForProfession(
    String professionId,
  ) async {
    final response = await _client
        .from('registration_field_configs')
        .select()
        .eq('profession_id', professionId)
        .eq('is_active', true)
        .order('field_order');

    return (response as List)
        .map((e) => RegistrationFieldConfig.fromJson(e))
        .toList();
  }

  /// เพิ่ม field config
  Future<RegistrationFieldConfig> addFieldConfig({
    required String professionId,
    required String fieldId,
    required String label,
    String? hint,
    required FieldType fieldType,
    bool isRequired = false,
    bool isLocked = false,
    bool requiresAttachment = false,
    String? attachmentGroupKey,
    bool attachmentRequiredWhenFilled = false,
    List<String>? visibleWhenProfessionCodes,
    int order = 0,
    String? iconName,
    List<String>? dropdownOptions,
  }) async {
    final now = DateTime.now();
    final data = {
      'profession_id': professionId,
      'field_id': fieldId,
      'field_key': fieldId,
      'label': label,
      'hint': hint,
      'field_type': fieldType.name,
      'is_required': isRequired,
      'is_locked': isLocked,
      'requires_attachment': requiresAttachment,
      'attachment_group_key': attachmentGroupKey,
      'attachment_required_when_filled': attachmentRequiredWhenFilled,
      'visible_when_profession_code': visibleWhenProfessionCodes,
      'field_order': order,
      'icon_name': iconName,
      'dropdown_options': dropdownOptions,
      'is_active': true,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    final response = await _client
        .from('registration_field_configs')
        .insert(data)
        .select()
        .single();
    return RegistrationFieldConfig.fromJson(response);
  }

  /// อัพเดท field config
  Future<void> updateFieldConfig(String id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('registration_field_configs').update(data).eq('id', id);
  }

  /// ลบ field config
  Future<void> deleteFieldConfig(String id) async {
    await _client
        .from('registration_field_configs')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  // =====================================================
  // REGISTRATION APPLICATIONS
  // =====================================================

  /// ดึงรายการผู้สมัครรอตรวจสอบ
  Future<List<RegistrationApplication>> getPendingApplications({
    String? professionId,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _client.from('registration_applications').select('''
      *,
      profession:professions(*)
    ''').eq('status', 'pending');

    if (professionId != null) {
      query = query.eq('profession_id', professionId);
    }

    final response = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((e) => RegistrationApplication.fromJson(e))
        .toList();
  }

  /// ดึงรายการผู้สมัครทั้งหมด
  Future<List<RegistrationApplication>> getAllApplications({
    VerificationStatus? status,
    String? professionId,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _client.from('registration_applications').select('''
      *,
      profession:professions(*)
    ''');

    if (status != null) {
      query = query.eq('status', status.value);
    }
    if (professionId != null) {
      query = query.eq('profession_id', professionId);
    }

    final response = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((e) => RegistrationApplication.fromJson(e))
        .toList();
  }

  /// ดึงผู้สมัครตาม ID
  Future<RegistrationApplication?> getApplicationById(String id) async {
    try {
      final response = await _client
          .from('registration_applications')
          .select('''
            *,
            profession:professions(*)
          ''')
          .eq('id', id)
          .single();
      return RegistrationApplication.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// ตรวจสอบว่า user สามารถสมัครสำหรับอาชีพนี้ได้หรือไม่ (pre-check ก่อนเปลี่ยนอาชีพ)
  /// คืน null ถ้าสมัครได้, คืนข้อความ error ถ้าสมัครไม่ได้
  Future<String?> canCreateApplication({
    required String userId,
    required String professionId,
  }) async {
    final existingApps = await _client
        .from('registration_applications')
        .select('id, status, profession_id')
        .eq('user_id', userId)
        .inFilter('status', ['pending', 'approved']);

    final rows = existingApps as List;

    final hasPending = rows.any((r) => r['status'] == 'pending');
    if (hasPending) {
      return 'คุณมีใบสมัครที่กำลังรอตรวจสอบอยู่แล้ว กรุณารอผลตรวจสอบหรือยกเลิกใบสมัครเดิมก่อนสมัครใหม่';
    }

    final userRes = await _client
        .from('users')
        .select('profession_id')
        .eq('id', userId)
        .single();
    final currentProfessionId = userRes['profession_id'] as String?;
    final isCurrentlyInThisProfession = currentProfessionId == professionId;

    // บล็อก approved application เฉพาะเมื่อ user ยังอยู่ในอาชีพนี้จริงๆ
    // ถ้า user เปลี่ยนออกไปแล้ว อนุญาตให้สมัครใหม่ได้ (cleanup trigger จะจัดการข้อมูลเก่า)
    final hasApprovedSameProfession = rows.any(
      (r) => r['status'] == 'approved' && r['profession_id'] == professionId,
    );
    if (hasApprovedSameProfession && isCurrentlyInThisProfession) {
      return 'คุณได้รับการอนุมัติสำหรับอาชีพนี้แล้ว ไม่สามารถสมัครซ้ำได้';
    }

    final existingRole = await _client
        .from('employee_roles')
        .select('id')
        .eq('user_id', userId)
        .eq('profession_id', professionId)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();

    if (existingRole != null) {
      return 'คุณมีสิทธิ์ในองค์กรนี้อยู่แล้ว ไม่สามารถสมัครซ้ำได้ หากต้องการเปลี่ยนสิทธิ์กรุณาติดต่อผู้ดูแลระบบ';
    }

    return null;
  }

  /// สร้างใบสมัคร (atomic — ใช้ RPC เพื่อกัน TOCTOU race condition)
  Future<RegistrationApplication> createApplication({
    required String oderId,
    required String professionId,
    required String firstName,
    required String lastName,
    required String username,
    String? phone,
    String? profileImageUrl,
    Map<String, dynamic>? registrationData,
  }) async {
    try {
      final response = await _client.rpc(
        'create_registration_application',
        params: {
          'p_user_id': oderId,
          'p_profession_id': professionId,
          'p_first_name': firstName,
          'p_last_name': lastName,
          'p_username': username,
          'p_phone': phone,
          'p_profile_image_url': profileImageUrl,
          'p_registration_data': registrationData ?? {},
        },
      );

      return RegistrationApplication.fromJson(response as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      // Map RPC error codes to user-friendly Thai messages
      final msg = e.message;
      if (msg.contains('PENDING_EXISTS')) {
        throw Exception(
          'คุณมีใบสมัครที่กำลังรอตรวจสอบอยู่แล้ว กรุณารอผลตรวจสอบหรือยกเลิกใบสมัครเดิมก่อนสมัครใหม่',
        );
      } else if (msg.contains('APPROVED_EXISTS')) {
        throw Exception(
          'คุณได้รับการอนุมัติสำหรับอาชีพนี้แล้ว ไม่สามารถสมัครซ้ำได้',
        );
      } else if (msg.contains('ROLE_EXISTS')) {
        throw Exception(
          'คุณมีสิทธิ์ในองค์กรนี้อยู่แล้ว ไม่สามารถสมัครซ้ำได้ หากต้องการเปลี่ยนสิทธิ์กรุณาติดต่อผู้ดูแลระบบ',
        );
      }
      rethrow;
    }
  }

  /// อนุมัติใบสมัคร (Deprecated — ใช้ RegistrationRepository.approveApplication แทน)
  @Deprecated('ใช้ RegistrationRepository.approveApplication แทน เพื่อรองรับ race-condition guard')
  Future<void> approveApplication(
    String applicationId, {
    String? reviewNote,
    String? reviewedBy,
  }) async {
    final regRepo = RegistrationRepository(_client);
    final application = await getApplicationById(applicationId);
    if (application != null) {
      await regRepo.approveApplication(application, reviewedBy: reviewedBy);
    }
  }

  /// ปฏิเสธใบสมัคร (Deprecated — ใช้ RegistrationRepository.rejectApplication แทน)
  @Deprecated('ใช้ RegistrationRepository.rejectApplication แทน เพื่อรองรับ race-condition guard')
  Future<void> rejectApplication(
    String applicationId, {
    required String reviewNote,
    String? reviewedBy,
  }) async {
    final regRepo = RegistrationRepository(_client);
    final application = await getApplicationById(applicationId);
    if (application != null) {
      await regRepo.rejectApplication(application, reviewNote, reviewedBy: reviewedBy);
    }
  }

  /// นับจำนวนผู้สมัครรอตรวจสอบ
  Future<int> getPendingCount() async {
    final response = await _client
        .from('registration_applications')
        .select()
        .eq('status', 'pending');
    return (response as List).length;
  }

  /// นับจำนวนผู้สมัครรอตรวจสอบแยกตามอาชีพ
  Future<Map<String, int>> getPendingCountByProfession() async {
    final response = await _client
        .from('registration_applications')
        .select('profession_id')
        .eq('status', 'pending');

    final Map<String, int> counts = {};
    for (final item in response) {
      final professionId = item['profession_id'] as String;
      counts[professionId] = (counts[professionId] ?? 0) + 1;
    }
    return counts;
  }
}
