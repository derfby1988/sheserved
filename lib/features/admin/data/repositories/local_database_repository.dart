import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/profession.dart';
import '../../models/registration_field_config.dart';

/// Repository สำหรับจัดการข้อมูลผ่าน Local PostgreSQL + WebSocket Server
/// ใช้แทน Supabase สำหรับ Development
class LocalDatabaseRepository {
  final String _baseUrl;

  LocalDatabaseRepository({String? baseUrl})
      : _baseUrl = baseUrl ?? 'http://localhost:3000';

  // =====================================================
  // HTTP HELPERS
  // =====================================================

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<dynamic> _get(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl$endpoint'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      throw Exception('GET $endpoint failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('LocalDatabaseRepository GET error: $e');
      rethrow;
    }
  }

  Future<dynamic> _post(String endpoint, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: _headers,
        body: json.encode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      }
      throw Exception('POST $endpoint failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('LocalDatabaseRepository POST error: $e');
      rethrow;
    }
  }

  // =====================================================
  // PROFESSION CRUD
  // =====================================================

  /// ดึงรายการอาชีพทั้งหมด
  Future<List<Profession>> getAllProfessions({bool activeOnly = true}) async {
    final response = await _get('/api/professions');
    return (response as List).map((json) {
      // Handle field_count - ต้อง fetch แยก
      json['field_count'] = 0;
      return Profession.fromJson(json);
    }).toList();
  }

  /// ดึงอาชีพตาม ID
  Future<Profession?> getProfessionById(String id) async {
    try {
      final response = await _get('/api/professions/$id');
      response['field_count'] = 0;
      return Profession.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// ดึงอาชีพตาม category
  Future<List<Profession>> getProfessionsByCategory(UserCategory category) async {
    final allProfessions = await getAllProfessions();
    return allProfessions.where((p) => p.category == category).toList();
  }

  // =====================================================
  // REGISTRATION FIELD CONFIGS
  // =====================================================

  /// ดึง field configs ของอาชีพ
  Future<List<RegistrationFieldConfig>> getFieldConfigsForProfession(
    String professionId,
  ) async {
    final response = await _get('/api/professions/$professionId/fields');
    return (response as List).map((json) {
      // Convert snake_case to camelCase
      final converted = {
        'id': json['id'],
        'professionId': json['profession_id'] ?? professionId,
        'fieldId': json['field_id'],
        'label': json['label'],
        'hint': json['hint'],
        'fieldType': json['field_type'],
        'isRequired': json['is_required'] ?? false,
        'fieldOrder': json['field_order'] ?? 0,
        'iconName': json['icon_name'],
        'dropdownOptions': json['dropdown_options'],
        'validationRegex': json['validation_regex'],
        'validationMessage': json['validation_message'],
        'isActive': json['is_active'] ?? true,
      };
      return RegistrationFieldConfig.fromJson(converted);
    }).toList();
  }

  // =====================================================
  // USERS
  // =====================================================

  /// สร้าง user
  Future<Map<String, dynamic>> createUser({
    required String professionId,
    required String firstName,
    required String lastName,
    required String username,
    String? email,
    String? phone,
    String? passwordHash,
    String? socialProvider,
    String? socialId,
  }) async {
    return await _post('/api/users', {
      'professionId': professionId,
      'firstName': firstName,
      'lastName': lastName,
      'username': username,
      'email': email,
      'phone': phone,
      'passwordHash': passwordHash,
      'socialProvider': socialProvider,
      'socialId': socialId,
    });
  }

  /// ดึง user ตาม ID
  Future<Map<String, dynamic>?> getUserById(String userId) async {
    try {
      return await _get('/api/users/$userId');
    } catch (e) {
      return null;
    }
  }

  // =====================================================
  // REGISTRATION APPLICATIONS
  // =====================================================

  /// ดึงรายการผู้สมัครรอตรวจสอบ
  Future<List<RegistrationApplication>> getPendingApplications({
    String? professionId,
  }) async {
    String endpoint = '/api/applications?status=pending';
    if (professionId != null) {
      endpoint += '&profession_id=$professionId';
    }
    final response = await _get(endpoint);
    return (response as List).map((json) {
      return _convertApplicationJson(json);
    }).toList();
  }

  /// ดึงรายการผู้สมัครทั้งหมด
  Future<List<RegistrationApplication>> getAllApplications({
    VerificationStatus? status,
    String? professionId,
  }) async {
    String endpoint = '/api/applications';
    final params = <String>[];
    if (status != null) params.add('status=${status.value}');
    if (professionId != null) params.add('profession_id=$professionId');
    if (params.isNotEmpty) endpoint += '?${params.join('&')}';

    final response = await _get(endpoint);
    return (response as List).map((json) {
      return _convertApplicationJson(json);
    }).toList();
  }

  /// ดึงผู้สมัครตาม ID
  Future<RegistrationApplication?> getApplicationById(String id) async {
    try {
      final response = await _get('/api/applications/$id');
      return _convertApplicationJson(response);
    } catch (e) {
      return null;
    }
  }

  /// สร้างใบสมัคร
  Future<RegistrationApplication> createApplication({
    required String userId,
    required String professionId,
    required String firstName,
    required String lastName,
    required String username,
    String? phone,
    String? profileImageUrl,
    Map<String, dynamic>? registrationData,
  }) async {
    final response = await _post('/api/applications', {
      'userId': userId,
      'professionId': professionId,
      'firstName': firstName,
      'lastName': lastName,
      'username': username,
      'phone': phone,
      'profileImageUrl': profileImageUrl,
      'registrationData': registrationData ?? {},
    });
    return _convertApplicationJson(response);
  }

  /// อนุมัติใบสมัคร
  Future<void> approveApplication(
    String applicationId, {
    String? reviewNote,
    String? reviewedBy,
  }) async {
    await _post('/api/applications/$applicationId/approve', {
      'note': reviewNote,
      'reviewedBy': reviewedBy,
    });
  }

  /// ปฏิเสธใบสมัคร
  Future<void> rejectApplication(
    String applicationId, {
    required String reviewNote,
    String? reviewedBy,
  }) async {
    await _post('/api/applications/$applicationId/reject', {
      'note': reviewNote,
      'reviewedBy': reviewedBy,
    });
  }

  /// นับจำนวนผู้สมัครรอตรวจสอบ
  Future<int> getPendingCount() async {
    final applications = await getPendingApplications();
    return applications.length;
  }

  // =====================================================
  // HELPERS
  // =====================================================

  RegistrationApplication _convertApplicationJson(Map<String, dynamic> json) {
    // Convert snake_case to camelCase and handle profession
    Profession? profession;
    if (json['profession_name'] != null) {
      profession = Profession(
        id: json['profession_id'],
        name: json['profession_name'],
        category: json['profession_category'] == 'consumer'
            ? UserCategory.consumer
            : UserCategory.provider,
        isBuiltIn: false,
        requiresVerification: true,
        fieldCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    return RegistrationApplication(
      id: json['id'],
      oderId: json['user_id'],
      professionId: json['profession_id'],
      profession: profession,
      firstName: json['first_name'],
      lastName: json['last_name'] ?? '',
      username: json['username'],
      phone: json['phone'],
      profileImageUrl: json['profile_image_url'],
      registrationData: json['registration_data'] is String
          ? jsonDecode(json['registration_data'])
          : (json['registration_data'] ?? {}),
      status: VerificationStatus.values.firstWhere(
        (e) => e.value == json['status'],
        orElse: () => VerificationStatus.pending,
      ),
      reviewNote: json['review_note'],
      reviewedBy: json['reviewed_by'],
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  // =====================================================
  // HEALTH CHECK
  // =====================================================

  /// ตรวจสอบการเชื่อมต่อ
  Future<bool> healthCheck() async {
    try {
      final response = await _get('/health');
      return response['status'] == 'ok';
    } catch (e) {
      return false;
    }
  }
}
