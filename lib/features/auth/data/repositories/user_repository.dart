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
          await _client.from('users').select().eq('id', id).single();
      return UserModel.fromJson(response);
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
  Future<UserModel?> login(String identifier, String password) async {
    final hashedPassword = _hashPassword(password);
    
    try {
      // 1. Try finding by username
      var response = await _client
          .from('users')
          .select()
          .eq('username', identifier)
          .eq('password_hash', hashedPassword)
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        return UserModel.fromJson(response);
      }

      // 2. Try finding by phone
      response = await _client
          .from('users')
          .select()
          .eq('phone', identifier)
          .eq('password_hash', hashedPassword)
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        return UserModel.fromJson(response);
      }

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
          .select()
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
    var query = _client.from('expert_profiles').select('*, users(verification_status)');

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
          .select()
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
    var query = _client.from('clinic_profiles').select();

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
}
