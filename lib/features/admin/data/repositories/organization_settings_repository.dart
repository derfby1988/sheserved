import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/organization_settings.dart';

/// Repository สำหรับจัดการ Organization Settings / Header
class OrganizationSettingsRepository {
  final SupabaseClient _client;

  OrganizationSettingsRepository(this._client);

  // =====================================================
  // READ — Organization Header (one-shot via RPC)
  // =====================================================

  /// ดึงข้อมูล Organization Header รวม profession + branches
  Future<OrganizationSettings?> getOrganizationHeader(String professionId) async {
    debugPrint('[ERP Repo] getOrganizationHeader — professionId=$professionId');
    try {
      final response = await _client.rpc(
        'get_organization_header',
        params: {'p_profession_id': professionId},
      );

      debugPrint('[ERP Repo] RPC response type: ${response.runtimeType}');
      if (response == null) {
        debugPrint('[ERP Repo] RPC returned null');
        return null;
      }
      debugPrint('[ERP Repo] RPC returned data: ${(response as Map<String, dynamic>).keys.toList()}');
      return OrganizationSettings.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[ERP Repo] getOrganizationHeader error: $e');
      debugPrint('[ERP Repo] stackTrace: $st');
      return null;
    }
  }

  /// ดึงข้อมูล profession ตาม ID (fallback)
  Future<OrganizationSettings?> getProfessionWithBranches(String professionId) async {
    try {
      // Fetch profession
      final profResponse = await _client
          .from('professions')
          .select()
          .eq('id', professionId)
          .single();

      // Fetch branches
      final branchesResponse = await _client
          .from('organization_branches')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('is_main_branch', ascending: false)
          .order('branch_code');

      final mainBranch = (branchesResponse as List).firstWhere(
        (b) => b['is_main_branch'] == true,
        orElse: () => branchesResponse.isNotEmpty ? branchesResponse.first : null,
      );

      return OrganizationSettings(
        professionId: professionId,
        professionName: profResponse['name'] ?? '',
        professionNameEn: profResponse['name_en'],
        professionIconName: profResponse['icon_name'],
        professionColorHex: profResponse['color_hex'],
        logoUrl: profResponse['logo_url'],
        taxId: profResponse['tax_id'],
        phone: profResponse['phone'],
        email: profResponse['email'],
        address: profResponse['address'],
        currency: profResponse['currency'] ?? 'THB',
        language: profResponse['language'] ?? 'th',
        timezone: profResponse['timezone'] ?? 'Asia/Bangkok',
        storageMode: profResponse['storage_mode'] ?? 'cloud',
        selfHostApiUrl: profResponse['self_host_api_url'],
        branches: (branchesResponse as List)
            .map((b) => OrganizationBranch.fromJson(b))
            .toList(),
        mainBranchId: mainBranch?['id'],
        totalBranches: branchesResponse.length,
      );
    } catch (e) {
      debugPrint('OrganizationSettingsRepository.getProfessionWithBranches error: $e');
      return null;
    }
  }

  // =====================================================
  // UPDATE — Organization Settings
  // =====================================================

  /// บันทึกข้อมูลองค์กร (RPC save_organization_settings)
  Future<bool> saveOrganizationSettings({
    required String professionId,
    required String name,
    String? nameEn,
    String? logoUrl,
    String? taxId,
    String? phone,
    String? email,
    String? address,
    String? currency,
    String? language,
    String? timezone,
    String? storageMode,
    String? selfHostApiUrl,
  }) async {
    try {
      await _client.rpc('save_organization_settings', params: {
        'p_profession_id': professionId,
        'p_name': name,
        'p_name_en': nameEn ?? name,
        'p_logo_url': logoUrl,
        'p_tax_id': taxId,
        'p_phone': phone,
        'p_email': email,
        'p_address': address,
        'p_currency': currency ?? 'THB',
        'p_language': language ?? 'th',
        'p_timezone': timezone ?? 'Asia/Bangkok',
        'p_storage_mode': storageMode ?? 'cloud',
        'p_self_host_api_url': selfHostApiUrl,
      });
      return true;
    } catch (e) {
      debugPrint('OrganizationSettingsRepository.saveOrganizationSettings error: $e');
      return false;
    }
  }

