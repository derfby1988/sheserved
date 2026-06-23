import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'package:sheserved/config/app_config.dart';

/// User Repository - จัดการข้อมูลผู้ใช้ใน Database
class UserRepository {
  final SupabaseClient _client;

  UserRepository(this._client);

  // =====================================================
  // USER CRUD
  // =====================================================

  /// สร้างผู้ใช้ใหม่
  Future<UserModel> createUser({
    required UserType userType,
    required String firstName,
    required String lastName,
    required String username,
    required String password,
    String? professionId,
    String? phone,
    String? email,
    String? profileImageUrl,
  }) async {
    final now = DateTime.now();
    final hashedPassword = _hashPassword(password);
    
    final data = {
      'profession_id': professionId,
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'password_hash': hashedPassword,
      'phone': phone,
      'email': email,
      'profile_image_url': profileImageUrl,
      'verification_status': 'pending',
      'is_active': true,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    if (AppConfig.databaseMode == DatabaseMode.localOnly) {
      final response = await http.post(
        Uri.parse('${AppConfig.localApiUrl}/api/users'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'professionId': professionId,
          'firstName': firstName,
          'lastName': lastName,
          'username': username,
          'email': email,
          'phone': phone,
          'passwordHash': hashedPassword,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return UserModel.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create user on local API: ${response.body}');
      }
    }

    final response = await _client.from('users').insert(data).select().single();
    return UserModel.fromJson(response);
  }

  /// ดึงข้อมูลผู้ใช้จาก ID
  Future<UserModel?> getUserById(String id) async {
    try {
      final response =
          await _client.from('users').select('*, professions(is_volunteer), role').eq('id', id).single();
      var user = UserModel.fromJson(response);
      
      if (user.professionId == null) {
        try {
          final groupResponse = await _client
              .from('user_group_roles')
              .select('profession_id')
              .eq('user_id', user.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 5));
          if (groupResponse != null) {
            user = user.copyWith(professionId: groupResponse['profession_id']);
          }
        } catch (e) {
          debugPrint('getUserById: Optional user_group_roles check failed: $e');
        }
      }
      return user;
    } catch (e) {
      return null;
    }
  }

  /// ดึงข้อมูลผู้ใช้จาก Username
  Future<UserModel?> getUserByUsername(String username) async {
    try {
      final response = await _client
          .from('users')
          .select()
          .eq('username', username)
          .single();
      return UserModel.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// ตรวจสอบว่า username มีอยู่แล้วหรือไม่
  Future<bool> isUsernameExists(String username) async {
    final response = await _client
        .from('users')
        .select('id')
        .eq('username', username)
        .maybeSingle();
    return response != null;
  }

  /// ตรวจสอบว่า phone มีอยู่แล้วหรือไม่
  Future<bool> isPhoneExists(String phone) async {
    final response = await _client
        .from('users')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();
    return response != null;
  }

  /// เข้าสู่ระบบด้วย Username หรือ Phone และ Password
  /// รัน query ขนานกัน + timeout ป้องกัน login ค้าง
  Future<UserModel?> login(String identifier, String password) async {
    final hashedPassword = _hashPassword(password);

    try {
      // 1. ค้นหา username + phone พร้อมกัน (parallel) พร้อม timeout
      final results = await Future.wait([
        _client
            .from('users')
            .select('*, professions(is_volunteer)')
            .eq('username', identifier)
            .eq('password_hash', hashedPassword)
            .eq('is_active', true)
            .maybeSingle()
            .timeout(const Duration(seconds: 8)),
        _client
            .from('users')
            .select('*, professions(is_volunteer)')
            .eq('phone', identifier)
            .eq('password_hash', hashedPassword)
            .eq('is_active', true)
            .maybeSingle()
            .timeout(const Duration(seconds: 8)),
      ]);

      UserModel? user;
      final usernameResult = results[0];
      final phoneResult = results[1];

      if (usernameResult != null) {
        user = UserModel.fromJson(usernameResult);
      } else if (phoneResult != null) {
        user = UserModel.fromJson(phoneResult);
      }

      if (user != null && user.professionId == null) {
        try {
          // Fallback: check user_group_roles table if profession_id is null in users table
          final groupResponse = await _client
              .from('user_group_roles')
              .select('profession_id')
              .eq('user_id', user.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 5));
          if (groupResponse != null) {
            user = user.copyWith(professionId: groupResponse['profession_id']);
          }
        } catch (e) {
          debugPrint('login: Optional user_group_roles check failed: $e');
        }
      }

      return user;
    } on TimeoutException catch (e) {
      debugPrint('UserRepository.login timeout: $e');
      return null;
    } catch (e) {
      debugPrint('UserRepository.login error: $e');
      return null;
    }
  }

  /// ฟังก์ชันช่วยสำหรับ Hash Password
  String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    var digest = crypto.sha256.convert(bytes);
    return digest.toString();
  }

  /// อัพเดทข้อมูลผู้ใช้
  Future<UserModel> updateUser(String id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    final response =
        await _client.from('users').update(data).eq('id', id).select().single();
    return UserModel.fromJson(response);
  }

  /// อัพเดทรหัสผ่าน
  Future<bool> updatePassword(String id, String newPassword) async {
    try {
      await _client
          .from('users')
          .update({
            'password_hash': newPassword, // TODO: Hash password
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// อัพเดทสถานะการยืนยัน
  Future<UserModel> updateVerificationStatus(
      String id, VerificationStatus status) async {
    return await updateUser(id, {'verification_status': status.value});
  }

  // =====================================================
  // SOCIAL LOGIN
  // =====================================================

  /// ค้นหาผู้ใช้จาก Social Provider ID
  Future<UserModel?> getUserBySocialId(String provider, String socialId) async {
    try {
      final response = await _client
          .from('users')
          .select()
          .eq('social_provider', provider)
          .eq('social_id', socialId)
          .eq('is_active', true)
          .single();
      return UserModel.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// สร้างผู้ใช้ใหม่จาก Social Login
  Future<UserModel> createUserFromSocial({
    required UserType userType,
    required String firstName,
    required String lastName,
    required String username,
    required String socialProvider,
    required String socialId,
    String? profileImageUrl,
    String? phone,
  }) async {
    final now = DateTime.now();
    final data = {
      'user_type': userType.value,
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'password_hash': null, // No password for social login
      'social_provider': socialProvider,
      'social_id': socialId,
      'phone': phone,
      'profile_image_url': profileImageUrl,
      'verification_status': 'verified', // Social accounts are pre-verified
      'is_active': true,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'last_login_at': now.toIso8601String(),
    };

    final response = await _client.from('users').insert(data).select().single();
    return UserModel.fromJson(response);
  }

  /// เชื่อมต่อ Social Account กับผู้ใช้ที่มีอยู่
  Future<UserModel> linkSocialAccount(
      String userId, String socialProvider, String socialId) async {
    return await updateUser(userId, {
      'social_provider': socialProvider,
      'social_id': socialId,
    });
  }

  /// ยกเลิกการเชื่อมต่อ Social Account
  Future<UserModel> unlinkSocialAccount(String userId) async {
    return await updateUser(userId, {
      'social_provider': null,
      'social_id': null,
    });
  }

  // =====================================================
  // CONSUMER PROFILE
  // =====================================================

  /// สร้าง Consumer Profile
  Future<ConsumerProfile> createConsumerProfile({
    required String userId,
    DateTime? birthday,
    String? address,
    String? emergencyContact,
    String? emergencyPhone,
    Map<String, dynamic>? healthInfo,
  }) async {
    final now = DateTime.now();
    final data = {
      'user_id': userId,
      'birthday': birthday?.toIso8601String(),
      'address': address,
      'emergency_contact': emergencyContact,
      'emergency_phone': emergencyPhone,
      'health_info': healthInfo,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    final response =
        await _client.from('consumer_profiles').insert(data).select().single();
    return ConsumerProfile.fromJson(response);
  }

  /// ดึง Consumer Profile จาก User ID
  Future<ConsumerProfile?> getConsumerProfile(String userId) async {
    try {
      final response = await _client
          .from('consumer_profiles')
          .select()
          .eq('user_id', userId)
          .single();
      return ConsumerProfile.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// อัพเดท Consumer Profile
  Future<ConsumerProfile> updateConsumerProfile(
      String userId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    final response = await _client
        .from('consumer_profiles')
        .update(data)
        .eq('user_id', userId)
        .select()
        .single();
    return ConsumerProfile.fromJson(response);
  }

  // =====================================================
  // EXPERT PROFILE
  // =====================================================

  /// สร้าง Expert Profile
  Future<ExpertProfile> createExpertProfile({
    required String userId,
    String? businessName,
    String? specialty,
    int? experienceYears,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
    String? description,
    String? idCardImageUrl,
    String? certificateImageUrl,
  }) async {
    final now = DateTime.now();
    final data = {
      'user_id': userId,
      'business_name': businessName,
      'specialty': specialty,
      'experience_years': experienceYears,
      'business_address': businessAddress,
      'business_phone': businessPhone,
      'business_email': businessEmail,
      'description': description,
      'id_card_image_url': idCardImageUrl,
      'certificate_image_url': certificateImageUrl,
      'rating': 0,
      'review_count': 0,
      'is_available': true,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    final response =
        await _client.from('expert_profiles').insert(data).select().single();
    return ExpertProfile.fromJson(response);
  }

  /// ดึง Expert Profile จาก User ID
  Future<ExpertProfile?> getExpertProfile(String userId) async {
    try {
      final response = await _client
          .from('expert_profiles')
          .select('*, users(verification_status, last_seen_at, availability_status)')
          .eq('user_id', userId)
          .single();
      return ExpertProfile.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// ดึง Expert Profiles ทั้งหมด
  Future<List<ExpertProfile>> getAllExpertProfiles({
    String? specialty,
    bool? isAvailable,
    int limit = 20,
    int offset = 0,
  }) async {
    var query = _client.from('expert_profiles').select('*, users(verification_status, last_seen_at, availability_status)');

    if (specialty != null) {
      query = query.eq('specialty', specialty);
    }
    if (isAvailable != null) {
      query = query.eq('is_available', isAvailable);
    }

    final response = await query
        .order('rating', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((e) => ExpertProfile.fromJson(e))
        .toList();
  }

  /// อัพเดท Expert Profile
  Future<ExpertProfile> updateExpertProfile(
      String userId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    final response = await _client
        .from('expert_profiles')
        .update(data)
        .eq('user_id', userId)
        .select()
        .single();
    return ExpertProfile.fromJson(response);
  }

  // =====================================================
  // CLINIC PROFILE
  // =====================================================

  /// สร้าง Clinic Profile
  Future<ClinicProfile> createClinicProfile({
    required String userId,
    String? clinicName,
    String? licenseNumber,
    String? serviceType,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
    String? description,
    String? businessImageUrl,
    String? licenseImageUrl,
    String? idCardImageUrl,
    double? latitude,
    double? longitude,
    List<String>? services,
  }) async {
    final now = DateTime.now();
    final data = {
      'user_id': userId,
      'clinic_name': clinicName,
      'license_number': licenseNumber,
      'service_type': serviceType,
      'business_address': businessAddress,
      'business_phone': businessPhone,
      'business_email': businessEmail,
      'description': description,
      'business_image_url': businessImageUrl,
      'license_image_url': licenseImageUrl,
      'id_card_image_url': idCardImageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'rating': 0,
      'review_count': 0,
      'is_open': true,
      'services': services,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    final response =
        await _client.from('clinic_profiles').insert(data).select().single();
    return ClinicProfile.fromJson(response);
  }

  /// ดึง Clinic Profile จาก User ID
  Future<ClinicProfile?> getClinicProfile(String userId) async {
    try {
      final response = await _client
          .from('clinic_profiles')
          .select('*, users(verification_status, last_seen_at, availability_status)')
          .eq('user_id', userId)
          .single();
      return ClinicProfile.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// ดึง Clinic Profiles ทั้งหมด
  Future<List<ClinicProfile>> getAllClinicProfiles({
    String? serviceType,
    bool? isOpen,
    int limit = 20,
    int offset = 0,
  }) async {
    var query = _client.from('clinic_profiles').select('*, users(verification_status, last_seen_at, availability_status)');

    if (serviceType != null) {
      query = query.eq('service_type', serviceType);
    }
    if (isOpen != null) {
      query = query.eq('is_open', isOpen);
    }

    final response = await query
        .order('rating', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((e) => ClinicProfile.fromJson(e))
        .toList();
  }

  /// อัพเดท Clinic Profile
  Future<ClinicProfile> updateClinicProfile(
      String userId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    final response = await _client
        .from('clinic_profiles')
        .update(data)
        .eq('user_id', userId)
        .select()
        .single();
    return ClinicProfile.fromJson(response);
  }

  // =====================================================
  // USER REGISTRATION DATA (Dynamic Fields)
  // =====================================================

  /// บันทึกข้อมูลลงทะเบียนแบบ dynamic
  Future<void> saveRegistrationData(
      String userId, Map<String, String> fieldValues) async {
    final now = DateTime.now().toIso8601String();
    final records = fieldValues.entries.map((e) => {
          'user_id': userId,
          'field_id': e.key,
          'field_value': e.value,
          'created_at': now,
          'updated_at': now,
        }).toList();

    await _client.from('user_registration_data').upsert(
      records,
      onConflict: 'user_id,field_id',
    );
  }

  /// ดึงข้อมูลลงทะเบียนของผู้ใช้
  Future<Map<String, String>> getRegistrationData(String userId) async {
    final response = await _client
        .from('user_registration_data')
        .select()
        .eq('user_id', userId);

    final Map<String, String> result = {};
    for (final record in response) {
      result[record['field_id']] = record['field_value'] ?? '';
    }
    return result;
  }

  // =====================================================
  // PRESENCE / ONLINE STATUS
  // =====================================================

  /// อัปเดต last_seen_at ของผู้ใช้ปัจจุบัน (เรียกจาก heartbeat)
  /// ใช้ RPC (SECURITY DEFINER) เพื่อ bypass RLS เพราะแอปใช้ Custom Auth ไม่ใช่ Supabase Auth
  Future<void> updateLastSeen(String userId) async {
    try {
      await _client.rpc('update_last_seen', params: {'user_id': userId});
    } catch (e) {
      debugPrint('updateLastSeen error: $e');
    }
  }

  /// นับจำนวนผู้ให้บริการ online แยกตาม profession_id
  /// Online = last_seen_at ภายใน 2 นาทีที่ผ่านมา และไม่อยู่ในสถานะ busy
  Future<Map<String, int>> getOnlineProviderCounts() async {
    final threshold = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 5)) // Increased to 5 mins for stability
        .toIso8601String();

    try {
      // ดึงข้อมูลผู้ใช้ที่มีความเคลื่อนไหว โดยจอยกับตารางอาชีพและหมวดหมู่
      // เพื่อตรวจสอบว่าอาชีพนั้นๆ อยู่ในหมวดหมู่ 'provider' หรือไม่
      final response = await _client
          .from('users')
          .select('profession_id, professions!inner(category)')
          .eq('is_active', true)
          .eq('professions.category', 'provider')
          .not('profession_id', 'is', null)
          .neq('availability_status', 'busy')
          .neq('availability_status', 'offline')
          .gte('last_seen_at', threshold);

      // debugPrint('UserRepository: getOnlineProviderCounts found ${response.length} active providers');

      final Map<String, int> counts = {};
      for (final row in response) {
        final profId = row['profession_id'] as String?;
        if (profId != null) {
          counts[profId] = (counts[profId] ?? 0) + 1;
        }
      }
      return counts;
    } catch (e) {
      debugPrint('getOnlineProviderCounts error: $e');
      return {};
    }
  }

  /// Stream สำหรับ real-time อัปเดต online counts
  /// subscribe ต่อตาราง users แล้วคำนวณใหม่ทุกครั้งที่มีการเปลี่ยนแปลง
  Stream<Map<String, int>> watchOnlineProviderCounts() {
    return _client
        .from('users')
        .stream(primaryKey: ['id'])
        .asyncMap((_) => getOnlineProviderCounts());
  }

  /// ดึงจำนวนผู้ใช้ที่ออนไลน์แยกตามหมวดหมู่ (id:provider, id:consumer)
  Future<Map<String, int>> getOnlineCategoryCounts() async {
    final threshold = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 5))
        .toIso8601String();

    try {
      final response = await _client
          .from('users')
          .select('professions!inner(category)')
          .eq('is_active', true)
          .neq('availability_status', 'busy')
          .neq('availability_status', 'offline')
          .gte('last_seen_at', threshold);

      final Map<String, int> counts = {
        'provider': 0,
        'consumer': 0,
      };
      
      for (final row in (response as List)) {
        final professions = row['professions'] as Map<String, dynamic>?;
        final category = professions?['category'] as String?;
        if (category != null) {
          counts[category] = (counts[category] ?? 0) + 1;
        }
      }
      return counts;
    } catch (e) {
      debugPrint('getOnlineCategoryCounts error: $e');
      return {'provider': 0, 'consumer': 0};
    }
  }

  /// Stream สำหรับ real-time อัปเดตจำนวนแยกตามหมวดหมู่
  Stream<Map<String, int>> watchOnlineCategoryCounts() {
    return _client
        .from('users')
        .stream(primaryKey: ['id'])
        .asyncMap((_) => getOnlineCategoryCounts());
  }


  /// นับจำนวนผู้ให้บริการ online ทั้งหมด
  Future<int> getTotalOnlineProviderCount() async {
    final counts = await getOnlineProviderCounts();
    return counts.values.fold<int>(0, (int a, int b) => a + b);
  }

  // =====================================================
  // AVAILABILITY STATUS
  // =====================================================

  /// อัปเดต availability_status ของผู้ใช้
  /// status: 'online', 'busy', 'offline'
  /// ใช้ RPC (SECURITY DEFINER) เพื่อ bypass RLS เพราะแอปใช้ Custom Auth ไม่ใช่ Supabase Auth
  Future<void> setAvailabilityStatus(String userId, String status) async {
    try {
      await _client.rpc('update_availability_status', params: {
        'user_id': userId,
        'new_status': status,
      });
      debugPrint('UserRepository: availability_status → $status for $userId');
    } catch (e) {
      debugPrint('setAvailabilityStatus error: $e');
    }
  }

  /// ดึง availability_status ของผู้ใช้ปัจจุบัน
  Future<String> getAvailabilityStatus(String userId) async {
    try {
      final response = await _client
          .from('users')
          .select('availability_status')
          .eq('id', userId)
          .single();
      return response['availability_status'] as String? ?? 'online';
    } catch (e) {
      return 'online';
    }
  }

  /// นับจำนวนผู้ให้บริการที่ online+available แยกตาม profession_id
  /// (ไม่รวม busy, offline)
  Future<Map<String, int>> getAvailableProviderCounts() async {
    return getOnlineProviderCounts(); // They use the same logic now
  }

  /// Stream real-time สำหรับ available (ไม่ busy) provider counts
  Stream<Map<String, int>> watchAvailableProviderCounts() {
    return _client
        .from('users')
        .stream(primaryKey: ['id'])
        .asyncMap((_) => getAvailableProviderCounts());
  }

  // =====================================================
  // UI PREFERENCES
  // =====================================================

  /// บันทึก UI Preference ของผู้ใช้
  /// [userId]        : ID ของผู้ใช้
  /// [preferenceKey] : key เช่น 'home_consultation_position'
  /// [value]         : ค่า เช่น 'topRight', 'center'
  Future<void> saveUiPreference(
    String userId,
    String preferenceKey,
    String value,
  ) async {
    debugPrint('UserRepository: saveUiPreference user=$userId key=$preferenceKey val=$value');
    
    // 1. Save to Local API if on Main Machine
    if (AppConfig.databaseMode != DatabaseMode.supabaseOnly) {
      try {
        final response = await http.post(
          Uri.parse('${AppConfig.localApiUrl}/api/users/$userId/preferences'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'key': preferenceKey, 'value': value}),
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('UserRepository: ✓ UI preference saved to Local DB');
        } else {
          debugPrint('UserRepository: ⚠️ Local DB save failed: ${response.body}');
        }
      } catch (e) {
        debugPrint('UserRepository: ❌ Local DB save error: $e');
      }
    }

    // 2. Save to Supabase (Always or fallback depending on preference)
    if (AppConfig.databaseMode != DatabaseMode.localOnly) {
      try {
        await _client.from('user_ui_preferences').upsert(
          {
            'user_id': userId,
            'preference_key': preferenceKey,
            'preference_value': value,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'user_id,preference_key',
        );
        debugPrint('UserRepository: ✓ UI preference saved to Supabase');
      } catch (e) {
        debugPrint('UserRepository: ❌ Supabase save error: $e');
      }
    }
  }

  /// ดึง UI Preference ของผู้ใช้
  /// คืน null หากยังไม่เคยบันทึก หรือตารางไม่มี
  Future<String?> getUiPreference(
    String userId,
    String preferenceKey,
  ) async {
    debugPrint('UserRepository: getUiPreference user=$userId key=$preferenceKey');
    
    // 1. Try Local API first if on Main Machine
    if (AppConfig.databaseMode != DatabaseMode.supabaseOnly) {
      try {
        final response = await http.get(
          Uri.parse('${AppConfig.localApiUrl}/api/users/$userId/preferences/$preferenceKey'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['value'] != null) {
            debugPrint('UserRepository: ✓ getUiPreference (Local) result=${data['value']}');
            return data['value'];
          }
        }
      } catch (e) {
        debugPrint('UserRepository: ❌ Local getUiPreference failed: $e');
      }
    }

    // 2. Try Supabase
    try {
      final response = await _client
          .from('user_ui_preferences')
          .select('preference_value')
          .eq('user_id', userId)
          .eq('preference_key', preferenceKey)
          .maybeSingle();
      final val = response?['preference_value'] as String?;
      debugPrint('UserRepository: ✓ getUiPreference (Supabase) result=$val');
      return val;
    } catch (e) {
      debugPrint('UserRepository: ❌ Supabase getUiPreference error: $e');
      return null;
    }
  }
}

