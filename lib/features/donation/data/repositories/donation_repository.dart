import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/donation_models.dart';

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
      final response = await _client
          .from('user_group_roles')
          .select('profession_id')
          .eq('user_id', userId)
          .eq('is_active', true);
          
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
    if (isAdminOverride) {
      await _client.from('donation_requests').update({
        'approval_status': DonationApprovalStatus.active.name,
        'local_verified_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);
      return;
    }

    if (currentStatus == DonationApprovalStatus.pending_local) {
      // ✅ Bug #1 Fix: Validate ก่อน write ทุกครั้ง
      // 1. ดึงหมวดหมู่ของคำร้องและตรวจ self-approval ก่อนเสมอ
      final reqData = await _client
          .from('donation_requests')
          .select('category_id, user_id')
          .eq('id', requestId)
          .single();

      if (reqData['user_id'] == approverId) {
        throw Exception('คุณไม่สามารถอนุมัติคำร้องของตนเองได้');
      }

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
           // approvalRadius is in integer (meters or km? typically km if small, meters if large). 
           // From DB code: int approvalRadius = 500; (Probably km? Actually in UI we set km, but default 500 km)
           // If UI sets km, need to compare with km. Geolocator returns meters.
           // Let's assume approvalRadius is km based on `int approvalRadius = 500`. 500 meters is too small for a region.
           // Actually, let's treat approvalRadius as km: distance in meters / 1000 <= approvalRadius
           if ((distance / 1000.0) > approvalRadius) {
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
}
