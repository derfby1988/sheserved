import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../admin/data/repositories/organization_settings_repository.dart';
import '../../../admin/models/organization_settings.dart';
import '../../../../services/auth_service.dart';

// ========================
// Repository Provider
// ========================

final organizationSettingsRepositoryProvider = Provider<OrganizationSettingsRepository>((ref) {
  return OrganizationSettingsRepository(Supabase.instance.client);
});

// ========================
// State
// ========================

class OrganizationSettingsState {
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  final OrganizationSettings? settings;
  final String? selectedBranchId;
  final String? professionId; // Stored even when settings is null (first-time setup)

  OrganizationSettingsState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.settings,
    this.selectedBranchId,
    this.professionId,
  });

  OrganizationSettingsState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    OrganizationSettings? settings,
    String? selectedBranchId,
    String? professionId,
  }) {
    final shouldClearError = clearError || ((isLoading != null && !isLoading) || (isSaving != null && !isSaving));
    return OrganizationSettingsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      settings: settings ?? this.settings,
      selectedBranchId: selectedBranchId ?? this.selectedBranchId,
      professionId: professionId ?? this.professionId,
    );
  }

  /// มีข้อมูลองค์กรหรือไม่
  bool get hasOrganization => settings != null;

  /// ต้องตั้งค่าครั้งแรกหรือไม่ (ยังไม่มี branches / ยังไม่มี logo)
  bool get needsInitialSetup {
    if (settings == null) return true;
    if (settings!.branches.isEmpty) return true;
    return false;
  }

  /// ชื่อสาขาที่เลือก
  String? get selectedBranchName {
    if (settings == null || selectedBranchId == null) return null;
    try {
      final branch = settings!.branches.firstWhere((b) => b.id == selectedBranchId);
      return branch.branchName;
    } catch (_) {
      return null;
    }
  }
}

// ========================
// Notifier
// ========================

class OrganizationSettingsNotifier extends StateNotifier<OrganizationSettingsState> {
  final OrganizationSettingsRepository _repository;

  OrganizationSettingsNotifier(this._repository) : super(OrganizationSettingsState());

  /// โหลดข้อมูล Organization จาก profession_id
  Future<void> loadOrganization(String professionId) async {
    debugPrint('[ERP] loadOrganization called with professionId=$professionId');
    state = state.copyWith(isLoading: true, clearError: true, professionId: professionId);

    try {
      final settings = await _repository.getOrganizationHeader(professionId);
      debugPrint('[ERP] getOrganizationHeader returned: ${settings != null ? settings.professionName : 'null'}');
      if (settings == null) {
        debugPrint('[ERP] settings is null — falling back to getProfessionWithBranches');
        final fallbackSettings = await _repository.getProfessionWithBranches(professionId);
        debugPrint('[ERP] fallback returned: ${fallbackSettings != null ? fallbackSettings.professionName : 'null'}');
        if (fallbackSettings == null) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: 'ไม่พบข้อมูลองค์กร',
          );
          return;
        }
        final defaultBranchId = fallbackSettings.mainBranchId ??
            (fallbackSettings.branches.isNotEmpty ? fallbackSettings.branches.first.id : null);
        state = state.copyWith(
          isLoading: false,
          settings: fallbackSettings,
          selectedBranchId: state.selectedBranchId ?? defaultBranchId,
        );
        return;
      }

      // Auto-select main branch if none selected
      final defaultBranchId = settings.mainBranchId ??
          (settings.branches.isNotEmpty ? settings.branches.first.id : null);

      state = state.copyWith(
        isLoading: false,
        settings: settings,
        selectedBranchId: state.selectedBranchId ?? defaultBranchId,
      );
      debugPrint('[ERP] loadOrganization success — org=${settings.professionName}, branches=${settings.branches.length}');
    } catch (e, st) {
      debugPrint('[ERP] loadOrganization ERROR: $e');
      debugPrint('[ERP] stackTrace: $st');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'โหลดข้อมูลองค์กรล้มเหลว: $e',
      );
    }
  }

  /// โหลดจาก user ปัจจุบัน (ใช้ profession_id จาก AuthService)
  Future<void> loadFromCurrentUser() async {
    final user = AuthService.instance.currentUser;
    final professionId = user?.professionId;
    debugPrint('[ERP] loadFromCurrentUser — userId=${user?.id}, professionId=$professionId');

    if (professionId == null || professionId.isEmpty) {
      debugPrint('[ERP] loadFromCurrentUser — no professionId, aborting');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'ไม่พบ Profession ID ของผู้ใช้',
      );
      return;
    }

    await loadOrganization(professionId);
  }

  /// เปลี่ยนสาขาที่เลือก
  void selectBranch(String branchId) {
    state = state.copyWith(selectedBranchId: branchId);
  }

  /// บันทึกข้อมูลองค์กร (รองรับ first-time setup)
  Future<bool> saveOrganization({
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
    final professionId = state.settings?.professionId ?? state.professionId;
    if (professionId == null || professionId.isEmpty) {
      state = state.copyWith(errorMessage: 'ไม่มี Profession ID สำหรับบันทึก');
      return false;
    }

    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final success = await _repository.saveOrganizationSettings(
        professionId: professionId,
        name: name,
        nameEn: nameEn,
        logoUrl: logoUrl,
        taxId: taxId,
        phone: phone,
        email: email,
        address: address,
        currency: currency,
        language: language,
        timezone: timezone,
        storageMode: storageMode,
        selfHostApiUrl: selfHostApiUrl,
      );

      if (success) {
        // Reload to get updated data
        await loadOrganization(professionId);
        state = state.copyWith(isSaving: false);
        return true;
      } else {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'บันทึกไม่สำเร็จ',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'บันทึกข้อมูลล้มเหลว: $e',
      );
      return false;
    }
  }

  /// สร้าง/อัปเดตสาขา
  Future<OrganizationBranch?> saveBranch({
    String? branchId,
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
    final professionId = state.settings?.professionId ?? state.professionId;
    if (professionId == null || professionId.isEmpty) return null;

    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final branch = await _repository.upsertBranch(
        branchId: branchId,
        professionId: professionId,
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

      if (branch != null) {
        await loadOrganization(professionId);
      }

      state = state.copyWith(isSaving: false);
      return branch;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'บันทึกสาขาล้มเหลว: $e',
      );
      return null;
    }
  }

  /// ลบสาขา
  Future<bool> deleteBranch(String branchId) async {
    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final success = await _repository.deleteBranch(branchId);
      if (success && state.settings != null) {
        await loadOrganization(state.settings!.professionId);
      }
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'ลบสาขาล้มเหลว: $e',
      );
      return false;
    }
  }

  /// อัปเดตสาขาของ user ปัจจุบัน
  Future<bool> assignUserBranch(String userId, String? branchId) async {
    try {
      final success = await _repository.updateUserBranch(userId, branchId);
      if (success) {
        state = state.copyWith(selectedBranchId: branchId);
      }
      return success;
    } catch (e) {
      state = state.copyWith(errorMessage: 'อัปเดตสาขาล้มเหลว: $e');
      return false;
    }
  }
}

// ========================
// Global Provider
// ========================

final organizationSettingsProvider =
    StateNotifierProvider<OrganizationSettingsNotifier, OrganizationSettingsState>((ref) {
  final repo = ref.watch(organizationSettingsRepositoryProvider);
  return OrganizationSettingsNotifier(repo);
});
