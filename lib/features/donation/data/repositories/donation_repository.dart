import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/donation_models.dart';
import '../../../../services/websocket_service.dart';

/// Repository สำหรับจัดการข้อมูลการบริจาค
class DonationRepository {
  final SupabaseClient _client;

  DonationRepository(this._client);

  /// ดึงข้อมูลฟิลด์พื้นฐานสำหรับทุกคำร้อง (Global Custom Fields)
  Future<List<DonationCategoryField>> getGlobalFields() async {
    try {
      final response = await _client
          .from('app_settings')
          .select('value')
          .eq('key', 'donation_global_fields')
          .maybeSingle();
      
      if (response != null && response['value'] != null) {
        final List valueList = response['value'] as List;
        return valueList.map((json) => DonationCategoryField.fromJson(json)).toList();
      }
    } catch (_) {}

    // คืนค่าเริ่มต้น (Default Fields) หากยังไม่มีในฐานข้อมูล
    return [
      const DonationCategoryField(id: 'title', label: 'หัวข้อคำร้องขอ', type: 'text', isRequired: true),
      const DonationCategoryField(id: 'target_amount', label: 'ยอดเป้าหมาย/จำนวน', type: 'number', isRequired: false),
      const DonationCategoryField(id: 'description', label: 'รายละเอียดเหตุผลความจำเป็น', type: 'long_text', isRequired: true),
      const DonationCategoryField(id: 'community_id', label: 'ชุมชน/พื้นที่', type: 'community_dropdown', isRequired: true),
      const DonationCategoryField(id: 'usage_location', label: 'สถานที่ใช้ความช่วยเหลือ', type: 'text', isRequired: false),
      const DonationCategoryField(id: 'requester_address', label: 'ที่อยู่ผู้ร้องขอ', type: 'address_picker', isRequired: false),
      const DonationCategoryField(id: 'needed_date', label: 'วันที่จำเป็นต้องใช้', type: 'date', isRequired: false),
      const DonationCategoryField(id: 'is_trending', label: 'กำลังยอดนิยม?', type: 'boolean', isRequired: false),
    ];
  }

  /// บันทึกข้อมูลฟิลด์พื้นฐาน
  Future<void> saveGlobalFields(List<DonationCategoryField> fields) async {
    await _client.from('app_settings').upsert({
      'key': 'donation_global_fields',
      'value': fields.map((e) => e.toJson()).toList(),
      'description': 'Global basic fields required for every donation request',
    });
  }

  /// ดึงหมวดหมู่การบริจาคทั้งหมด
  Future<List<DonationCategory>> getCategories() async {
    final response = await _client
        .from('donation_categories')
        .select()
        .order('display_order', ascending: true);
    
    return (response as List)
        .map((json) => DonationCategory.fromJson(json))
        .toList();
  }

  /// ดึงเฉพาะหมวดหมู่สำหรับแจ้งเหตุฉุกเฉิน
  Future<List<DonationCategory>> getEmergencyCategories() async {
    final response = await _client
        .from('donation_categories')
        .select()
        .eq('is_emergency', true)
        .order('display_order', ascending: true);
    
    return (response as List)
        .map((json) => DonationCategory.fromJson(json))
        .toList();
  }

  /// ดึงข้อมูลหมวดหมู่แบบ Real-time (พร้อมระบบ Fallback)
  Stream<List<DonationCategory>> watchCategories() async* {
    // 1. Fetch ทันทีผ่าน HTTP (Guest โหลดได้)
    try {
      yield await getCategories();
    } catch (_) {}

    // 2. ถ้าเป็น Guest (ไม่ได้ Login) ให้หยุดแค่นี้ ไม่ต้องง้อ Realtime
    if (_client.auth.currentUser == null) {
      return;
    }

    // 3. Subscribe Realtime (เฉพาะคนที่ Login)
    try {
      final stream = _client
          .from('donation_categories')
          .stream(primaryKey: ['id'])
          .order('display_order', ascending: true)
          .asyncMap((_) => getCategories());
          
      await for (final data in stream) {
        yield data;
      }
    } catch (e) {
      print('Supabase Realtime Error (watchCategories): $e');
    }
  }

