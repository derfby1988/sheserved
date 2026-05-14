import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/consultation_request_model.dart';
import 'package:sheserved/config/app_config.dart';

class ConsultationRepository {
  final SupabaseClient _client;

  ConsultationRepository(this._client);

  /// Create a new consultation request with child symptoms
  Future<ConsultationRequestModel> createRequest({
    required String userId,
    String? packageId,
    required String packageName,
    required double price,
    Map<String, dynamic> bodyArea = const {},
    Map<String, dynamic> symptomsChart = const {},
    List<SymptomPoint> symptoms = const [],
  }) async {
    final now = DateTime.now();
    final data = {
      'user_id': userId,
      'package_id': packageId,
      'package_name': packageName,
      'price': price,
      'body_area': bodyArea,
      'symptoms_chart': symptomsChart,
      'status': 'pending',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    // 1. Insert parent request
    final parentResponse = await _client
        .from('consultation_requests')
        .insert(data)
        .select()
        .single();
    
    final String requestId = parentResponse['id'];

    // 2. Insert child symptoms if any
    if (symptoms.isNotEmpty) {
      final symptomsData = symptoms.map((s) => s.toJson(requestId)).toList();
      await _client.from('consultation_symptoms').insert(symptomsData);
    }

    // Return the model with symptoms populated
    final fullData = Map<String, dynamic>.from(parentResponse);
    fullData['symptoms'] = symptoms.map((s) => {
      'region_id': s.regionId,
      'side': s.side,
      'symptom': s.symptom,
      'display_label': s.displayLabel,
    }).toList();
    
    return ConsultationRequestModel.fromJson(fullData);
  }

  /// Get consultation requests for a user including symptoms
  Future<List<ConsultationRequestModel>> getUserRequests(String userId) async {
    final response = await _client
        .from('consultation_requests')
        .select('*, symptoms:consultation_symptoms(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((e) => ConsultationRequestModel.fromJson(e))
        .toList();
  }

  /// Update consultation request
  Future<ConsultationRequestModel> updateRequest(String id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    final response = await _client
        .from('consultation_requests')
        .update(data)
        .eq('id', id)
        .select('*, symptoms:consultation_symptoms(*)')
        .single();
    return ConsultationRequestModel.fromJson(response);
  }

  /// Stream ALL consultation requests — for expert/admin dashboard
  Future<List<Map<String, dynamic>>> getAllRequestsWithUserInfo() async {
    try {
      final response = await _client
          .from('consultation_requests')
          .select('''
            id, user_id, package_id, package_name, price,
            body_area, symptoms_chart, status, created_at, updated_at,
            provider_id,
            symptoms:consultation_symptoms(*),
            users:user_id (first_name, last_name, profile_image_url)
          ''')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('ConsultationRepository.getAllRequestsWithUserInfo error: $e');
      return [];
    }
  }

  /// Stream ALL consultation requests — for expert/admin dashboard
  Stream<List<Map<String, dynamic>>> watchAllRequestsWithUserInfo() {
    return _client
        .from('consultation_requests')
        .stream(primaryKey: ['id'])
        .asyncMap((_) => getAllRequestsWithUserInfo());
  }

  /// ดึงคำขอเฉพาะแพ็คเกจที่ตรงกับ professionId ของ provider
  /// กรองด้วย package_id ที่กลุ่มอาชีพต้องรับผิดชอบ
  Future<List<Map<String, dynamic>>> getRequestsForProfession(
      List<String> packageIds) async {
    try {
      final selectFields = '''
      id, user_id, package_id, package_name, price,
      body_area, symptoms_chart, status, created_at, updated_at,
      provider_id,
      symptoms:consultation_symptoms(*),
      users:user_id (first_name, last_name, profile_image_url)
    ''';

      // Apply in_() filter BEFORE .order() to stay on PostgrestFilterBuilder
      final response = packageIds.isNotEmpty
          ? await _client
              .from('consultation_requests')
              .select(selectFields)
              .inFilter('package_id', packageIds)
              .order('created_at', ascending: false)
              .timeout(const Duration(seconds: 10))
          : await _client
              .from('consultation_requests')
              .select(selectFields)
              .order('created_at', ascending: false)
              .timeout(const Duration(seconds: 10));

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('getRequestsForProfession error: $e');
      return [];
    }
  }

  /// Stream real-time คำขอ เฉพาะกลุ่มอาชีพที่ระบุ
  Stream<List<Map<String, dynamic>>> watchRequestsForProfession(
      List<String> packageIds) {
    return _client
        .from('consultation_requests')
        .stream(primaryKey: ['id'])
        .asyncMap((_) => getRequestsForProfession(packageIds));
  }

  /// ดึง packageId ทั้งหมดที่ตรงกับ professionId
  Future<List<String>> getPackageIdsForProfession(String professionId) async {
    try {
      // 1. Fetch the actual profession name/key to match legacy roles like 'doctor', 'pharmacist'
      String professionName = '';
      try {
        final profResponse = await _client
            .from('professions')
            .select('name')
            .eq('id', professionId)
            .maybeSingle();
        if (profResponse != null) {
          professionName = profResponse['name']?.toString().toLowerCase() ?? '';
        }
      } catch (e) {
        debugPrint('getPackageIdsForProfession: failed to get profession name: $e');
      }

      // 2. Fetch all active packages
      final response = await _client
          .from('consultation_packages')
          .select('id, name, expert_groups')
          .eq('is_active', true)
          .timeout(const Duration(seconds: 10));

      final List<String> matchedIds = [];
      for (final row in response) {
        final groups = row['expert_groups'];
        if (groups is List) {
          final hasMatch = groups.any((g) {
            if (g is! Map) return false;
            final gMap = g;
            
            // Match by ID (UUID)
            final idMatch = gMap['role'] == professionId ||
                gMap['id'] == professionId ||
                gMap['profession_id'] == professionId;
            
            if (idMatch) return true;

            // Match by Name/Role string (Case-insensitive)
            // e.g. "doctor" matches user with profession named "แพทย์" or "หมอ"
            final role = gMap['role']?.toString().toLowerCase() ?? '';
            if (role.isEmpty) return false;

            if (professionName.isNotEmpty) {
              // Legacy role matching
              if (role == 'doctor' && (professionName.contains('หมอ') || professionName.contains('แพทย์'))) return true;
              if (role == 'pharmacist' && professionName.contains('เภสัช')) return true;
              if (role == 'specialist' && professionName.contains('เฉพาะทาง')) return true;
              if (role == 'professor' && professionName.contains('อาจารย์')) return true;
              
              // Direct name match
              if (professionName.contains(role) || role.contains(professionName)) return true;
            }
            
            return false;
          });
          
          if (hasMatch) {
            matchedIds.add(row['id'] as String);
          }
        }
      }
      
      // Log for debugging
      debugPrint('ConsultationRepo: Profession ($professionId : $professionName) matched packages: $matchedIds');
      
      // Fallback: If no specific match, for safety in dev, return all or empty?
      // For now, return all if empty to avoid empty dashboard during setup, 
      // but only if profession is valid.
      return matchedIds;
    } catch (e) {
      debugPrint('getPackageIdsForProfession error: $e');
      return [];
    }
  }

  /// Provider รับงาน: อัปเดตสถานะ request → in_progress และบันทึก provider_id (ระบบเดิม)
  Future<void> assignProvider({
    required String requestId,
    required String providerId,
  }) async {
    await _client.from('consultation_requests').update({
      'status': 'in_progress',
      'provider_id': providerId,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', requestId);
  }

  /// Provider รับงาน: เข้าร่วม Expert Group (ระบบใหม่ Phase 1 ป้องกัน Race Condition)
  Future<void> assignProviderToGroup({
    required String consultationId,
    required String providerId,
    required String packageId,
    required String professionId,
  }) async {
    // 1. ดึงข้อมูล expert_groups ของแพ็คเกจ
    final pkgRes = await _client
        .from('consultation_packages')
        .select('expert_groups')
        .eq('id', packageId)
        .maybeSingle();
        
    final expertGroups = (pkgRes?['expert_groups'] as List<dynamic>?) ?? [];

    // 2. ดึงชื่อ profession เพื่อใช้เทียบ (กรณีเทียบด้วย role string)
    final profRes = await _client
        .from('professions')
        .select('name')
        .eq('id', professionId)
        .maybeSingle();
    final professionName = (profRes?['name'] as String?)?.toLowerCase() ?? '';

    // 3. ค้นหา expert_group_id ที่ตรงกับวิชาชีพ
    String? matchedExpertGroupId;
    for (var g in expertGroups) {
      if (g is Map<String, dynamic>) {
        final idMatch = g['role'] == professionId ||
            g['id'] == professionId ||
            g['profession_id'] == professionId;

        if (idMatch) {
          matchedExpertGroupId = g['id'] as String?;
          break;
        }

        final role = g['role']?.toString().toLowerCase() ?? '';
        if (role.isNotEmpty && professionName.isNotEmpty) {
          if (role == 'doctor' && (professionName.contains('หมอ') || professionName.contains('แพทย์'))) {
            matchedExpertGroupId = g['id'] as String?; break;
          }
          if (role == 'pharmacist' && professionName.contains('เภสัช')) {
            matchedExpertGroupId = g['id'] as String?; break;
          }
          if (role == 'specialist' && professionName.contains('เฉพาะทาง')) {
            matchedExpertGroupId = g['id'] as String?; break;
          }
          if (role == 'professor' && professionName.contains('อาจารย์')) {
            matchedExpertGroupId = g['id'] as String?; break;
          }
          if (professionName.contains(role) || role.contains(professionName)) {
            matchedExpertGroupId = g['id'] as String?; break;
          }
        }
      }
    }

    if (matchedExpertGroupId == null) {
      throw Exception('ไม่พบกลุ่มผู้เชี่ยวชาญที่ตรงกับวิชาชีพของคุณในแพ็คเกจนี้');
    }

    // 4. เรียก RPC ด้วย expertGroupId ที่หามาได้
    final response = await _client.rpc(
      'assign_provider_to_group',
      params: {
        'p_consultation_id': consultationId,
        'p_provider_id': providerId,
        'p_expert_group_id': matchedExpertGroupId,
      },
    );

    // หาก RPC รีเทิร์นค่าที่แปลว่าไม่สำเร็จ (เช่น โควต้าเต็ม)
    if (response is Map && response['success'] == false) {
      throw Exception(response['message'] ?? 'โควต้ากลุ่มนี้เต็มแล้ว');
    }
  }

  /// Provider สละสิทธิ์: คืนโควต้าให้แพทย์อื่น
  Future<void> abandonProviderFromGroup({
    required String consultationId,
    required String providerId,
  }) async {
    final response = await _client.rpc(
      'abandon_provider_from_group',
      params: {
        'p_consultation_id': consultationId,
        'p_provider_id': providerId,
      },
    );

    if (response is Map && response['success'] == false) {
      throw Exception(response['message'] ?? 'สละสิทธิ์ไม่สำเร็จ');
    }
  }

  /// Update status of a consultation request
  Future<void> updateStatus(String requestId, String status) async {
    await _client
        .from('consultation_requests')
        .update({
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', requestId);
  }

  /// Get statistics for organ usage frequency
  Future<Map<String, int>> getSymptomStatistics() async {
    try {
      // Fetch only region_id from consultation_symptoms
      final List<dynamic> response = await _client
          .from('consultation_symptoms')
          .select('region_id');

      final Map<String, int> stats = {};
      for (var row in response) {
        final String? regionId = row['region_id'];
        if (regionId != null) {
          stats[regionId] = (stats[regionId] ?? 0) + 1;
        }
      }
      return stats;
    } catch (e) {
      debugPrint('Error fetching symptom stats: $e');
      return {};
    }
  }

  /// Get total count of active consultation requests (recipients)
  Future<int> getActiveRecipientCount() async {
    try {
      final response = await _client
          .from('consultation_requests')
          .select('id')
          .inFilter('status', ['pending', 'in_progress'])
          .count(CountOption.exact);
      
      return response.count ?? 0;
    } catch (e) {
      debugPrint('getActiveRecipientCount error: $e');
      return 0;
    }
  }

  /// Stream active recipient count
  Stream<int> watchActiveRecipientCount() {
    return _client
        .from('consultation_requests')
        .stream(primaryKey: ['id'])
        .asyncMap((_) => getActiveRecipientCount());
  }
}

