import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';
import '../models/gl_entry.dart';
import '../models/dashboard_snapshot.dart';
import '../models/chart_of_account.dart';
import '../models/accounts_receivable.dart';
import '../models/accounts_payable.dart';
import '../models/shift.dart';

/// Repository สำหรับ ERP Phase 3 — Finance & Operations + Read Model
class PhaseThreeRepository {
  final SupabaseClient _client;

  PhaseThreeRepository(this._client);

  // ========================
  // EMPLOYEES (HR Core)
  // ========================

  Future<List<Employee>> getEmployees(String professionId) async {
    try {
      final response = await _client
          .from('employees')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('full_name');
      return (response as List)
          .map((e) => Employee.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getEmployees error: $e');
      return [];
    }
  }

  Future<Employee?> createEmployee(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('employees')
          .insert(data)
          .select()
          .single();
      return Employee.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] createEmployee error: $e');
      return null;
    }
  }

  Future<bool> updateEmployee(String id, Map<String, dynamic> data) async {
    try {
      await _client.from('employees').update(data).eq('id', id);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] updateEmployee error: $e');
      return false;
    }
  }

  // ========================
  // GL ENTRIES (Accounting Core)
  // ========================

  Future<List<GlEntry>> getGlEntries(String professionId, {int limit = 50}) async {
    try {
      final response = await _client
          .from('gl_entries')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => GlEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getGlEntries error: $e');
      return [];
    }
  }

  Future<bool> createGlFromOrder(String orderId) async {
    try {
      final response = await _client.rpc(
        'create_gl_from_order',
        params: {'p_order_id': orderId},
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase3Repo] createGlFromOrder error: $e');
      return false;
    }
  }

  Future<GlEntry?> createGlEntry(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('gl_entries')
          .insert(data)
          .select()
          .single();
      return GlEntry.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] createGlEntry error: $e');
      return null;
    }
  }

  // ========================
  // DASHBOARD SNAPSHOTS (Read Model)
  // ========================

  Future<List<DashboardSnapshot>> getDashboardSnapshots(
    String professionId, {
    String type = 'daily',
    int limit = 30,
  }) async {
    try {
      final response = await _client
          .from('dashboard_snapshots')
          .select()
          .eq('profession_id', professionId)
          .eq('snapshot_type', type)
          .order('snapshot_date', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => DashboardSnapshot.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getDashboardSnapshots error: $e');
      return [];
    }
  }

  Future<String?> upsertDashboardSnapshot({
    required String professionId,
    required String type,
    required Map<String, dynamic> metrics,
  }) async {
    try {
      final response = await _client.rpc(
        'upsert_dashboard_snapshot',
        params: {
          'p_profession_id': professionId,
          'p_snapshot_type': type,
          'p_metrics': metrics,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase3Repo] upsertDashboardSnapshot error: $e');
      return null;
    }
  }

  // ========================
  // CHART OF ACCOUNTS
  // ========================

  Future<List<ChartOfAccount>> getChartOfAccounts(String professionId) async {
    try {
      final response = await _client
          .from('chart_of_accounts')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('account_code');
      return (response as List)
          .map((e) => ChartOfAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getChartOfAccounts error: $e');
      return [];
    }
  }

  Future<ChartOfAccount?> createChartOfAccount(Map<String, dynamic> data) async {
    try {
      final mode = await getChartOfAccountsAccountTypeMode();
      final payload = Map<String, dynamic>.from(data);
      if (payload['account_type'] is String) {
        payload['account_type'] = _normalizeAccountTypeForStorage(
          payload['account_type'] as String,
          mode,
        );
      }
      payload['is_custom'] = true;
      final response = await _client
          .from('chart_of_accounts')
          .insert(payload)
          .select()
          .single();
      return ChartOfAccount.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] createChartOfAccount error: $e');
      return null;
    }
  }

  Future<bool> updateChartOfAccount(String id, Map<String, dynamic> data) async {
    try {
      final mode = await getChartOfAccountsAccountTypeMode();
      final payload = Map<String, dynamic>.from(data);
      if (payload['account_type'] is String) {
        payload['account_type'] = _normalizeAccountTypeForStorage(
          payload['account_type'] as String,
          mode,
        );
      }
      payload['is_custom'] = true;
      await _client.from('chart_of_accounts').update(payload).eq('id', id);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] updateChartOfAccount error: $e');
      return false;
    }
  }

  Future<bool> ensureChartOfAccountsSeeded(String professionId) async {
    try {
      await _client.rpc(
        'seed_profession_chart_of_accounts',
        params: {'p_profession_id': professionId},
      );
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] ensureChartOfAccountsSeeded error: $e');
      return false;
    }
  }

  Future<bool> resetChartOfAccountToStandard(String accountId) async {
    try {
      final response = await _client.rpc(
        'reset_chart_of_account_to_standard',
        params: {'p_account_id': accountId},
      );
      return response == true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] resetChartOfAccountToStandard error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getChartOfAccountDependencies(String accountId) async {
    try {
      final response = await _client.rpc(
        'get_chart_of_account_dependencies',
        params: {'p_account_id': accountId},
      );
      return response as Map<String, dynamic>?;
    } catch (e, st) {
      debugPrint('[Phase3Repo] getChartOfAccountDependencies error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> deleteChartOfAccount(String accountId) async {
    try {
      final response = await _client.rpc(
        'delete_chart_of_account',
        params: {'p_account_id': accountId},
      );
      return (response as Map<String, dynamic>?) ?? {'success': false, 'error': 'No response'};
    } catch (e, st) {
      debugPrint('[Phase3Repo] deleteChartOfAccount error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<String> getChartOfAccountsAccountTypeMode() async {
    try {
      final response = await _client.rpc('get_chart_of_accounts_account_type_mode');
      return response?.toString() ?? 'text';
    } catch (e, st) {
      debugPrint('[Phase3Repo] getChartOfAccountsAccountTypeMode error: $e');
      return 'text';
    }
  }

  dynamic _normalizeAccountTypeForStorage(String accountType, String mode) {
    if (mode == 'numeric') {
      switch (accountType) {
        case 'asset':
          return 1;
        case 'liability':
          return 2;
        case 'equity':
          return 3;
        case 'revenue':
          return 4;
        case 'expense':
          return 5;
        default:
          return 1;
      }
    }
    return accountType;
  }

  // ========================
  // ACCOUNTS RECEIVABLE (AR)
  // ========================

  Future<List<AccountsReceivable>> getAccountsReceivable(
    String professionId, {
    String? status,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('accounts_receivable')
          .select()
          .eq('profession_id', professionId);
      if (status != null) {
        query = query.eq('status', status);
      }
      final response = await query
          .order('due_date', ascending: true)
          .limit(limit);
      return (response as List)
          .map((e) => AccountsReceivable.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getAccountsReceivable error: $e');
      return [];
    }
  }

  Future<bool> updateArStatus(String id, String status, {double? paidAmount}) async {
    try {
      final data = <String, dynamic>{'status': status};
      if (paidAmount != null) {
        data['paid_amount'] = paidAmount;
      }
      await _client.from('accounts_receivable').update(data).eq('id', id);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] updateArStatus error: $e');
      return false;
    }
  }

  // ========================
  // ACCOUNTS PAYABLE (AP)
  // ========================

  Future<List<AccountsPayable>> getAccountsPayable(
    String professionId, {
    String? status,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('accounts_payable')
          .select()
          .eq('profession_id', professionId);
      if (status != null) {
        query = query.eq('status', status);
      }
      final response = await query
          .order('due_date', ascending: true)
          .limit(limit);
      return (response as List)
          .map((e) => AccountsPayable.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getAccountsPayable error: $e');
      return [];
    }
  }

  Future<bool> updateApStatus(String id, String status, {double? paidAmount}) async {
    try {
      final data = <String, dynamic>{'status': status};
      if (paidAmount != null) {
        data['paid_amount'] = paidAmount;
      }
      await _client.from('accounts_payable').update(data).eq('id', id);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] updateApStatus error: $e');
      return false;
    }
  }

  // ========================
  // SHIFTS (HR)
  // ========================

  Future<List<Shift>> getShifts(
    String professionId, {
    String? employeeId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 100,
  }) async {
    try {
      var query = _client
          .from('shifts')
          .select()
          .eq('profession_id', professionId);
      if (employeeId != null) {
        query = query.eq('employee_id', employeeId);
      }
      if (fromDate != null) {
        query = query.gte('shift_date', fromDate.toIso8601String());
      }
      if (toDate != null) {
        query = query.lte('shift_date', toDate.toIso8601String());
      }
      final response = await query
          .order('shift_date', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => Shift.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getShifts error: $e');
      return [];
    }
  }

  Future<Shift?> createShift(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('shifts')
          .insert(data)
          .select()
          .single();
      return Shift.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] createShift error: $e');
      return null;
    }
  }

  Future<bool> updateShift(String id, Map<String, dynamic> data) async {
    try {
      await _client.from('shifts').update(data).eq('id', id);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] updateShift error: $e');
      return false;
    }
  }
}
