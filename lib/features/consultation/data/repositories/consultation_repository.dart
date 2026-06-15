import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
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
    String? status,
  }) async {
    final authToken = Supabase.instance.client.auth.currentSession?.accessToken;
    final data = {
      'userId': userId,
      'user_id': userId,
      'packageId': packageId,
      'package_id': packageId,
      'packageName': packageName,
      'package_name': packageName,
      'price': price,
      'body_area': bodyArea,
      'symptoms_chart': symptomsChart,
      'status': status ?? 'pending',
      'symptoms': symptoms
          .map(
            (s) => {
              'region_id': s.regionId,
              'side': s.side,
              'symptom': s.symptom,
              'display_label': s.displayLabel,
            },
          )
          .toList(),
    };

    final response = await http.post(
      Uri.parse('${AppConfig.localApiUrl}/api/consultations/requests'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'x-user-id': userId,
        if (authToken != null) 'Authorization': 'Bearer $authToken',
        'x-idempotency-key':
            'consultation-${sha256.convert(utf8.encode(jsonEncode(data))).toString()}',
      },
      body: jsonEncode(data),
    );

    if (response.statusCode != 202 &&
        response.statusCode != 200 &&
        response.statusCode != 201) {
      throw Exception(
        'Failed to submit consultation request: ${response.statusCode} ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final requestJson = Map<String, dynamic>.from(
      payload['consultationRequest'] as Map? ?? payload,
    );

    if (payload['roomId'] != null && requestJson['room_id'] == null) {
      requestJson['room_id'] = payload['roomId'];
    }

    return ConsultationRequestModel.fromJson(requestJson);
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
  Future<ConsultationRequestModel> updateRequest(
    String id,
    Map<String, dynamic> data,
  ) async {
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
  /// [excludeProviderId] ถ้าระบุ → กรองรายการที่ provider นั้นเคย dismiss ออก
  Future<List<Map<String, dynamic>>> getAllRequestsWithUserInfo({
    String? excludeProviderId,
  }) async {
    try {
      var query = _client.from('consultation_requests').select('''
            id, user_id, package_id, package_name, price,
            body_area, symptoms_chart, status, created_at, updated_at,
            provider_id,
            symptoms:consultation_symptoms(*),
            users:user_id (first_name, last_name, profile_image_url)
          ''');

      if (excludeProviderId != null && excludeProviderId.isNotEmpty) {
        query = query.not(
          'dismissed_by_provider_ids',
          'cs',
          '{$excludeProviderId}',
        );
      }

      final response = await query
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('ConsultationRepository.getAllRequestsWithUserInfo error: $e');
      return [];
    }
  }

  /// Stream ALL consultation requests — for expert/admin dashboard
  Stream<List<Map<String, dynamic>>> watchAllRequestsWithUserInfo({
    String? excludeProviderId,
  }) {
    return _client
        .from('consultation_requests')
        .stream(primaryKey: ['id'])
        .asyncMap(
          (_) =>
              getAllRequestsWithUserInfo(excludeProviderId: excludeProviderId),
        );
  }

  /// ดึงคำขอเฉพาะแพ็คเกจที่ตรงกับ professionId ของ provider
  /// กรองด้วย package_id ที่กลุ่มอาชีพต้องรับผิดชอบ
  /// [excludeProviderId] ถ้าระบุ → กรองรายการที่ provider นั้นเคย dismiss ออก
  Future<List<Map<String, dynamic>>> getRequestsForProfession(
    List<String> packageIds, {
    String? excludeProviderId,
  }) async {
    try {
      final selectFields = '''
      id, user_id, package_id, package_name, price,
      body_area, symptoms_chart, status, created_at, updated_at,
      provider_id,
      symptoms:consultation_symptoms(*),
      users:user_id (first_name, last_name, profile_image_url)
    ''';

      // Build query step-by-step to allow PostgrestFilterBuilder chain
      var query = _client.from('consultation_requests').select(selectFields);

      if (packageIds.isNotEmpty) {
        query = query.inFilter('package_id', packageIds);
      }

      if (excludeProviderId != null && excludeProviderId.isNotEmpty) {
        query = query.not(
          'dismissed_by_provider_ids',
          'cs',
          '{$excludeProviderId}',
        );
      }

      final response = await query
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
    List<String> packageIds, {
    String? excludeProviderId,
  }) {
    return _client
        .from('consultation_requests')
        .stream(primaryKey: ['id'])
        .asyncMap(
          (_) => getRequestsForProfession(
            packageIds,
            excludeProviderId: excludeProviderId,
          ),
        );
  }

  // ============================================================
  // 🆕 Per-Tab Pagination Methods
  // ============================================================

  /// ดึงคำขอแบบกรอง status + pagination ที่ฝั่ง DB
  /// [status] เป็น null หรือ 'all' = ไม่กรอง status
  /// [packageIds] ถ้ามี = กรองเฉพาะ package ที่ตรงกับ provider
  Future<List<Map<String, dynamic>>> getRequestsByStatus({
    String? status,
    int page = 0,
    int pageSize = 15,
    List<String>? packageIds,
  }) async {
    try {
      final selectFields = '''
      id, user_id, package_id, package_name, price,
      body_area, symptoms_chart, status, created_at, updated_at,
      provider_id,
      symptoms:consultation_symptoms(*),
      users:user_id (first_name, last_name, profile_image_url)
    ''';

      var query = _client.from('consultation_requests').select(selectFields);

      // กรอง status ที่ DB (ถ้าไม่ใช่ 'all')
      if (status != null && status != 'all') {
        query = query.eq('status', status);
      }

      // กรอง package สำหรับ provider
      if (packageIds != null && packageIds.isNotEmpty) {
        query = query.inFilter('package_id', packageIds);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1)
          .timeout(const Duration(seconds: 10));

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('getRequestsByStatus error: $e');
      return [];
    }
  }

  /// ดึงจำนวนรายการต่อ status สำหรับแสดงบน stat chips
  /// [packageIds] ถ้ามี = นับเฉพาะ package ที่ตรงกับ provider
  Future<Map<String, int>> getStatusCounts({List<String>? packageIds}) async {
    final counts = <String, int>{
      'all': 0,
      'pending': 0,
      'in_progress': 0,
      'completed': 0,
    };

    try {
      // นับ 'all'
      var allQuery = _client.from('consultation_requests').select('id');
      if (packageIds != null && packageIds.isNotEmpty) {
        allQuery = allQuery.inFilter('package_id', packageIds);
      }
      final allRes = await allQuery.count(CountOption.exact);
      counts['all'] = allRes.count ?? 0;

      // นับแต่ละ status
      for (final s in ['pending', 'in_progress', 'completed']) {
        var q = _client
            .from('consultation_requests')
            .select('id')
            .eq('status', s);
        if (packageIds != null && packageIds.isNotEmpty) {
          q = q.inFilter('package_id', packageIds);
        }
        final res = await q.count(CountOption.exact);
        counts[s] = res.count ?? 0;
      }
    } catch (e) {
      debugPrint('getStatusCounts error: $e');
    }

    return counts;
  }

  /// Get consultation history for a specific provider
  Future<List<ConsultationRequestModel>> getProviderHistory(
    String providerId,
  ) async {
    final response = await _client
        .from('consultation_requests')
        .select('*, symptoms:consultation_symptoms(*)')
        .eq('provider_id', providerId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((e) => ConsultationRequestModel.fromJson(e))
        .toList();
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
        debugPrint(
          'getPackageIdsForProfession: failed to get profession name: $e',
        );
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
            final idMatch =
                gMap['role'] == professionId ||
                gMap['id'] == professionId ||
                gMap['profession_id'] == professionId;

            if (idMatch) return true;

            // Match by Name/Role string (Case-insensitive)
            // e.g. "doctor" matches user with profession named "แพทย์" or "หมอ"
            final role = gMap['role']?.toString().toLowerCase() ?? '';
            if (role.isEmpty) return false;

            if (professionName.isNotEmpty) {
              // Legacy role matching
              if (role == 'doctor' &&
                  (professionName.contains('หมอ') ||
                      professionName.contains('แพทย์')))
                return true;
              if (role == 'pharmacist' && professionName.contains('เภสัช'))
                return true;
              if (role == 'specialist' && professionName.contains('เฉพาะทาง'))
                return true;
              if (role == 'professor' && professionName.contains('อาจารย์'))
                return true;

              // Direct name match
              if (professionName.contains(role) ||
                  role.contains(professionName))
                return true;
            }

            return false;
          });

          if (hasMatch) {
            matchedIds.add(row['id'] as String);
          }
        }
      }

      // Log for debugging
      debugPrint(
        'ConsultationRepo: Profession ($professionId : $professionName) matched packages: $matchedIds',
      );

      // Fallback: If no specific match, for safety in dev, return all or empty?
      // For now, return all if empty to avoid empty dashboard during setup,
      // but only if profession is valid.
      return matchedIds;
    } catch (e) {
      debugPrint('getPackageIdsForProfession error: $e');
      return [];
    }
  }

  /// Provider ปัด/ปฏิเสธคำขอปรึกษา → เพิ่ม provider ID เข้า dismissed_by_provider_ids
  Future<void> dismissRequestForProvider({
    required String requestId,
    required String providerId,
  }) async {
    try {
      // ดึงค่าปัจจุบันก่อน (ป้องกัน race condition แบบง่าย)
      final res = await _client
          .from('consultation_requests')
          .select('dismissed_by_provider_ids')
          .eq('id', requestId)
          .single();

      final current =
          (res['dismissed_by_provider_ids'] as List?)?.cast<String>() ?? [];
      if (!current.contains(providerId)) {
        current.add(providerId);
        await _client
            .from('consultation_requests')
            .update({
              'dismissed_by_provider_ids': current,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', requestId);
      }
    } catch (e) {
      debugPrint('dismissRequestForProvider error: $e');
      rethrow;
    }
  }

  /// Provider รับงาน: อัปเดตสถานะ request → in_progress และบันทึก provider_id (ระบบเดิม)
  Future<void> assignProvider({
    required String requestId,
    required String providerId,
  }) async {
    await _client
        .from('consultation_requests')
        .update({
          'status': 'in_progress',
          'provider_id': providerId,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', requestId);
  }

  /// Ensure consultation_room_experts rows exist for a consultation.
  /// ใช้ RPC ensure_room_experts (SECURITY DEFINER) เพื่อ bypass RLS
  Future<void> ensureRoomExperts({
    required String consultationId,
    required String packageId,
    String? roomId,
  }) async {
    try {
      await _client.rpc(
        'ensure_room_experts',
        params: {
          'p_consultation_id': consultationId,
          'p_package_id': packageId,
          'p_room_id': roomId,
        },
      );
      debugPrint('ensureRoomExperts: RPC succeeded for $consultationId');
    } catch (e) {
      debugPrint('ensureRoomExperts error: $e');
      // Non-fatal: fallbacks in UI will handle it
    }
  }

  /// Provider รับงาน: sync provider เข้า consultation_room_experts หลังจาก assignProvider (ระบบเก่า)
  /// ใช้ RPC sync_provider_to_room_experts (SECURITY DEFINER) เพื่อ bypass RLS
  Future<void> syncProviderToRoomExperts({
    required String consultationId,
    required String providerId,
    String? professionId,
  }) async {
    try {
      await _client.rpc(
        'sync_provider_to_room_experts',
        params: {
          'p_consultation_id': consultationId,
          'p_provider_id': providerId,
          'p_profession_id': professionId,
        },
      );
      debugPrint(
        'syncProviderToRoomExperts: RPC succeeded for consultationId=$consultationId providerId=$providerId',
      );
    } catch (e) {
      debugPrint('syncProviderToRoomExperts error: $e');
      // Non-fatal: banner may show waiting instead of joined
    }
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
        final idMatch =
            g['role'] == professionId ||
            g['id'] == professionId ||
            g['profession_id'] == professionId;

        if (idMatch) {
          matchedExpertGroupId = g['id'] as String?;
          break;
        }

        final role = g['role']?.toString().toLowerCase() ?? '';
        if (role.isNotEmpty && professionName.isNotEmpty) {
          if (role == 'doctor' &&
              (professionName.contains('หมอ') ||
                  professionName.contains('แพทย์'))) {
            matchedExpertGroupId = g['id'] as String?;
            break;
          }
          if (role == 'pharmacist' && professionName.contains('เภสัช')) {
            matchedExpertGroupId = g['id'] as String?;
            break;
          }
          if (role == 'specialist' && professionName.contains('เฉพาะทาง')) {
            matchedExpertGroupId = g['id'] as String?;
            break;
          }
          if (role == 'professor' && professionName.contains('อาจารย์')) {
            matchedExpertGroupId = g['id'] as String?;
            break;
          }
          if (professionName.contains(role) || role.contains(professionName)) {
            matchedExpertGroupId = g['id'] as String?;
            break;
          }
        }
      }
    }

    if (matchedExpertGroupId == null) {
      throw Exception(
        'ไม่พบกลุ่มผู้เชี่ยวชาญที่ตรงกับวิชาชีพของคุณในแพ็คเกจนี้',
      );
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

  /// ตรวจสอบว่า provider มี consultation ที่ in_progress อยู่หรือไม่
  /// ใช้สำหรับ safety net: ถ้า busy แต่ไม่มีงาน → reset เป็น online
  Future<bool> hasActiveInProgressConsultation(String providerId) async {
    try {
      final response = await _client
          .from('consultation_requests')
          .select('id')
          .eq('provider_id', providerId)
          .eq('status', 'in_progress')
          .limit(1);
      return (response as List).isNotEmpty;
    } catch (e) {
      debugPrint('hasActiveInProgressConsultation error: $e');
      return false;
    }
  }

  /// นับจำนวน consultation ที่ provider กำลังทำอยู่ (in_progress)
  /// ใช้สำหรับแสดง banner + จำกัดจำนวนงานพร้อมกัน
  Future<int> getActiveInProgressConsultationCount(String providerId) async {
    try {
      final response = await _client
          .from('consultation_requests')
          .select('id')
          .eq('provider_id', providerId)
          .eq('status', 'in_progress')
          .count(CountOption.exact);
      return response.count ?? 0;
    } catch (e) {
      debugPrint('getActiveInProgressConsultationCount error: $e');
      return 0;
    }
  }

  /// ดึงรายการ consultation ที่ provider กำลังทำอยู่ (in_progress)
  /// ใช้สำหรับแสดงรายละเอียดใน banner
  Future<List<Map<String, dynamic>>> getActiveInProgressConsultations(
    String providerId,
  ) async {
    try {
      final response = await _client
          .from('consultation_requests')
          .select('id, package_name, patient:user_id (first_name, last_name), created_at')
          .eq('provider_id', providerId)
          .eq('status', 'in_progress')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('getActiveInProgressConsultations error: $e');
      return [];
    }
  }

  /// Mark expert ว่าเสร็จงานแล้ว คืนค่าว่าทุกคนเสร็จหรือยัง
  /// ใช้ RPC mark_expert_finished (SECURITY DEFINER)
  Future<Map<String, dynamic>> markExpertFinished(
    String consultationId,
    String providerId,
  ) async {
    try {
      final response = await _client.rpc(
        'mark_expert_finished',
        params: {
          'p_consultation_id': consultationId,
          'p_provider_id': providerId,
        },
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('markExpertFinished error: $e');
      rethrow;
    }
  }

  /// ดึงสถานะการเสร็จงานของ experts ทั้งหมดใน consultation
  Future<Map<String, dynamic>> getExpertCompletionStatus(
    String consultationId,
  ) async {
    try {
      final response = await _client.rpc(
        'get_expert_completion_status',
        params: {'p_consultation_id': consultationId},
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('getExpertCompletionStatus error: $e');
      return {
        'total_count': 0,
        'finished_count': 0,
        'remaining_count': 0,
        'all_finished': false,
        'experts': [],
      };
    }
  }

  /// บันทึกว่า expert ออกจากห้องแชท (ไปหน้าอื่น)
  Future<Map<String, dynamic>> markExpertLeft(
    String consultationId,
    String providerId,
  ) async {
    try {
      final response = await _client.rpc(
        'mark_expert_left',
        params: {
          'p_consultation_id': consultationId,
          'p_provider_id': providerId,
        },
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('markExpertLeft error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// บันทึกว่า expert กลับเข้าห้องแชท
  Future<Map<String, dynamic>> markExpertReentered(
    String consultationId,
    String providerId,
  ) async {
    try {
      final response = await _client.rpc(
        'mark_expert_reentered',
        params: {
          'p_consultation_id': consultationId,
          'p_provider_id': providerId,
        },
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('markExpertReentered error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// ยกเลิกสถานะจบงานของ expert (revert finished_at)
  Future<Map<String, dynamic>> markExpertReverted(
    String consultationId,
    String providerId,
  ) async {
    try {
      final response = await _client.rpc(
        'mark_expert_reverted',
        params: {
          'p_consultation_id': consultationId,
          'p_provider_id': providerId,
        },
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('markExpertReverted error: $e');
      rethrow;
    }
  }

  /// ดึงรายการ consultation_id ที่ expert จบงานแล้ว
  Future<Set<String>> getFinishedConsultationIds(String providerId) async {
    try {
      final response = await _client
          .from('consultation_room_experts')
          .select('consultation_id')
          .eq('provider_id', providerId)
          .not('finished_at', 'is', null);
      final list = (response as List).cast<Map<String, dynamic>>();
      return list.map((e) => e['consultation_id'].toString()).toSet();
    } catch (e) {
      debugPrint('getFinishedConsultationIds error: $e');
      return {};
    }
  }
}
