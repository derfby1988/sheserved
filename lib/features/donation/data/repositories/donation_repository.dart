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
  Future<List<DonationRequest>> getRequests({String? categoryId}) async {
    var query = _client.from('donation_requests').select();
    
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }
    
    final response = await query
        .eq('approval_status', DonationApprovalStatus.active.name)
        .order('created_at', ascending: false);
    
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
    await _client.from('donation_categories').update(data).eq('id', id);
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

  /// อนุมัติคำร้องขอ (Flow หลายขั้นตอน)
  Future<void> approveRequest(String requestId, DonationApprovalStatus currentStatus, String approverId) async {
    DonationApprovalStatus nextStatus;
    Map<String, dynamic> updateData = {};

    if (currentStatus == DonationApprovalStatus.pending_local) {
      nextStatus = DonationApprovalStatus.pending_storage;
      updateData = {
        'approval_status': nextStatus.name,
        'local_verified_at': DateTime.now().toIso8601String(),
      };
    } else if (currentStatus == DonationApprovalStatus.pending_storage) {
      nextStatus = DonationApprovalStatus.active;
      updateData = {
        'approval_status': nextStatus.name,
        'storage_approved_by': approverId,
      };
    } else {
      return;
    }

    await _client.from('donation_requests').update(updateData).eq('id', requestId);
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


  /// ดึงรายการที่รออนุมัติ (กรองตามสิทธิ)
  Future<List<DonationRequest>> getPendingRequests(String userId, {bool isStorageAdmin = false}) async {
    // 1. ดึงข้อมูลชุมชนที่ผู้ใช้คนนี้เป็นผู้นำ
    final communityResponse = await _client
        .from('communities')
        .select('id')
        .eq('leader_id', userId);
    final ledCommunityIds = (communityResponse as List).map((c) => c['id'] as String).toList();

    // 2. กำหนดสถานะที่ผู้ใช้มีสิทธิเห็น
    List<String> statuses = [];
    if (ledCommunityIds.isNotEmpty) statuses.add(DonationApprovalStatus.pending_local.name);
    if (isStorageAdmin) statuses.add(DonationApprovalStatus.pending_storage.name);

    if (statuses.isEmpty) return [];

    var query = _client.from('donation_requests').select().inFilter('approval_status', statuses);

    final response = await query.order('created_at');
    final List<DonationRequest> allRelevant = (response as List).map((json) => DonationRequest.fromJson(json)).toList();

    // กรองขั้นสุดท้ายตามสิทธิ
    return allRelevant.where((req) {
      if (req.approvalStatus == DonationApprovalStatus.pending_local) {
        return ledCommunityIds.contains(req.communityId);
      }
      if (req.approvalStatus == DonationApprovalStatus.pending_storage) {
        return isStorageAdmin;
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
}
