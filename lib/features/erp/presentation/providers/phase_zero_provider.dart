import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/employee_role.dart';
import '../../data/models/organization_feature_flag.dart';
import '../../data/models/organization_role.dart';
import '../../data/models/role_module_permission.dart';
import '../../data/repositories/phase_zero_repository.dart';
import '../../../../services/auth_service.dart';

// ========================
// Repository Provider
// ========================

final phaseZeroRepositoryProvider = Provider<PhaseZeroRepository>((ref) {
  return PhaseZeroRepository(Supabase.instance.client);
});

// ========================
// State
// ========================

class PhaseZeroState {
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  // RBAC
  final List<Map<String, dynamic>> userRolesAndPermissions;
  final List<OrganizationRole> organizationRoles;
  final List<EmployeeRole> employeeRoles;
  final List<Map<String, dynamic>> usersWithRoles; // รายการ user พร้อม role สำหรับหน้า Assignment

  // Feature Flags
  final List<OrganizationFeatureFlag> featureFlags;

  // Selected
  final OrganizationRole? selectedRole;
  final List<RoleModulePermission> selectedRolePermissions;

  PhaseZeroState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.userRolesAndPermissions = const [],
    this.organizationRoles = const [],
    this.employeeRoles = const [],
    this.usersWithRoles = const [],
    this.featureFlags = const [],
    this.selectedRole,
    this.selectedRolePermissions = const [],
  });

  PhaseZeroState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    List<Map<String, dynamic>>? userRolesAndPermissions,
    List<OrganizationRole>? organizationRoles,
    List<EmployeeRole>? employeeRoles,
    List<Map<String, dynamic>>? usersWithRoles,
    List<OrganizationFeatureFlag>? featureFlags,
    OrganizationRole? selectedRole,
    bool clearSelectedRole = false,
    List<RoleModulePermission>? selectedRolePermissions,
  }) {
    final shouldClearError = clearError ||
        ((isLoading != null && !isLoading) || (isSaving != null && !isSaving));
    return PhaseZeroState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      userRolesAndPermissions:
          userRolesAndPermissions ?? this.userRolesAndPermissions,
      organizationRoles: organizationRoles ?? this.organizationRoles,
      employeeRoles: employeeRoles ?? this.employeeRoles,
      usersWithRoles: usersWithRoles ?? this.usersWithRoles,
      featureFlags: featureFlags ?? this.featureFlags,
      selectedRole: clearSelectedRole ? null : (selectedRole ?? this.selectedRole),
      selectedRolePermissions:
          selectedRolePermissions ?? this.selectedRolePermissions,
    );
  }

  /// ตรวจสอบว่า user มี permission ใน module ที่กำหนดหรือไม่
  bool hasModulePermission(String moduleName, {int minimumLevel = 1}) {
    for (final roleMap in userRolesAndPermissions) {
      final perms = roleMap['permissions'] as List<dynamic>?;
      if (perms == null) continue;
      for (final perm in perms) {
        if (perm is Map<String, dynamic> &&
            perm['module_name'] == moduleName &&
            (perm['access_level'] as int?) != null &&
            (perm['access_level'] as int) >= minimumLevel) {
          return true;
        }
      }
    }
    return false;
  }

  /// ตรวจสอบว่า feature เปิดใช้งานหรือไม่
  bool isFeatureEnabled(String featureName) {
    try {
      final flag = featureFlags.firstWhere((f) => f.featureName == featureName);
      return flag.isEnabled;
    } catch (_) {
      return false; // ถ้าไม่มี flag → ปิดไว้ก่อน (secure by default)
    }
  }

  /// รายชื่อ feature ที่เปิดใช้งาน
  List<String> get enabledFeatures {
    return featureFlags
        .where((f) => f.isEnabled)
        .map((f) => f.featureName)
        .toList();
  }
}

// ========================
// Notifier
// ========================

class PhaseZeroNotifier extends StateNotifier<PhaseZeroState> {
  final PhaseZeroRepository _repository;

  PhaseZeroNotifier(this._repository) : super(PhaseZeroState());

  // ========================
  // RBAC — Load User Roles
  // ========================

