import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_role.dart';
import '../models/organization_feature_flag.dart';
import '../models/organization_role.dart';
import '../models/role_module_permission.dart';

/// Repository สำหรับ ERP Phase 0 — Reliability Core + RBAC + Feature Flags
class PhaseZeroRepository {
  final SupabaseClient _client;

  PhaseZeroRepository(this._client);

  // ========================
  // RBAC — User Roles & Permissions
  // ========================

  /// ดึง roles + permissions ของ user ใน profession ผ่าน RPC
  Future<List<Map<String, dynamic>>> getUserRolesAndPermissions(
    String userId,
    String professionId,
  ) async {
    try {
      final response = await _client.rpc(
        'get_user_roles_and_permissions',
        params: {
          'p_user_id': userId,
          'p_profession_id': professionId,
        },
      );
      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e, st) {
      debugPrint('[Phase0Repo] getUserRolesAndPermissions error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return [];
    }
  }

  /// ดึง roles ทั้งหมดของ profession
  Future<List<OrganizationRole>> getOrganizationRoles(String professionId) async {
    try {
      final response = await _client
          .from('organization_roles')
          .select()
          .eq('profession_id', professionId)
          .order('role_name');
      return (response as List)
          .map((e) => OrganizationRole.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase0Repo] getOrganizationRoles error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return [];
    }
  }

  /// สร้าง role ใหม่
  Future<OrganizationRole?> createOrganizationRole({
    required String professionId,
    required String roleName,
    String? roleDescription,
    bool isSystemRole = false,
  }) async {
    try {
      final response = await _client
          .from('organization_roles')
          .insert({
            'profession_id': professionId,
            'role_name': roleName,
            'role_description': roleDescription,
            'is_system_role': isSystemRole,
          })
          .select()
          .single();
      return OrganizationRole.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase0Repo] createOrganizationRole error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return null;
    }
  }

  /// อัปเดต permissions ของ role (ลบเก่าแล้ว insert ใหม่)
  Future<bool> updateRolePermissions(
    String roleId,
    List<RoleModulePermission> permissions,
  ) async {
    try {
      await _client
          .from('role_module_permissions')
          .delete()
          .eq('role_id', roleId);

      if (permissions.isNotEmpty) {
        final inserts = permissions
            .map((p) => {
                  'role_id': roleId,
                  'module_name': p.moduleName,
                  'access_level': p.accessLevel,
                })
            .toList();
        await _client.from('role_module_permissions').insert(inserts);
      }
      return true;
    } catch (e, st) {
      debugPrint('[Phase0Repo] updateRolePermissions error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return false;
    }
  }

  /// ดึง permissions ของ role
  Future<List<RoleModulePermission>> getRolePermissions(String roleId) async {
    try {
      final response = await _client
          .from('role_module_permissions')
          .select()
          .eq('role_id', roleId);
      return (response as List)
          .map((e) => RoleModulePermission.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase0Repo] getRolePermissions error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return [];
    }
  }

  /// assign role ให้ user
  Future<EmployeeRole?> assignEmployeeRole({
    required String professionId,
    required String userId,
    required String roleId,
    String? branchId,
    String? assignedBy,
  }) async {
    try {
      final response = await _client
          .from('employee_roles')
          .insert({
            'profession_id': professionId,
            'user_id': userId,
            'role_id': roleId,
            'branch_id': branchId,
            'assigned_by': assignedBy,
          })
          .select()
          .single();
      return EmployeeRole.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase0Repo] assignEmployeeRole error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return null;
    }
  }

  /// ปิด/เปิด employee role
  Future<bool> toggleEmployeeRole(String employeeRoleId, bool isActive) async {
    try {
      await _client
          .from('employee_roles')
          .update({'is_active': isActive})
          .eq('id', employeeRoleId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase0Repo] toggleEmployeeRole error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return false;
    }
  }

  // ========================
  // Feature Flags
  // ========================

  /// ดึง feature flags ของ profession ผ่าน RPC
  Future<List<OrganizationFeatureFlag>> getProfessionFeatureFlags(
    String professionId,
  ) async {
    try {
      final response = await _client.rpc(
        'get_profession_feature_flags',
        params: {'p_profession_id': professionId},
      );
      if (response == null) return [];
      return (response as List)
          .map((e) => OrganizationFeatureFlag.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase0Repo] getProfessionFeatureFlags error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return [];
    }
  }

  /// อัปเดต/สร้าง feature flag ผ่าน RPC
  Future<String?> upsertFeatureFlag({
    required String professionId,
    required String featureName,
    required String status,
    String? updatedBy,
  }) async {
    try {
      final response = await _client.rpc(
        'upsert_feature_flag',
        params: {
          'p_profession_id': professionId,
          'p_feature_name': featureName,
          'p_status': status,
          'p_updated_by': updatedBy,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase0Repo] upsertFeatureFlag error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return null;
    }
  }

  // ========================
  // Transaction Context (Reliability Core)
  // ========================

  /// สร้าง transaction context ผ่าน RPC
  Future<String?> createTransactionContext({
    required String professionId,
    required String transactionId,
    required String sourceModule,
    required String operationType,
    Map<String, dynamic> metadata = const {},
    String? createdBy,
  }) async {
    try {
      final response = await _client.rpc(
        'create_transaction_context',
        params: {
          'p_profession_id': professionId,
          'p_transaction_id': transactionId,
          'p_source_module': sourceModule,
          'p_operation_type': operationType,
          'p_metadata': metadata,
          'p_created_by': createdBy,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase0Repo] createTransactionContext error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return null;
    }
  }

  /// อัปเดต transaction context ผ่าน RPC
  Future<bool> updateTransactionContext({
    required String transactionContextId,
    required String status,
    List<Map<String, dynamic>>? steps,
  }) async {
    try {
      final response = await _client.rpc(
        'update_transaction_context',
        params: {
          'p_transaction_context_id': transactionContextId,
          'p_status': status,
          'p_steps': steps,
        },
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase0Repo] updateTransactionContext error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return false;
    }
  }
}
