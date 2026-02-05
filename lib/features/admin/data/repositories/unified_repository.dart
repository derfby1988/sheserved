import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/profession.dart';
import '../../models/registration_field_config.dart';
import '../../../../config/app_config.dart';

/// Unified Repository - จัดการข้อมูลจากทั้ง Local และ Supabase
/// 
/// การทำงาน:
/// 1. อ่านข้อมูลจาก Local ก่อน (เร็วกว่า)
/// 2. ถ้า Supabase พร้อมใช้งาน จะ sync ข้อมูลอัตโนมัติ
/// 3. เขียนข้อมูลไปทั้ง 2 ที่พร้อมกัน (เมื่อ online)
/// 4. ถ้า offline จะเก็บไว้ใน queue แล้ว sync ทีหลัง
class UnifiedRepository {
  final String _localApiUrl;
  final bool _supabaseConfigured;
  SupabaseClient? _supabaseClient;
  
  // Offline queue
  final List<_PendingOperation> _offlineQueue = [];
  Timer? _syncTimer;
  bool _isSyncing = false;

  // Stream controllers
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  UnifiedRepository({
    String? localApiUrl,
  }) : _localApiUrl = localApiUrl ?? AppConfig.localApiUrl,
       _supabaseConfigured = AppConfig.supabaseUrl != 'YOUR_SUPABASE_URL' {
    
    // Initialize Supabase client if configured
    if (_supabaseConfigured) {
      try {
        _supabaseClient = Supabase.instance.client;
      } catch (e) {
        debugPrint('UnifiedRepository: Supabase not initialized yet');
      }
    }

    // Start periodic sync
    _startPeriodicSync();
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _processOfflineQueue();
    });
  }

  // =====================================================
  // PROFESSIONS
  // =====================================================

  /// ดึงอาชีพทั้งหมด - อ่านจาก Local ก่อน
  Future<List<Profession>> getAllProfessions({bool forceRefresh = false}) async {
    // ถ้า forceRefresh และ Supabase พร้อม ให้ sync ก่อน
    if (forceRefresh && _supabaseConfigured && _supabaseClient != null) {
      await _syncProfessionsFromSupabase();
    }

    // อ่านจาก Local
    try {
      final response = await http.get(Uri.parse('$_localApiUrl/api/professions'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.map((json) {
          json['field_count'] = 0;
          return Profession.fromJson(json);
        }).toList();
      }
    } catch (e) {
      debugPrint('UnifiedRepository: Failed to fetch from local - $e');
    }

    // Fallback to Supabase if local fails
    if (_supabaseClient != null) {
      try {
        final response = await _supabaseClient!
            .from('professions')
            .select()
            .eq('is_active', true)
            .order('display_order');
        return (response as List).map((json) {
          json['field_count'] = 0;
          return Profession.fromJson(json);
        }).toList();
      } catch (e) {
        debugPrint('UnifiedRepository: Failed to fetch from Supabase - $e');
      }
    }

    return [];
  }

  /// ดึงอาชีพตาม ID
  Future<Profession?> getProfessionById(String id) async {
    // Try local first
    try {
      final response = await http.get(Uri.parse('$_localApiUrl/api/professions/$id'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        data['field_count'] = 0;
        return Profession.fromJson(data);
      }
    } catch (e) {
      debugPrint('UnifiedRepository: Failed to fetch profession from local - $e');
    }

    // Fallback to Supabase
    if (_supabaseClient != null) {
      try {
        final response = await _supabaseClient!
            .from('professions')
            .select()
            .eq('id', id)
            .single();
        response['field_count'] = 0;
        return Profession.fromJson(response);
      } catch (e) {
        debugPrint('UnifiedRepository: Failed to fetch profession from Supabase - $e');
      }
    }

    return null;
  }

  /// สร้างอาชีพใหม่ - เขียนไปทั้ง 2 ที่
  Future<Profession?> createProfession({
    required String name,
    String? nameEn,
    String? description,
    String? iconName,
    required UserCategory category,
    bool requiresVerification = true,
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
      'display_order': 999,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    Profession? created;

    // Write to Supabase first (if available) to get UUID
    if (_supabaseClient != null) {
      try {
        final response = await _supabaseClient!
            .from('professions')
            .insert(data)
            .select()
            .single();
        response['field_count'] = 0;
        created = Profession.fromJson(response);
        data['id'] = created.id; // Use Supabase-generated ID
      } catch (e) {
        debugPrint('UnifiedRepository: Failed to create in Supabase - $e');
      }
    }

    // Write to Local
    try {
      final localData = Map<String, dynamic>.from(data);
      if (created != null) {
        localData['id'] = created.id;
      }
      
      await http.post(
        Uri.parse('$_localApiUrl/api/professions'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(localData),
      );

      // If Supabase failed, queue for later
      if (created == null && _supabaseConfigured) {
        _offlineQueue.add(_PendingOperation(
          table: 'professions',
          operation: 'insert',
          data: localData,
        ));
      }
    } catch (e) {
      debugPrint('UnifiedRepository: Failed to create in local - $e');
    }

    return created;
  }

  // =====================================================
  // REGISTRATION FIELDS
  // =====================================================

  /// ดึง fields ของอาชีพ
  Future<List<RegistrationFieldConfig>> getFieldConfigsForProfession(String professionId) async {
    // Try local first
    try {
      final response = await http.get(
        Uri.parse('$_localApiUrl/api/professions/$professionId/fields'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.map((json) {
          return RegistrationFieldConfig.fromJson({
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
          });
        }).toList();
      }
    } catch (e) {
      debugPrint('UnifiedRepository: Failed to fetch fields from local - $e');
    }

    // Fallback to Supabase
    if (_supabaseClient != null) {
      try {
        final response = await _supabaseClient!
            .from('registration_field_configs')
            .select()
            .eq('profession_id', professionId)
            .eq('is_active', true)
            .order('field_order');
        return (response as List)
            .map((e) => RegistrationFieldConfig.fromJson(e))
            .toList();
      } catch (e) {
        debugPrint('UnifiedRepository: Failed to fetch fields from Supabase - $e');
      }
    }

    return [];
  }

  // =====================================================
  // REGISTRATION APPLICATIONS
  // =====================================================

  /// ดึงใบสมัครรอตรวจสอบ
  Future<List<RegistrationApplication>> getPendingApplications() async {
    // Try local first
    try {
      final response = await http.get(
        Uri.parse('$_localApiUrl/api/applications?status=pending'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.map((json) => _convertApplicationJson(json)).toList();
      }
    } catch (e) {
      debugPrint('UnifiedRepository: Failed to fetch applications from local - $e');
    }

    // Fallback to Supabase
    if (_supabaseClient != null) {
      try {
        final response = await _supabaseClient!
            .from('registration_applications')
            .select('*, profession:professions(*)')
            .eq('status', 'pending')
            .order('created_at', ascending: false);
        return (response as List)
            .map((e) => RegistrationApplication.fromJson(e))
            .toList();
      } catch (e) {
        debugPrint('UnifiedRepository: Failed to fetch applications from Supabase - $e');
      }
    }

    return [];
  }

  /// สร้างใบสมัคร
  Future<RegistrationApplication?> createApplication({
    required String userId,
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
      'user_id': userId,
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

    RegistrationApplication? created;

    // Write to Supabase first
    if (_supabaseClient != null) {
      try {
        final response = await _supabaseClient!
            .from('registration_applications')
            .insert(data)
            .select()
            .single();
        created = RegistrationApplication.fromJson(response);
      } catch (e) {
        debugPrint('UnifiedRepository: Failed to create application in Supabase - $e');
      }
    }

    // Write to Local
    try {
      await http.post(
        Uri.parse('$_localApiUrl/api/applications'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'professionId': professionId,
          'firstName': firstName,
          'lastName': lastName,
          'username': username,
          'phone': phone,
          'profileImageUrl': profileImageUrl,
          'registrationData': registrationData,
        }),
      );
    } catch (e) {
      debugPrint('UnifiedRepository: Failed to create application in local - $e');
    }

    return created;
  }

  /// อนุมัติใบสมัคร
  Future<void> approveApplication(String applicationId, {String? note}) async {
    // Write to both
    if (_supabaseClient != null) {
      try {
        final now = DateTime.now();
        await _supabaseClient!.from('registration_applications').update({
          'status': 'approved',
          'review_note': note,
          'reviewed_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        }).eq('id', applicationId);
      } catch (e) {
        debugPrint('UnifiedRepository: Failed to approve in Supabase - $e');
      }
    }

    try {
      await http.post(
        Uri.parse('$_localApiUrl/api/applications/$applicationId/approve'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'note': note}),
      );
    } catch (e) {
      debugPrint('UnifiedRepository: Failed to approve in local - $e');
    }
  }

  /// ปฏิเสธใบสมัคร
  Future<void> rejectApplication(String applicationId, {required String note}) async {
    // Write to both
    if (_supabaseClient != null) {
      try {
        final now = DateTime.now();
        await _supabaseClient!.from('registration_applications').update({
          'status': 'rejected',
          'review_note': note,
          'reviewed_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        }).eq('id', applicationId);
      } catch (e) {
        debugPrint('UnifiedRepository: Failed to reject in Supabase - $e');
      }
    }

    try {
      await http.post(
        Uri.parse('$_localApiUrl/api/applications/$applicationId/reject'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'note': note}),
      );
    } catch (e) {
      debugPrint('UnifiedRepository: Failed to reject in local - $e');
    }
  }

  // =====================================================
  // SYNC METHODS
  // =====================================================

  /// Sync professions from Supabase to Local
  Future<void> _syncProfessionsFromSupabase() async {
    if (_supabaseClient == null) return;

    try {
      _syncStatusController.add(SyncStatus.syncing);

      final response = await _supabaseClient!
          .from('professions')
          .select()
          .eq('is_active', true);

      await http.post(
        Uri.parse('$_localApiUrl/api/professions/sync'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'data': response}),
      );

      _syncStatusController.add(SyncStatus.idle);
      debugPrint('UnifiedRepository: Synced ${(response as List).length} professions');
    } catch (e) {
      _syncStatusController.add(SyncStatus.error);
      debugPrint('UnifiedRepository: Failed to sync professions - $e');
    }
  }

  /// Process offline queue
  Future<void> _processOfflineQueue() async {
    if (_offlineQueue.isEmpty || _isSyncing) return;
    if (_supabaseClient == null) return;

    _isSyncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    final operations = List<_PendingOperation>.from(_offlineQueue);
    _offlineQueue.clear();

    for (final op in operations) {
      try {
        switch (op.operation) {
          case 'insert':
            await _supabaseClient!.from(op.table).insert(op.data);
            break;
          case 'update':
            await _supabaseClient!.from(op.table).update(op.data).eq('id', op.data['id']);
            break;
          case 'delete':
            await _supabaseClient!.from(op.table).delete().eq('id', op.data['id']);
            break;
        }
      } catch (e) {
        // Re-queue failed operations
        _offlineQueue.add(op);
        debugPrint('UnifiedRepository: Failed to process operation - $e');
      }
    }

    _isSyncing = false;
    _syncStatusController.add(SyncStatus.idle);
  }

  /// Force full sync
  Future<void> forceFullSync() async {
    await _syncProfessionsFromSupabase();
    // Add more tables as needed
  }

  // =====================================================
  // HELPERS
  // =====================================================

  RegistrationApplication _convertApplicationJson(Map<String, dynamic> json) {
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

  void dispose() {
    _syncTimer?.cancel();
    _syncStatusController.close();
  }
}

/// Sync Status
enum SyncStatus {
  idle,
  syncing,
  error,
}

/// Pending Operation for offline queue
class _PendingOperation {
  final String table;
  final String operation;
  final Map<String, dynamic> data;

  _PendingOperation({
    required this.table,
    required this.operation,
    required this.data,
  });
}