  /// โหลด roles + permissions ของ user ปัจจุบัน
  Future<void> loadCurrentUserRoles() async {
    final user = AuthService.instance.currentUser;
    final professionId = user?.professionId;
    final userId = user?.id;

    if (professionId == null || userId == null) {
      state = state.copyWith(
        errorMessage: 'ไม่พบข้อมูลผู้ใช้หรือ Profession ID',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final rolesAndPerms = await _repository.getUserRolesAndPermissions(
        userId,
        professionId,
      );

      state = state.copyWith(
        isLoading: false,
        userRolesAndPermissions: rolesAndPerms,
      );
      debugPrint('[Phase0] loadCurrentUserRoles — found ${rolesAndPerms.length} role(s)');
    } catch (e, st) {
      debugPrint('[Phase0] loadCurrentUserRoles ERROR: $e');
      debugPrint('[Phase0] stackTrace: $st');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'โหลดข้อมูลสิทธิ์ล้มเหลว: $e',
      );
    }
  }

  // ========================
  // RBAC — Organization Roles
  // ========================

  /// โหลด roles ทั้งหมดของ profession
  Future<void> loadOrganizationRoles(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final roles = await _repository.getOrganizationRoles(professionId);
      state = state.copyWith(
        isLoading: false,
        organizationRoles: roles,
      );
    } catch (e, st) {
      debugPrint('[Phase0] loadOrganizationRoles ERROR: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'โหลดข้อมูลตำแหน่งล้มเหลว: $e',
      );
    }
  }

  /// เลือก role เพื่อดู/แก้ไข permissions
  Future<void> selectRole(OrganizationRole role) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final perms = await _repository.getRolePermissions(role.id);
      state = state.copyWith(
        isLoading: false,
        selectedRole: role,
        selectedRolePermissions: perms,
      );
    } catch (e, st) {
      debugPrint('[Phase0] selectRole ERROR: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'โหลด permissions ล้มเหลว: $e',
      );
    }
  }

  void clearSelectedRole() {
    state = state.copyWith(clearSelectedRole: true, selectedRolePermissions: []);
  }

  /// เปลี่ยนสถานะ active/inactive ของ role
  Future<bool> toggleOrganizationRoleActive(
    String roleId,
    bool isActive, {
    required String professionId,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final success = await _repository.toggleOrganizationRoleActive(
        roleId,
        isActive,
      );

      if (success) {
        await loadOrganizationRoles(professionId);
      } else {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'เปลี่ยนสถานะตำแหน่งไม่สำเร็จ',
        );
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase0] toggleOrganizationRoleActive ERROR: $e');
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'เปลี่ยนสถานะตำแหน่งล้มเหลว: $e',
      );
      return false;
    }
  }

  /// สร้าง role ใหม่
  Future<bool> createRole({
    required String professionId,
    required String roleName,
    String? roleDescription,
    List<RoleModulePermission> permissions = const [],
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final role = await _repository.createOrganizationRole(
        professionId: professionId,
        roleName: roleName,
        roleDescription: roleDescription,
      );

      if (role == null) {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'สร้างตำแหน่งไม่สำเร็จ',
        );
        return false;
      }

      if (permissions.isNotEmpty) {
        final permsWithRoleId = permissions.map((p) =>
            RoleModulePermission(
              id: '',
              roleId: role.id,
              moduleName: p.moduleName,
              accessLevel: p.accessLevel,
            )).toList();

        await _repository.updateRolePermissions(role.id, permsWithRoleId);
      }

      // โหลดใหม่
      await loadOrganizationRoles(professionId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase0] createRole ERROR: $e');
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'สร้างตำแหน่งล้มเหลว: $e',
      );
      return false;
    }
  }

  /// อัปเดต permissions ของ selected role
  Future<bool> updateSelectedRolePermissions(
    List<RoleModulePermission> permissions,
  ) async {
    final role = state.selectedRole;
    if (role == null) return false;

    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final success = await _repository.updateRolePermissions(role.id, permissions);
      if (success) {
        state = state.copyWith(
          isSaving: false,
          selectedRolePermissions: permissions,
        );
      } else {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'อัปเดต permissions ไม่สำเร็จ',
        );
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase0] updateSelectedRolePermissions ERROR: $e');
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'อัปเดต permissions ล้มเหลว: $e',
      );
      return false;
    }
  }

  // ========================
  // RBAC — User-Role Assignment (Phase 4: Permission Management UI)
  // ========================

  /// โหลดรายการ user ทั้งหมดใน profession พร้อม role
  Future<void> loadUsersWithRoles(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final users = await _repository.getUsersWithRoles(professionId);
      state = state.copyWith(
        isLoading: false,
        usersWithRoles: users,
      );
      debugPrint('[Phase0] loadUsersWithRoles — found ${users.length} user(s)');
    } catch (e, st) {
      debugPrint('[Phase0] loadUsersWithRoles ERROR: $e');
      debugPrint('[Phase0] stackTrace: $st');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'โหลดข้อมูล user พร้อม role ล้มเหลว: $e',
      );
    }
  }

  /// มอบ role ให้ user (wraps existing assignEmployeeRole)
  Future<bool> assignRoleToUser({
    required String professionId,
    required String userId,
    required String roleId,
    String? branchId,
    String? assignedBy,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final result = await _repository.assignEmployeeRole(
        professionId: professionId,
        userId: userId,
        roleId: roleId,
        branchId: branchId,
        assignedBy: assignedBy,
      );

      if (result == null) {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'มอบ role ไม่สำเร็จ',
        );
        return false;
      }

      // โหลดรายการใหม่
      await loadUsersWithRoles(professionId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase0] assignRoleToUser ERROR: $e');
      debugPrint('[Phase0] stackTrace: $st');
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'มอบ role ล้มเหลว: $e',
      );
      return false;
    }
  }

  /// ถอน role จาก user (delete row)
  Future<bool> revokeRoleFromUser({
    required String employeeRoleId,
    required String professionId,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final success = await _repository.removeEmployeeRole(employeeRoleId);

      if (!success) {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'ถอน role ไม่สำเร็จ',
        );
        return false;
      }

      // โหลดรายการใหม่
      await loadUsersWithRoles(professionId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase0] revokeRoleFromUser ERROR: $e');
      debugPrint('[Phase0] stackTrace: $st');
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'ถอน role ล้มเหลว: $e',
      );
      return false;
    }
  }

  // ========================
  // Feature Flags
  // ========================

  /// โหลด feature flags ของ profession
  Future<void> loadFeatureFlags(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final flags = await _repository.getProfessionFeatureFlags(professionId);
      state = state.copyWith(
        isLoading: false,
        featureFlags: flags,
      );
      debugPrint('[Phase0] loadFeatureFlags — found ${flags.length} flag(s)');
    } catch (e, st) {
      debugPrint('[Phase0] loadFeatureFlags ERROR: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'โหลด feature flags ล้มเหลว: $e',
      );
    }
  }

  /// อัปเดต/สร้าง feature flag
  Future<bool> setFeatureFlag({
    required String professionId,
    required String featureName,
    required String status,
    String? updatedBy,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final id = await _repository.upsertFeatureFlag(
        professionId: professionId,
        featureName: featureName,
        status: status,
        updatedBy: updatedBy,
      );

      if (id == null) {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'อัปเดต feature flag ไม่สำเร็จ',
        );
        return false;
      }

      // โหลดใหม่
      await loadFeatureFlags(professionId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase0] setFeatureFlag ERROR: $e');
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'อัปเดต feature flag ล้มเหลว: $e',
      );
      return false;
    }
  }

  /// สลับเปิด/ปิด feature flag
  Future<bool> toggleFeatureFlag(OrganizationFeatureFlag flag) async {
    final newStatus = flag.isEnabled ? 'disabled' : 'enabled';
    final user = AuthService.instance.currentUser;

    return setFeatureFlag(
      professionId: flag.professionId,
      featureName: flag.featureName,
      status: newStatus,
      updatedBy: user?.id,
    );
  }
}

// ========================
// Provider
// ========================

final phaseZeroProvider =
    StateNotifierProvider<PhaseZeroNotifier, PhaseZeroState>((ref) {
  final repo = ref.watch(phaseZeroRepositoryProvider);
  return PhaseZeroNotifier(repo);
});
