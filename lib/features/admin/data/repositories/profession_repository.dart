import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/profession.dart';
import '../../models/registration_field_config.dart';

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
          .order('display_order');
      
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

      final response = await query.order('display_order').timeout(const Duration(seconds: 10));

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
          .select()
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
    bool requiresVerification = true,
    int displayOrder = 0,
  }) async {
    final now = DateTime.now();
    final data = {
      'name': name,
      'name_en': nameEn,
      'description': description,
      'icon_name': iconName,
      'category': category.value,
      'is_built_in': false,
      'is_active': true,
      'requires_verification': requiresVerification,
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
    final response = await _client
        .from('professions')
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return Profession.fromJson(response);
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

  /// เรียงลำดับอาชีพใหม่
  Future<void> reorderProfessions(List<String> professionIds) async {
    for (int i = 0; i < professionIds.length; i++) {
      await _client
          .from('professions')
          .update({
            'display_order': i,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', professionIds[i]);
    }
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
    int order = 0,
    String? iconName,
    List<String>? dropdownOptions,
  }) async {
    final now = DateTime.now();
    final data = {
      'profession_id': professionId,
      'field_id': fieldId,
      'label': label,
      'hint': hint,
      'field_type': fieldType.name,
      'is_required': isRequired,
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

  /// สร้างใบสมัคร
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
    final now = DateTime.now();
    final data = {
      'user_id': oderId,
      'profession_id': professionId,
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'phone': phone,
      'profile_image_url': profileImageUrl,
      'registration_data': registrationData ?? {},
      'status': 'pending',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    final response = await _client
        .from('registration_applications')
        .insert(data)
        .select()
        .single();
    return RegistrationApplication.fromJson(response);
  }

  /// อนุมัติใบสมัคร
  Future<void> approveApplication(
    String applicationId, {
    String? reviewNote,
    String? reviewedBy,
  }) async {
    final now = DateTime.now();
    await _client
        .from('registration_applications')
        .update({
          'status': 'approved',
          'review_note': reviewNote,
          'reviewed_by': reviewedBy,
          'reviewed_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        })
        .eq('id', applicationId);

    // Update user verification status
    final application = await getApplicationById(applicationId);
    if (application != null) {
      await _client
          .from('users')
          .update({
            'verification_status': 'verified',
            'updated_at': now.toIso8601String(),
          })
          .eq('id', application.oderId);
    }
  }

  /// ปฏิเสธใบสมัคร
  Future<void> rejectApplication(
    String applicationId, {
    required String reviewNote,
    String? reviewedBy,
  }) async {
    final now = DateTime.now();
    await _client
        .from('registration_applications')
        .update({
          'status': 'rejected',
          'review_note': reviewNote,
          'reviewed_by': reviewedBy,
          'reviewed_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        })
        .eq('id', applicationId);

    // Update user verification status
    final application = await getApplicationById(applicationId);
    if (application != null) {
      await _client
          .from('users')
          .update({
            'verification_status': 'rejected',
            'updated_at': now.toIso8601String(),
          })
          .eq('id', application.oderId);
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
