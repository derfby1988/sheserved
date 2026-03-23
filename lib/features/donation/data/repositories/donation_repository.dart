import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/donation_models.dart';

/// Repository สำหรับจัดการข้อมูลการบริจาค
class DonationRepository {
  final SupabaseClient _client;

  DonationRepository(this._client);

  /// ดึงหมวดหมู่การบริจาคทั้งหมด
  Future<List<DonationCategory>> getCategories() async {
    final response = await _client
        .from('donation_categories')
        .select()
        .order('display_order');
    
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
        .order('display_order');
    
    return (response as List)
        .map((json) => DonationCategory.fromJson(json))
        .toList();
  }

  /// ดึงข้อมูลหมวดหมู่แบบ Real-time
  Stream<List<DonationCategory>> watchCategories() {
    return _client
        .from('donation_categories')
        .stream(primaryKey: ['id'])
        .order('display_order')
        .asyncMap((_) => getCategories());
  }

  /// ดึงคำร้องขอการบริจาค (กรองตามหมวดหมู่ได้)
  Future<List<DonationRequest>> getRequests({
    String? categoryId,
    String? userId,
    bool bypassStatusFilter = false,
  }) async {
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
    
    return (response as List)
        .map((json) => DonationRequest.fromJson(json))
        .toList();
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

  /// ดึงข้อมูลคำร้องขอแบบ Real-time
  Stream<List<DonationRequest>> watchRequests({String? categoryId}) {
    return _client
        .from('donation_requests')
        .stream(primaryKey: ['id'])
        .eq('approval_status', DonationApprovalStatus.active.name)
        .asyncMap((_) => getRequests(categoryId: categoryId));
  }

  // =====================================================
  // ADMIN CRUD OPERATIONS
  // =====================================================

  /// สร้างหมวดหมู่ใหม่
  Future<void> createCategory(Map<String, dynamic> data) async {
    await _client.from('donation_categories').insert(data);
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
  Future<void> createRequest(Map<String, dynamic> data) async {
    await _client.from('donation_requests').insert(data);
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


  /// ดึง profession_id ทั้งหมดที่ผู้ใช้นี้มีสิทธิ์อนุมัติ (ผ่าน user_group_roles)
  Future<List<String>> getUserApproverProfessions(String userId) async {
    try {
      final response = await _client
          .from('user_group_roles')
          .select('profession_id')
          .eq('user_id', userId)
          .eq('is_active', true);
      return (response as List).map((r) => r['profession_id'] as String).toList();
    } catch (e) {
      return [];
    }
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
  }) async {
    if (currentStatus == DonationApprovalStatus.pending_local) {
      // 1. บันทึกการอนุมัติของ profession นี้
      if (professionId != null) {
        await _client.from('donation_request_approvals').upsert({
          'request_id': requestId,
          'profession_id': professionId,
          'approved_by': approverId,
          'status': 'approved',
          'approved_at': DateTime.now().toIso8601String(),
        }, onConflict: 'request_id,profession_id');
      }

      // 2. ดึงหมวดหมู่ของคำร้องนี้
      final reqData = await _client
          .from('donation_requests')
          .select('category_id')
          .eq('id', requestId)
          .single();
      final categoryId = reqData['category_id'] as String;

      // 3. ดึงรายชื่อ profession ที่ต้องอนุมัติในหมวดนี้
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
      final approvedIds = (approvedData as List).map((r) => r['profession_id'].toString()).toSet();

      // 5. ถ้าครบทุก profession → active
      final allApproved = requiredIds.every((id) => approvedIds.contains(id));
      final newStatus = allApproved
          ? DonationApprovalStatus.active.name
          : DonationApprovalStatus.pending_local.name;

      await _client.from('donation_requests').update({
        'approval_status': newStatus,
        'local_verified_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);

    } else if (currentStatus == DonationApprovalStatus.pending_storage) {
      await _client.from('donation_requests').update({
        'approval_status': DonationApprovalStatus.active.name,
        'storage_approved_by': approverId,
      }).eq('id', requestId);
    }
  }

  /// ดึงรายการที่รออนุมัติสำหรับผู้ใช้นี้
  /// กรองจาก profession ของผู้ใช้ที่อยู่ใน approver_profession_ids ของแต่ละหมวดหมู่
  /// และยังไม่ได้อนุมัติสำหรับ profession นั้น
  Future<List<DonationRequest>> getPendingRequests(String userId, {bool isStorageAdmin = false}) async {
    // 1. ดึง profession ที่ผู้ใช้มี
    final userProfIds = await getUserApproverProfessions(userId);

    List<String> statuses = [];
    List<String> categoriesUserCanApprove = [];

    if (userProfIds.isNotEmpty) {
      // 2. หาหมวดหมู่ที่ profession ของผู้ใช้อยู่ใน approver_profession_ids
      final cats = await _client
          .from('donation_categories')
          .select('id, approver_profession_ids');
      for (final cat in (cats as List)) {
        final approvers = List<String>.from(
            (cat['approver_profession_ids'] as List? ?? []).map((e) => e.toString()));
        if (approvers.any((a) => userProfIds.contains(a))) {
          categoriesUserCanApprove.add(cat['id'].toString());
        }
      }
      if (categoriesUserCanApprove.isNotEmpty) {
        statuses.add(DonationApprovalStatus.pending_local.name);
      }
    }
    if (isStorageAdmin) statuses.add(DonationApprovalStatus.pending_storage.name);

    if (statuses.isEmpty) return [];

    // 3. ดึงคำร้องที่ยังรออนุมัติ
    final response = await _client
        .from('donation_requests')
        .select()
        .inFilter('approval_status', statuses)
        .order('created_at');

    final List<DonationRequest> all =
        (response as List).map((json) => DonationRequest.fromJson(json)).toList();

    if (userProfIds.isEmpty) {
      return all.where((r) => r.approvalStatus == DonationApprovalStatus.pending_storage).toList();
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
        // ตรวจสอบว่ายังมี profession ของผู้ใช้ที่ยังไม่ได้อนุมัติ
        return userProfIds.any((pid) => !approvedSet.contains('${req.id}_$pid'));
      }
      return req.approvalStatus == DonationApprovalStatus.pending_storage && isStorageAdmin;
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
}