  /// ดึงคำร้องขอการบริจาค (กรองตามหมวดหมู่ได้)
  Future<List<DonationRequest>> getRequests({
    String? categoryId,
    String? userId,
    bool bypassStatusFilter = false,
  }) async {
    try {
      var query = _client.from('donation_requests').select();

      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      if (userId != null) {
        query = query.eq('user_id', userId);
      }

      if (!bypassStatusFilter) {
        query = query.eq('approval_status', DonationApprovalStatus.active.name);
      }

      final response = await query.order('created_at', ascending: false);

      final list = response as List;
      final results = <DonationRequest>[];
      for (int i = 0; i < list.length; i++) {
        try {
          results.add(DonationRequest.fromJson(list[i] as Map<String, dynamic>));
        } catch (e) {
          debugPrint('DonationRepository.getRequests: Error parsing request at index $i: $e');
          // Skip corrupted rows instead of failing the whole query
        }
      }
      return results;
    } catch (e) {
      debugPrint('DonationRepository.getRequests: Query error: $e');
      rethrow;
    }
  }

  /// ✅ ดึงคำร้องทั้งหมดที่ผูกกับวิดีโอ (รองรับหลายคำร้องต่อวิดีโอเดียว)
  /// ถ้า activeOnly = true จะดึงเฉพาะที่สถานะ active (เปิดรับบริจาคแล้ว)
  Future<List<DonationRequest>> getRequestsByVideoId(
    String videoId, {
    bool activeOnly = false,
  }) async {
    var query = _client
        .from('donation_requests')
        .select()
        .eq('video_id', videoId);

    if (activeOnly) {
      query = query.eq('approval_status', DonationApprovalStatus.active.name);
    }

    final response = await query.order('created_at', ascending: true);
    return (response as List)
        .map((json) => DonationRequest.fromJson(json))
        .toList();
  }

