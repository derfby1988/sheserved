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
            symptoms:consultation_symptoms(*),
            users:user_id (first_name, last_name, profile_image_url)
          ''')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
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
      final String selectFields = '''
            id, user_id, package_id, package_name, price,
            body_area, symptoms_chart, status, created_at, updated_at,
            provider_id,
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
      // ดึง packages ทั้งหมดที่ active
      final response = await _client
          .from('consultation_packages')
          .select('id, expert_groups')
          .eq('is_active', true);

      final List<String> matchedIds = [];
      for (final row in response) {
        final groups = row['expert_groups'];
        if (groups is List) {
          // ตรวจว่า expert_groups มี professionId นั้นหรือเปล่า
          final hasMatch = groups.any((g) {
            final gMap = g as Map<String, dynamic>;
            return gMap['id'] == professionId ||
                gMap['profession_id'] == professionId;
          });
          if (hasMatch) {
            matchedIds.add(row['id'] as String);
          }
        }
      }
      // ถ้าไม่มี expert_groups match เลย = provider นี้รับทุก packages
      return matchedIds.isEmpty
          ? (response as List).map((r) => r['id'] as String).toList()
          : matchedIds;
    } catch (e) {
      debugPrint('getPackageIdsForProfession error: $e');
      return [];
    }
  }

  /// Provider รับงาน: อัปเดตสถานะ request → in_progress และบันทึก provider_id
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
}