  /// บันทึกข้อมูลองค์กร (direct update fallback)
  Future<bool> updateProfessionDirect({
    required String professionId,
    required Map<String, dynamic> data,
  }) async {
    try {
      data['updated_at'] = DateTime.now().toIso8601String();
      await _client.from('professions').update(data).eq('id', professionId);
      return true;
    } catch (e) {
      debugPrint('OrganizationSettingsRepository.updateProfessionDirect error: $e');
      return false;
    }
  }

  // =====================================================
  // BRANCH CRUD
  // =====================================================

  /// สร้าง/อัปเดตสาขา (RPC upsert_branch)
  Future<OrganizationBranch?> upsertBranch({
    String? branchId,
    required String professionId,
    required String branchCode,
    required String branchName,
    String? taxId,
    String? branchTaxCode,
    String? address,
    String? phone,
    String? email,
    bool isMainBranch = false,
    bool isActive = true,
  }) async {
    try {
      final response = await _client.rpc('upsert_branch', params: {
        'p_branch_id': branchId,
        'p_profession_id': professionId,
        'p_branch_code': branchCode,
        'p_branch_name': branchName,
        'p_tax_id': taxId,
        'p_branch_tax_code': branchTaxCode,
        'p_address': address,
        'p_phone': phone,
        'p_email': email,
        'p_is_main_branch': isMainBranch,
        'p_is_active': isActive,
      });

      if (response == null) return null;
      final result = response as Map<String, dynamic>;
      final returnedId = result['branch_id'] as String?;
      if (returnedId == null) return null;

      return OrganizationBranch(
        id: returnedId,
        branchCode: branchCode,
        branchName: branchName,
        taxId: taxId,
        branchTaxCode: branchTaxCode,
        address: address,
        phone: phone,
        email: email,
        isMainBranch: isMainBranch,
        isActive: isActive,
      );
    } catch (e) {
      debugPrint('OrganizationSettingsRepository.upsertBranch error: $e');
      return null;
    }
  }

  /// ลบสาขา (soft delete)
  Future<bool> deleteBranch(String branchId) async {
    try {
      await _client.from('organization_branches').update({
        'is_active': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', branchId);
      return true;
    } catch (e) {
      debugPrint('OrganizationSettingsRepository.deleteBranch error: $e');
      return false;
    }
  }

  /// ดึงรายการสาขาทั้งหมดของ profession
  Future<List<OrganizationBranch>> getBranches(String professionId) async {
    try {
      final response = await _client
          .from('organization_branches')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('is_main_branch', ascending: false)
          .order('branch_code');

      return (response as List)
          .map((b) => OrganizationBranch.fromJson(b))
          .toList();
    } catch (e) {
      debugPrint('OrganizationSettingsRepository.getBranches error: $e');
      return [];
    }
  }

  // =====================================================
  // USER BRANCH ASSIGNMENT
  // =====================================================

  /// อัปเดตสาขาของ user
  Future<bool> updateUserBranch(String userId, String? branchId) async {
    try {
      await _client.from('users').update({
        'branch_id': branchId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
      return true;
    } catch (e) {
      debugPrint('OrganizationSettingsRepository.updateUserBranch error: $e');
      return false;
    }
  }

  /// ดึงสาขาปัจจุบันของ user
  Future<String?> getUserBranchId(String userId) async {
    try {
      final response = await _client
          .from('users')
          .select('branch_id')
          .eq('id', userId)
          .single();
      return response['branch_id'] as String?;
    } catch (e) {
      debugPrint('OrganizationSettingsRepository.getUserBranchId error: $e');
      return null;
    }
  }
}
