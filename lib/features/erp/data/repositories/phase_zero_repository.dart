import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_role.dart';
import '../models/organization_feature_flag.dart';
import '../models/organization_role.dart';
import '../models/role_module_permission.dart';
import '../models/transaction_audit_log.dart';
import '../models/circuit_breaker_state.dart';
import '../models/dead_letter_record.dart';
import '../models/retry_attempt.dart';

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
            'is_active': true,
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

  /// เปลี่ยนสถานะ active/inactive ของ role
  Future<bool> toggleOrganizationRoleActive(
    String roleId,
    bool isActive,
  ) async {
    try {
      await _client
          .from('organization_roles')
          .update({'is_active': isActive})
          .eq('id', roleId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase0Repo] toggleOrganizationRoleActive error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return false;
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

  /// ดึงรายการ user ทั้งหมดใน profession พร้อม role (เรียก RPC get_users_with_roles)
  Future<List<Map<String, dynamic>>> getUsersWithRoles(String professionId) async {
    try {
      final response = await _client.rpc(
        'get_users_with_roles',
        params: {'p_profession_id': professionId},
      );
      if (response == null) return [];
      return (response as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e, st) {
      debugPrint('[Phase0Repo] getUsersWithRoles error: $e');
      debugPrint('[Phase0Repo] stackTrace: $st');
      return [];
    }
  }

  /// ถอน role จาก user (delete row จาก employee_roles)
  Future<bool> removeEmployeeRole(String employeeRoleId) async {
    try {
      await _client
          .from('employee_roles')
          .delete()
          .eq('id', employeeRoleId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase0Repo] removeEmployeeRole error: $e');
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

  // ========================
  // RELIABILITY — Audit Log
  // ========================

  Future<List<TransactionAuditLog>> getAuditLogs({
    String? professionId,
    String? tableName,
    String? recordId,
    int limit = 100,
  }) async {
    try {
      var query = _client.from('transaction_audit_log').select();
      if (professionId != null) query = query.eq('profession_id', professionId);
      if (tableName != null) query = query.eq('table_name', tableName);
      if (recordId != null) query = query.eq('record_id', recordId);
      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => TransactionAuditLog.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase0Repo] getAuditLogs error: $e');
      return [];
    }
  }

  Future<int?> recordAuditLog({
    required String tableName,
    required String recordId,
    required String action,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
    String? actorId,
    String actorType = 'user',
    String? professionId,
    String? reason,
  }) async {
    try {
      final response = await _client.rpc(
        'record_audit_log',
        params: {
          'p_table_name': tableName,
          'p_record_id': recordId,
          'p_action': action,
          'p_old_values': oldValues,
          'p_new_values': newValues,
          'p_actor_id': actorId,
          'p_actor_type': actorType,
          'p_profession_id': professionId,
          'p_reason': reason,
        },
      );
      return response != null ? (response as num).toInt() : null;
    } catch (e, st) {
      debugPrint('[Phase0Repo] recordAuditLog error: $e');
      return null;
    }
  }

  // ========================
  // RELIABILITY — Circuit Breaker
  // ========================

  Future<List<CircuitBreakerState>> getCircuitBreakers(String professionId) async {
    try {
      final response = await _client
          .from('circuit_breaker_states')
          .select()
          .eq('profession_id', professionId)
          .order('updated_at', ascending: false);
      return (response as List)
          .map((e) => CircuitBreakerState.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase0Repo] getCircuitBreakers error: $e');
      return [];
    }
  }

  Future<String?> updateCircuitBreaker({
    required String professionId,
    required String serviceName,
    required String result, // 'success' or 'failure'
  }) async {
    try {
      final response = await _client.rpc(
        'update_circuit_breaker',
        params: {
          'p_profession_id': professionId,
          'p_service_name': serviceName,
          'p_result': result,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase0Repo] updateCircuitBreaker error: $e');
      return null;
    }
  }

  // ========================
  // RELIABILITY — Dead Letter
  // ========================

  Future<List<DeadLetterRecord>> getDeadLetterRecords(String professionId) async {
    try {
      final response = await _client
          .from('dead_letter_records')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => DeadLetterRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase0Repo] getDeadLetterRecords error: $e');
      return [];
    }
  }

  Future<bool> resolveDeadLetter({
    required String deadLetterId,
    required String resolution,
    String? resolvedBy,
  }) async {
    try {
      final response = await _client.rpc(
        'resolve_dead_letter',
        params: {
          'p_dead_letter_id': deadLetterId,
          'p_resolution': resolution,
          'p_resolved_by': resolvedBy,
        },
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase0Repo] resolveDeadLetter error: $e');
      return false;
    }
  }

  // ========================
  // RELIABILITY — Retry Attempts
  // ========================

  Future<List<RetryAttempt>> getRetryAttempts({
    required String professionId,
    String? operationType,
    String? targetId,
  }) async {
    try {
      var query = _client
          .from('retry_attempts')
          .select()
          .eq('profession_id', professionId);
      if (operationType != null) query = query.eq('operation_type', operationType);
      if (targetId != null) query = query.eq('target_id', targetId);
      final response = await query
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => RetryAttempt.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase0Repo] getRetryAttempts error: $e');
      return [];
    }
  }

  Future<String?> createRetryAttempt({
    required String professionId,
    required String operationType,
    required String targetId,
    int backoffMs = 2000,
  }) async {
    try {
      final response = await _client.rpc(
        'create_retry_attempt',
        params: {
          'p_profession_id': professionId,
          'p_operation_type': operationType,
          'p_target_id': targetId,
          'p_backoff_ms': backoffMs,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase0Repo] createRetryAttempt error: $e');
      return null;
    }
  }
}