  /// ✅ ตรวจสอบว่าอาชีพของผู้ใช้มีสิทธิ์สร้างคำร้องในหมวดหมู่นี้หรือไม่
  /// (ต้องอยู่ใน volunteer_profession_ids ที่แอดมินกำหนด)
  /// คืนค่า null หากมีสิทธิ์, คืนข้อความข้อผิดพลาดหากไม่มีสิทธิ์
  Future<String?> validateVolunteerEligibility(
    String userId,
    String categoryId,
  ) async {
    try {
      // ดึง volunteer_profession_ids ของหมวดหมู่นี้ก่อน
      final catData = await _client
          .from('donation_categories')
          .select('name, volunteer_profession_ids')
          .eq('id', categoryId)
          .maybeSingle();

      if (catData == null) {
        return 'ไม่พบข้อมูลหมวดหมู่การบริจาค';
      }

      final categoryName = catData['name']?.toString() ?? 'หมวดหมู่นี้';
      final volunteerIds = List<String>.from(
          (catData['volunteer_profession_ids'] as List? ?? [])
              .map((e) => e.toString()));

      // ถ้าแอดมินไม่กำหนด volunteer_profession_ids เลย → ไม่จำกัดสิทธิ์
      // (ผู้ใช้ทุกคนสามารถสร้างคำร้องในหมวดหมู่นี้ได้)
      if (volunteerIds.isEmpty) return null;

      // ดึง profession IDs ของผู้ใช้ (เฉพาะเมื่อหมวดหมู่นี้มีการจำกัดสิทธิ์)
      final userProfIds = await getUserApproverProfessions(userId);
      if (userProfIds.isEmpty) {
        return 'คุณยังไม่มีการกำหนดอาชีพในระบบ กรุณาอัปเดตโปรไฟล์ก่อน';
      }

      // ตรวจว่าอาชีพใดของผู้ใช้ที่ตรง
      final hasEligibleProfession =
          userProfIds.any((pid) => volunteerIds.contains(pid));

      if (!hasEligibleProfession) {
        // ดึงชื่ออาชีพที่อนุญาตมาแสดงในข้อความแจ้งเตือน
        final profNames = await _client
            .from('professions')
            .select('name')
            .inFilter('id', volunteerIds);
        final allowedNames = (profNames as List)
            .map((p) => p['name']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .join(', ');
        return 'หมวดหมู่ "$categoryName" กำหนดให้เฉพาะอาชีพ: $allowedNames เท่านั้นที่สามารถสร้างคำร้องบริจาคได้ (อาชีพของคุณไม่ตรงกับที่แอดมินกำหนด)';
      }

      return null; // มีสิทธิ์
    } catch (e) {
      return null; // กรณี error ให้ผ่านไปก่อน
    }
  }

  /// ✅ สร้างคำร้องพร้อมตรวจสอบสิทธิ์อาชีพและอนุมัติอัตโนมัติ
  /// สำหรับใช้ใน Emergency Flow (Responder/Reporter สร้างคำร้องจากหน้า Live)
  /// คืนค่า requestId หากสำเร็จ หรือ throw Exception พร้อมข้อความแจ้งเตือน
  Future<String> createRequestWithAutoApproval(
    Map<String, dynamic> data,
    String requesterId, {
    String? categoryId,
    bool skipVolunteerCheck = false,
  }) async {
    final usedCategoryId = categoryId ?? data['category_id']?.toString();
    if (usedCategoryId == null) {
      throw Exception('กรุณาระบุหมวดหมู่การบริจาค');
    }

    // --- Obstacle 3: ตรวจสอบสิทธิ์อาชีพก่อน ---
    if (!skipVolunteerCheck) {
      final eligibilityError = await validateVolunteerEligibility(
        requesterId, usedCategoryId);
      if (eligibilityError != null) {
        throw Exception(eligibilityError);
      }
    }

    // --- สร้างคำร้อง ---
    final newRequestId = await createRequest(data);

    // --- Obstacle 1: ตรวจสอบ Auto-Approval ---
    // ดึงอาชีพของผู้ร้องขอ
    final userProfIds = await getUserApproverProfessions(requesterId);
    // ดึง approver_profession_ids (user category IDs) ของหมวดหมู่
    final catData = await _client
        .from('donation_categories')
        .select('approver_profession_ids')
        .eq('id', usedCategoryId)
        .maybeSingle();

    if (catData != null && userProfIds.isNotEmpty) {
      final requiredCatIds = List<String>.from(
          (catData['approver_profession_ids'] as List? ?? [])
              .map((e) => e.toString()));

      if (requiredCatIds.isNotEmpty) {
        // ดึง user_category ของอาชีพผู้ร้องขอ
        final profCatMap = await getProfessionCategoryMap(userProfIds);

        // วนหาว่าอาชีพผู้ร้องขอตรงกับ user category ในลำดับอนุมัติหรือไม่
        for (final profId in userProfIds) {
          final userCatId = profCatMap[profId];
          if (userCatId != null && requiredCatIds.contains(userCatId)) {
            // ✅ อาชีพนี้เป็นผู้อนุมัติในหมวดนี้ → บันทึกการอนุมัติอัตโนมัติ
            try {
              await _client.from('donation_request_approvals').upsert({
                'request_id': newRequestId,
                'profession_id': profId,
                'approved_by': requesterId,
                'status': 'approved',
                'approved_at': DateTime.now().toIso8601String(),
              }, onConflict: 'request_id,profession_id');
            } catch (_) {} // ถ้าเกิด error ในขั้นนี้ให้ข้ามไป ไม่ block การสร้างคำร้อง
          }
        }

        // ตรวจสอบว่าอนุมัติครบทุกกลุ่มแล้วหรือยัง
        await _checkAndActivateRequest(newRequestId, usedCategoryId);
      }
    }

    return newRequestId;
  }

  /// ตรวจสอบว่าคำร้องผ่านการอนุมัติครบทุกกลุ่มแล้วหรือไม่ → ถ้าครบ เปลี่ยนเป็น active
  Future<void> _checkAndActivateRequest(
      String requestId, String categoryId) async {
    try {
      final catData = await _client
          .from('donation_categories')
          .select('approver_profession_ids')
          .eq('id', categoryId)
          .single();
      final requiredIds = List<String>.from(
          (catData['approver_profession_ids'] as List? ?? [])
              .map((e) => e.toString()));

      if (requiredIds.isEmpty) {
        // ถ้าไม่มีผู้อนุมัติที่กำหนด → active ทันที
        await _client.from('donation_requests').update({
          'approval_status': DonationApprovalStatus.active.name,
          'local_verified_at': DateTime.now().toIso8601String(),
        }).eq('id', requestId);
        return;
      }

      // ดึงการอนุมัติที่มีอยู่แล้ว
      final approvedData = await _client
          .from('donation_request_approvals')
          .select('profession_id')
          .eq('request_id', requestId)
          .eq('status', 'approved');
      final approvedProfIds =
          (approvedData as List).map((r) => r['profession_id'].toString()).toList();

      if (approvedProfIds.isEmpty) return;

      final approvedCats = <String>{};
      final catResp = await _client
          .from('professions')
          .select('category')
          .inFilter('id', approvedProfIds);
      for (final r in (catResp as List)) {
        if (r['category'] != null) approvedCats.add(r['category'].toString());
      }

      final allApproved = requiredIds.every((id) => approvedCats.contains(id));
      if (allApproved) {
        await _client.from('donation_requests').update({
          'approval_status': DonationApprovalStatus.active.name,
          'local_verified_at': DateTime.now().toIso8601String(),
        }).eq('id', requestId);
      }
    } catch (_) {}
  }

  /// ดึงคำร้องขอที่กำลังเป็นที่นิยม
  Future<List<DonationRequest>> getTrendingRequests() async {
    final response = await _client
        .from('donation_requests')
        .select()
        .eq('is_trending', true)
        .eq('approval_status', DonationApprovalStatus.active.name)
        .limit(10);
    
    return (response as List)
        .map((json) => DonationRequest.fromJson(json))
        .toList();
  }

  /// คำนวณสถิติภาพรวม (Requested, Received, Remaining)
  Future<DonationStats> getOverallStats() async {
    final response = await _client
        .from('donation_requests')
        .select('target_amount, current_amount')
        .eq('approval_status', DonationApprovalStatus.active.name);
    
    double requested = 0;
    double received = 0;
    
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    for (final row in (response as List)) {
      requested += parseDouble(row['target_amount']);
      received += parseDouble(row['current_amount']);
    }

    return DonationStats(
      requested: requested,
      received: received,
      remaining: (requested - received).clamp(0, double.infinity),
    );
  }

  /// ดึงข้อมูลคำร้องขอแบบ Real-time (พร้อมระบบ Fallback)
  Stream<List<DonationRequest>> watchRequests({String? categoryId}) async* {
    // 1. Fetch ทันทีผ่าน HTTP (Guest โหลดได้)
    try {
      yield await getRequests(categoryId: categoryId);
    } catch (_) {}

    // 2. ถ้าเป็น Guest (ไม่ได้ Login) ให้หยุดแค่นี้
    if (_client.auth.currentUser == null) {
      return;
    }

    // 3. Subscribe Realtime (เฉพาะคนที่ Login)
    try {
      final stream = _client
          .from('donation_requests')
          .stream(primaryKey: ['id'])
          .eq('approval_status', DonationApprovalStatus.active.name)
          .asyncMap((_) => getRequests(categoryId: categoryId));

      await for (final data in stream) {
        yield data;
      }
    } catch (e) {
      print('Supabase Realtime Error (watchRequests): $e');
    }
  }

  /// ยกเลิกคำร้องขอรับบริจาค (Soft Delete โดยเปลี่ยนสถานะ)
  Future<void> cancelRequest(String requestId) async {
    await _client
        .from('donation_requests')
        .update({'approval_status': DonationApprovalStatus.cancelled.name})
        .eq('id', requestId);
  }

  // =====================================================
  // ADMIN CRUD OPERATIONS
  // =====================================================

  /// สร้างหมวดหมู่ใหม่
  Future<void> createCategory(Map<String, dynamic> data) async {
    await _client.from('donation_categories').insert(data);
  }

  /// อัปเดตลำดับหมวดหมู่ทั้งหมด
  Future<void> updateCategoriesDisplayOrder(List<Map<String, dynamic>> orderData) async {
    try {
      for (var item in orderData) {
        await _client.from('donation_categories')
            .update({'display_order': item['display_order']})
            .eq('id', item['id']);
      }
    } catch (e) {
      print('[DonationRepository] Error updating categories order: $e');
      rethrow;
    }
  }

  /// อัปเดตหมวดหมู่
  Future<void> updateCategory(String id, Map<String, dynamic> data) async {
    try {
      print('[DonationRepository] Updating category $id with data: $data');
      await _client.from('donation_categories').update(data).eq('id', id);
      print('[DonationRepository] Category update success');
    } catch (e) {
      print('[DonationRepository] Category update error: $e');
      rethrow;
    }
  }

  /// ลบหมวดหมู่
  Future<void> deleteCategory(String id) async {
    await _client.from('donation_categories').delete().eq('id', id);
  }

  /// สร้างคำร้องขอใหม่
  Future<String> createRequest(Map<String, dynamic> data) async {
    final response = await _client.from('donation_requests').insert(data).select('id').single();
    return response['id'] as String;
  }

  /// อัปเดตคำร้องขอ
  Future<void> updateRequest(String id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('donation_requests').update(data).eq('id', id);
  }

  /// ลบคำร้องขอ
  Future<void> deleteRequest(String id) async {
    await _client.from('donation_requests').delete().eq('id', id);
  }

  /// ดึงข้อมูลชุมชนทั้งหมด
  Future<List<Map<String, dynamic>>> getCommunities() async {
    final response = await _client.from('communities').select('*').order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  /// ปฏิเสธคำร้องขอ
  Future<void> rejectRequest(String requestId) async {
    await _client.from('donation_requests').update({
      'approval_status': DonationApprovalStatus.rejected.name,
    }).eq('id', requestId);
  }


  /// ดึง profession_id ทั้งหมดที่ผู้ใช้นี้มีสิทธิ์อนุมัติ (ทั้งจากตาราง users และ user_group_roles)
  Future<List<String>> getUserApproverProfessions(String userId) async {
    try {
      final List<String> allProfIds = [];

      // 1. ดึงอาชีพหลักจากการลงทะเบียน (users table)
      final userResponse = await _client
          .from('users')
          .select('profession_id')
          .eq('id', userId)
          .maybeSingle();

      if (userResponse != null && userResponse['profession_id'] != null) {
        allProfIds.add(userResponse['profession_id'] as String);
      }

      // 2. ดึงจากสิทธิ์เพิ่มเติม (user_group_roles table)
      // Note: user_group_roles ไม่มีคอลัมน์ is_active (ดู migration 20260224103000_groups_and_roles.sql)
      final response = await _client
          .from('user_group_roles')
          .select('profession_id')
          .eq('user_id', userId);

      allProfIds.addAll((response as List).map((r) => r['profession_id'] as String));

      return allProfIds.toSet().toList();
    } catch (e) {
      return [];
    }
  }

  /// ดึง user_category_id ที่ผู้ใช้คนนี้สังกัด (ผ่าน profession)
  Future<List<String>> getUserApproverCategories(String userId) async {
    final profIds = await getUserApproverProfessions(userId);
    if (profIds.isEmpty) return [];
    
    final response = await _client
        .from('professions')
        .select('category')
        .inFilter('id', profIds);
        
    final List<String> cats = [];
    for (final r in (response as List)) {
      if (r['category'] != null) {
        cats.add(r['category'].toString());
      }
    }
    return cats.toSet().toList();
  }

  /// ตรวจสอบว่าผู้ใช้มีสิทธิ์อนุมัติบริจาคในหมวดหมู่ใดบ้าง
  Future<bool> isLocalLeader(String userId) async {
    final profIds = await getUserApproverProfessions(userId);
    if (profIds.isEmpty) return false;
    // ตรวจสอบว่า profession นั้นอยู่ใน approver_profession_ids ของหมวดใดหมวดหนึ่ง
    try {
      final cats = await _client
          .from('donation_categories')
          .select('approver_profession_ids');
      for (final cat in (cats as List)) {
        final approvers = cat['approver_profession_ids'] as List? ?? [];
        if (approvers.any((a) => profIds.contains(a.toString()))) return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// ดึงประวัติการอนุมัติของคำร้องนั้น
  Future<List<Map<String, dynamic>>> getRequestApprovals(String requestId) async {
    final response = await _client
        .from('donation_request_approvals')
        .select('*, profession:professions(name), approver:users(first_name, last_name)')
        .eq('request_id', requestId);
    return List<Map<String, dynamic>>.from(response);
  }

  /// อนุมัติคำร้อง: บันทึกลง donation_request_approvals
  /// จากนั้นตรวจสอบว่าครบทุกกลุ่มอาชีพหรือยัง → ถ้าครบ → active
  Future<void> approveRequest(
    String requestId,
    DonationApprovalStatus currentStatus,
    String approverId, {
    String? professionId, // profession ที่ผู้อนุมัติใช้ในการอนุมัติครั้งนี้
    bool isAdminOverride = false, // สำหรับแอดมินลัดคิว
  }) async {
    // ✅ Self-Approval Guard — ตรวจ ALWAYS เพื่อนการใดๆ แม้แต่เป็น Admin Override
    final reqData = await _client
        .from('donation_requests')
        .select('category_id, user_id, title')
        .eq('id', requestId)
        .single();

    if (reqData['user_id'] == approverId) {
      throw Exception('คุณไม่สามารถอนุมัติคำร้องของตนเองได้ แม้จะมีสิทธิ์ Admin Override');
    }

    if (isAdminOverride) {
      await _client.from('donation_requests').update({
        'approval_status': DonationApprovalStatus.active.name,
        'local_verified_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);
      return;
    }

    if (currentStatus == DonationApprovalStatus.pending_local) {

      final categoryId = reqData['category_id'] as String;

      // 2. บันทึกการอนุมัติของ profession นี้ (หลัง validate ผ่านแล้ว)
      if (professionId != null) {
        await _client.from('donation_request_approvals').upsert({
          'request_id': requestId,
          'profession_id': professionId,
          'approved_by': approverId,
          'status': 'approved',
          'approved_at': DateTime.now().toIso8601String(),
        }, onConflict: 'request_id,profession_id');
      }

      // 3. ดึงรายชื่อ user category ที่ต้องอนุมัติในหมวดนี้
      final catData = await _client
          .from('donation_categories')
          .select('approver_profession_ids')
          .eq('id', categoryId)
          .single();
      final requiredIds = List<String>.from(
          (catData['approver_profession_ids'] as List? ?? []).map((e) => e.toString()));

      // 4. ดึงรายชื่อ profession ที่อนุมัติแล้ว
      final approvedData = await _client
          .from('donation_request_approvals')
          .select('profession_id')
          .eq('request_id', requestId)
          .eq('status', 'approved');
      final approvedProfIds = (approvedData as List).map((r) => r['profession_id'].toString()).toList();

      final approvedCats = <String>{};
      if (approvedProfIds.isNotEmpty) {
        final catResp = await _client.from('professions').select('category').inFilter('id', approvedProfIds);
        for (final r in (catResp as List)) {
          if (r['category'] != null) approvedCats.add(r['category'].toString());
        }
      }

      // 5. ถ้าครบทุก user category → active
      final allApproved = requiredIds.every((id) => approvedCats.contains(id));
      final newStatus = allApproved
          ? DonationApprovalStatus.active.name
          : DonationApprovalStatus.pending_local.name;

      await _client.from('donation_requests').update({
        'approval_status': newStatus,
        'local_verified_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);

      // ✅ ส่ง Real-time Notification ให้เจ้าของคำร้องบริจาค เมื่อสถานะเปลี่ยน
      final requestOwnerId = reqData['user_id']?.toString();
      final requestTitle = reqData['title']?.toString() ?? 'คำร้องบริจาค';
      if (requestOwnerId != null) {
        WebSocketService().socket?.emit('donation-request-status-updated', {
          'userId': requestOwnerId,
          'requestId': requestId,
          'title': requestTitle,
          'status': newStatus,
        });
      }
    }
  }

  /// ดึงรายการที่รออนุมัติสำหรับผู้ใช้นี้
  /// กรองจาก profession (user category) ของผู้ใช้ที่อยู่ใน approver_profession_ids ของแต่ละหมวดหมู่
  /// และยังไม่ได้อนุมัติสำหรับ profession นั้น
  Future<List<DonationRequest>> getPendingRequests(String userId, {bool isAdminOverride = false}) async {
    // 1. ดึง profession และ category ที่ผู้ใช้มี
    final userProfIds = await getUserApproverProfessions(userId);
    final userCatIds = await getUserApproverCategories(userId);
    final profCatMap = await getProfessionCategoryMap(userProfIds);

    List<String> statuses = [];
    List<String> categoriesUserCanApprove = [];
    int approvalRadius = 500; // default radius
    Position? currentPosition;
    List<dynamic> allCategoriesDB = [];

    if (userProfIds.isNotEmpty || userCatIds.isNotEmpty) {
      // Fetch user's approver settings (toggles)
      final regData = await _client
          .from('user_approver_settings')
          .select('category_id, is_enabled, radius_meters')
          .eq('user_id', userId);
      
      final disabledCategories = <String>[];
      for (final row in (regData as List)) {
        final catId = row['category_id'] as String;
        final isEnabled = row['is_enabled'] as bool? ?? true;
        final radiusMeters = row['radius_meters'] as int? ?? 500;
        
        if (!isEnabled) {
          disabledCategories.add(catId);
        }
        approvalRadius = radiusMeters; // Using the latest one found since it's practically global per user
      }

      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
           currentPosition = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low,
           );
        }
      } catch (e) {
        print('[DonationRepository] Failed to get current location: $e');
      }


      // 2. หาหมวดหมู่ที่ profession ของผู้ใช้อยู่ใน approver_profession_ids
      allCategoriesDB = await _client
          .from('donation_categories')
          .select('id, approver_profession_ids');
      for (final cat in allCategoriesDB) {
        final catIdStr = cat['id'].toString();
        
        // กรองตามที่เคยตั้งค่าใน Widget แถบอนุมัติ (ถ้าไม่ได้ตั้งค่า default เป็น true)
        if (disabledCategories.contains(catIdStr)) continue;

        final approvers = List<String>.from(
            (cat['approver_profession_ids'] as List? ?? []).map((e) => e.toString()));
        // check user categories against required approver categories
        if (approvers.any((a) => userCatIds.contains(a))) {
          categoriesUserCanApprove.add(catIdStr);
        }
      }
      if (categoriesUserCanApprove.isNotEmpty || isAdminOverride) {
        statuses.add(DonationApprovalStatus.pending_local.name);
      }
    }

    if (statuses.isEmpty) return [];

    // 3. ดึงคำร้องที่ยังรออนุมัติ โดยไม่รวมคำร้องที่ผู้ใช้สร้างเอง
    final response = await _client
        .from('donation_requests')
        .select()
        .inFilter('approval_status', statuses)
        .neq('user_id', userId)
        .order('created_at');

    final List<DonationRequest> all =
        (response as List).map((json) => DonationRequest.fromJson(json)).toList();

    if (isAdminOverride) {
      return all.where((r) => r.approvalStatus == DonationApprovalStatus.pending_local).toList();
    }

    if (userProfIds.isEmpty) {
      return [];
    }

    // 4. กรองเฉพาะหมวดหมู่ที่ผู้ใช้มีสิทธิ์ AND ยังไม่ได้อนุมัติด้วย profession นั้น
    // ดึงรายการที่ professor นี้อนุมัติไปแล้ว
    final alreadyApproved = await _client
        .from('donation_request_approvals')
        .select('request_id, profession_id')
        .eq('status', 'approved')
        .inFilter('profession_id', userProfIds);
    final approvedSet = <String>{};
    for (final row in (alreadyApproved as List)) {
      approvedSet.add('${row['request_id']}_${row['profession_id']}');
    }

    return all.where((req) {
      if (req.approvalStatus == DonationApprovalStatus.pending_local) {
        if (!categoriesUserCanApprove.contains(req.categoryId)) return false;
        
        // Distance filtering
        if (currentPosition != null && req.latitude != null && req.longitude != null) {
           final distance = Geolocator.distanceBetween(
             currentPosition!.latitude,
             currentPosition!.longitude,
             req.latitude!,
             req.longitude!,
           );
           // approvalRadius is stored in meters (e.g. 500m to 100,000m)
           // Geolocator.distanceBetween also returns meters.
           // So we can compare them directly.
           if (distance > approvalRadius) {
             return false;
           }
        }
        
        // ตรวจสอบว่ายังมี profession (category) ของผู้ใช้ที่ยังไม่ได้อนุมัติหรือไม่
        // ถ้าอนุมัติเป็นที่เรียบร้อยในหมวด categories ของตัวเองแล้ว ให้ไม่ต้องโชว์
        // Actually, the check logic needs to ensure the request is not already approved *by this user category*
        
        // Find which categories this user can approve for THIS request
        final reqCatData = allCategoriesDB.firstWhere((c) => c['id'].toString() == req.categoryId, orElse: () => {});
        final reqApprovers = List<String>.from(
            (reqCatData['approver_profession_ids'] as List? ?? []).map((e) => e.toString()));
        
        final userCatsThatCanApprove = userCatIds.where((catId) => reqApprovers.contains(catId)).toList();
        
        // Determine which ones have already been approved
        // ตรวจสอบว่าในหมวดหมู่ผู้ใช้ที่ตัวเรามีสิทธิ์อนุมัติคำร้องนี้ (userCatsThatCanApprove)
        // มีหมวดหมู่ไหนที่ 'ยังไม่ได้ถูกอนุมัติ' ด้วยวิชาชีพใดๆ ของเราที่ตรงกับหมวดหมู่นั้นบ้าง
        bool needsApproval = false;
        
        for (final reqCatApproverId in reqApprovers) {
          // ถ้าเราไม่ได้มีหมวดหมู่นี้ ก็ข้ามไป
          if (!userCatsThatCanApprove.contains(reqCatApproverId)) continue;
          
          // ดูว่าเรามี profession ใดบ้างที่ตกอยู่ในหมวดหมู่นี้
          final pids = userProfIds.where((pid) => profCatMap[pid] == reqCatApproverId).toList();
          
          // ถ้าไม่มีสัก profession ในหมวดนี้ที่อนุมัติแล้วแปลว่ายังต้องอนุมัติ
          bool hasApprovedAsThisCat = pids.any((pid) => approvedSet.contains('${req.id}_$pid'));
          if (!hasApprovedAsThisCat) {
            needsApproval = true;
            break;
          }
        }
        
        return needsApproval;
      }
      return false;
    }).toList();
  }

  /// ดึงประวัติการบริจาคทั้งหมด
  Future<List<Map<String, dynamic>>> getContributions() async {
    final response = await _client
        .from('donation_contributions')
        .select('''
          *,
          user:users(username, first_name, last_name),
          request:donation_requests(title)
        ''')
        .order('created_at', ascending: false);
    
    return List<Map<String, dynamic>>.from(response);
  }

  /// เพิ่มข้อมูลการบริจาค (จำลอง Flow การชำระเงิน)
  Future<void> addContribution(Map<String, dynamic> data) async {
    await _client.from('donation_contributions').insert(data);
  }

  /// ดึง Transaction ที่รอดำเนินการคืนเงิน (refund_pending)
  Future<List<Map<String, dynamic>>> getRefundPendingTransactions(String userId) async {
    final response = await _client
        .from('donation_transactions')
        .select('*, request:donation_requests(title, id)')
        .eq('donor_user_id', userId)
        .eq('status', 'refund_pending');
    return List<Map<String, dynamic>>.from(response);
  }

  /// อัปเดตความต้องการคืนเงิน (credit vs beneficiary)
  Future<void> updateRefundPreference(String transactionId, String preference) async {
    await _client.from('donation_transactions').update({
      'refund_preference': preference,
      // เมื่อเลือกแล้ว เราอาจจะเปลี่ยนสถานะเพื่อให้ Node.js ไปจัดการต่อ
      'status': 'refund_disposed', // สถานะใหม่เพื่อบอกว่า 'จัดสรรแล้ว'
    }).eq('id', transactionId);
  }

  // =====================================================
  // HELPER METHODS (Bug Fixes)
  // =====================================================

  /// ✅ Bug #4 Fix: ตรวจสอบว่าผู้ใช้เป็น Storage Admin จาก DB จริง
  Future<bool> isStorageAdmin(String userId) async {
    try {
      final response = await _client
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      if (response == null) return false;
      final role = response['role']?.toString() ?? '';
      return role == 'admin' || role == 'storage_admin';
    } catch (e) {
      return false;
    }
  }

  /// ✅ Bug #3 Fix: ดึง approver user_category IDs ของหมวดหมู่บริจาคนั้น
  Future<List<String>> getCategoryApproverIds(String categoryId) async {
    try {
      final data = await _client
          .from('donation_categories')
          .select('approver_profession_ids')
          .eq('id', categoryId)
          .maybeSingle();
      if (data == null) return [];
      return List<String>.from(
          (data['approver_profession_ids'] as List? ?? []).map((e) => e.toString()));
    } catch (e) {
      return [];
    }
  }

  /// ✅ Bug #3 Fix: ดึง map ของ professionId → user_category_id
  Future<Map<String, String>> getProfessionCategoryMap(List<String> professionIds) async {
    if (professionIds.isEmpty) return {};
    try {
      final response = await _client
          .from('professions')
          .select('id, category')
          .inFilter('id', professionIds);
      final map = <String, String>{};
      for (final r in (response as List)) {
        if (r['id'] != null && r['category'] != null) {
          map[r['id'].toString()] = r['category'].toString();
        }
      }
      return map;
    } catch (e) {
      return {};
    }
  }

  // =====================================================
  // DONATION TRANSACTIONS (Payment Infrastructure)
  // =====================================================

  /// สร้าง Transaction ใหม่ (status: pending) เมื่อผู้ใช้เริ่ม Flow ชำระเงิน
  /// คืน transaction id เพื่อให้ PaymentService ใช้ติดตาม
  Future<String> createTransaction(Map<String, dynamic> data) async {
    final response = await _client
        .from('donation_transactions')
        .insert(data)
        .select('id')
        .single();
    return response['id'] as String;
  }

  /// ยืนยันการชำระเงิน (status: confirmed)
  /// เรียก DB Function confirm_donation_transaction ซึ่งจะ:
  ///   1. อัปเดต status → confirmed, ตั้ง confirmed_at
  ///   2. atomic: บวก amount เข้า donation_requests.current_amount
  Future<void> confirmTransaction(String transactionId, {String? paymentReference}) async {
    await _client.rpc('confirm_donation_transaction', params: {
      'p_transaction_id': transactionId,
      'p_reference': paymentReference,
    });
  }

  /// ทำเครื่องหมาย Transaction ว่าล้มเหลว (status: failed)
  Future<void> failTransaction(String transactionId) async {
    await _client
        .from('donation_transactions')
        .update({'status': 'failed'})
        .eq('id', transactionId);
  }

  /// ดึง Transactions ทั้งหมดของคำร้องนี้ (เรียงจากใหม่ไปเก่า)
  Future<List<DonationTransaction>> getTransactionsByRequest(String requestId) async {
    final response = await _client
        .from('donation_transactions')
        .select()
        .eq('request_id', requestId)
        .order('created_at', ascending: false);
    return (response as List)
        .map((json) => DonationTransaction.fromJson(json))
        .toList();
  }

  /// ดึงประวัติการบริจาคของผู้ใช้คนนี้ (เรียงจากใหม่ไปเก่า)
  Future<List<DonationTransaction>> getTransactionsByUser(String userId) async {
    final response = await _client
        .from('donation_transactions')
        .select()
        .eq('donor_user_id', userId)
        .order('created_at', ascending: false);
    return (response as List)
        .map((json) => DonationTransaction.fromJson(json))
        .toList();
  }

  /// ดึง Transactions ที่สำเร็จทั้งหมดของคำร้อง (สำหรับแสดง audit trail)
  Future<List<DonationTransaction>> getConfirmedTransactions(String requestId) async {
    final response = await _client
        .from('donation_transactions')
        .select()
        .eq('request_id', requestId)
        .eq('status', 'confirmed')
        .order('confirmed_at', ascending: false);
    return (response as List)
        .map((json) => DonationTransaction.fromJson(json))
        .toList();
  }
}
