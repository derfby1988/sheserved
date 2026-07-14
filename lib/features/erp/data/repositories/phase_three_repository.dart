import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';
import '../models/employee_invitation.dart';
import '../../../../services/auth_service.dart';
import '../models/gl_entry.dart';
import '../models/dashboard_snapshot.dart';
import '../models/chart_of_account.dart';
import '../models/accounts_receivable.dart';
import '../models/accounts_payable.dart';
import '../models/shift.dart';
import '../models/settlement_ledger.dart';
import '../models/payroll_run.dart';
import '../models/payroll_item.dart';
import '../models/hr_settings.dart';
import '../models/thai_holiday.dart';
import '../models/employee_tax_allowance.dart';

/// Repository สำหรับ ERP Phase 3 — Finance & Operations + Read Model
class PhaseThreeRepository {
  final SupabaseClient _client;

  PhaseThreeRepository(this._client);

  // ========================
  // EMPLOYEES (HR Core)
  // ========================

  Future<List<Employee>> getEmployees(String professionId, {bool includeInactive = false}) async {
    try {
      var query = _client
          .from('employees')
          .select()
          .eq('profession_id', professionId);
      if (!includeInactive) {
        query = query.eq('is_active', true);
      }
      final response = await query.order('is_active', ascending: false).order('full_name');
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
      final userId = AuthService.instance.currentUser?.id;
      final enrichedData = Map<String, dynamic>.from(data);
      if (userId != null && userId.isNotEmpty) {
        enrichedData['created_by'] = userId;
        enrichedData['updated_by'] = userId;
      }
      final response = await _client
          .from('employees')
          .insert(enrichedData)
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
      final userId = AuthService.instance.currentUser?.id;
      final enrichedData = Map<String, dynamic>.from(data);
      if (userId != null && userId.isNotEmpty) {
        enrichedData['updated_by'] = userId;
      }
      await _client.from('employees').update(enrichedData).eq('id', id);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] updateEmployee error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableUsersForInvite(
    String professionId, {
    String? search,
  }) async {
    try {
      final response = await _client.rpc(
        'get_available_users_for_invite',
        params: {
          'p_profession_id': professionId,
          if (search != null && search.isNotEmpty) 'p_search': search,
        },
      );
      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e, st) {
      debugPrint('[Phase3Repo] getAvailableUsersForInvite error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> inviteEmployee(Map<String, dynamic> data) async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      final response = await _client.rpc(
        'invite_employee',
        params: {
          'p_profession_id': data['profession_id'],
          'p_invited_by': userId,
          if (data['user_id'] != null) 'p_user_id': data['user_id'],
          if (data['email'] != null) 'p_email': data['email'],
          if (data['phone'] != null) 'p_phone': data['phone'],
          'p_full_name': data['full_name'],
          if (data['employee_code'] != null) 'p_employee_code': data['employee_code'],
          if (data['department'] != null) 'p_department': data['department'],
          if (data['job_title'] != null) 'p_job_title': data['job_title'],
          if (data['branch_id'] != null) 'p_branch_id': data['branch_id'],
          if (data['base_salary'] != null) 'p_base_salary': data['base_salary'],
          if (data['salary'] != null) 'p_salary': data['salary'],
          if (data['commission_rate'] != null) 'p_commission_rate': data['commission_rate'],
          if (data['provident_fund_rate'] != null) 'p_provident_fund_rate': data['provident_fund_rate'],
          if (data['personal_allowance'] != null) 'p_personal_allowance': data['personal_allowance'],
          if (data['tax_deductible_expenses'] != null) 'p_tax_deductible_expenses': data['tax_deductible_expenses'],
          if (data['payment_method'] != null) 'p_payment_method': data['payment_method'],
          if (data['bank_name'] != null) 'p_bank_name': data['bank_name'],
          if (data['bank_account_number'] != null) 'p_bank_account_number': data['bank_account_number'],
          if (data['intended_role_name'] != null) 'p_intended_role_name': data['intended_role_name'],
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e, st) {
      debugPrint('[Phase3Repo] inviteEmployee error: $e');
      return null;
    }
  }

  Future<List<EmployeeInvitation>> getEmployeeInvitations(String professionId) async {
    try {
      final response = await _client
          .from('employee_invitations')
          .select('*, cancelled_by_user:users!cancelled_by(first_name, last_name, username, email)')
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => EmployeeInvitation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getEmployeeInvitations error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> acceptEmployeeInvitation(String token) async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      final response = await _client.rpc(
        'accept_employee_invitation',
        params: {
          'p_token': token,
          if (userId != null) 'p_user_id': userId,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e, st) {
      debugPrint('[Phase3Repo] acceptEmployeeInvitation error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> rejectEmployeeInvitation(
    String token, {
    String? rejectionReason,
  }) async {
    try {
      final response = await _client.rpc(
        'reject_employee_invitation',
        params: {
          'p_token': token,
          if (rejectionReason != null && rejectionReason.isNotEmpty)
            'p_rejection_reason': rejectionReason,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e, st) {
      debugPrint('[Phase3Repo] rejectEmployeeInvitation error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> cancelEmployeeInvitation(
    String token, {
    required String cancelledBy,
    String? cancellationReason,
  }) async {
    try {
      final response = await _client.rpc(
        'cancel_employee_invitation',
        params: {
          'p_token': token,
          'p_cancelled_by': cancelledBy,
          if (cancellationReason != null && cancellationReason.isNotEmpty)
            'p_cancellation_reason': cancellationReason,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e, st) {
      debugPrint('[Phase3Repo] cancelEmployeeInvitation error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getCancelledInvitationsForUser() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return [];
    try {
      final response = await _client.rpc(
        'get_cancelled_invitations_for_user',
        params: {'p_user_id': userId},
      );
      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e, st) {
      debugPrint('[Phase3Repo] getCancelledInvitationsForUser error: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getPendingInvitationsForCurrentUser() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return [];
    try {
      final response = await _client.rpc(
        'get_pending_employee_invitations_for_user',
        params: {'p_user_id': userId},
      );
      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e, st) {
      debugPrint('[Phase3Repo] getPendingInvitationsForCurrentUser error: $e\n$st');
      return [];
    }
  }

  Future<Map<String, dynamic>?> ensureOwnerAsEmployee(String professionId) async {
    try {
      final currentUserId = AuthService.instance.currentUser?.id;
      final response = await _client.rpc(
        'ensure_owner_as_employee',
        params: {
          'p_profession_id': professionId,
          'p_current_user_id': currentUserId,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e, st) {
      debugPrint('[Phase3Repo] ensureOwnerAsEmployee error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> terminateEmployee({
    required String employeeId,
    String? terminationReason,
    DateTime? terminationDate,
    bool canReinvite = true,
    DateTime? reinviteEligibleAt,
  }) async {
    try {
      final currentUserId = AuthService.instance.currentUser?.id;
      final response = await _client.rpc(
        'terminate_employee',
        params: {
          'p_employee_id': employeeId,
          'p_terminated_by': currentUserId,
          if (terminationReason != null && terminationReason.isNotEmpty)
            'p_termination_reason': terminationReason,
          if (terminationDate != null)
            'p_termination_date': terminationDate.toIso8601String().split('T')[0],
          'p_can_reinvite': canReinvite,
          if (reinviteEligibleAt != null)
            'p_reinvite_eligible_at': reinviteEligibleAt.toIso8601String(),
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e, st) {
      debugPrint('[Phase3Repo] terminateEmployee error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getInvitationHistoryForUser({
    required String professionId,
    String? userId,
    String? email,
    String? phone,
  }) async {
    try {
      final response = await _client.rpc(
        'get_invitation_history_for_user',
        params: {
          'p_profession_id': professionId,
          if (userId != null && userId.isNotEmpty) 'p_user_id': userId,
          if (email != null && email.isNotEmpty) 'p_email': email,
          if (phone != null && phone.isNotEmpty) 'p_phone': phone,
        },
      );
      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e, st) {
      debugPrint('[Phase3Repo] getInvitationHistoryForUser error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getOrganizationRoles(String professionId) async {
    try {
      final response = await _client
          .from('organization_roles')
          .select('id, role_name')
          .eq('profession_id', professionId)
          .order('role_name');
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getOrganizationRoles error: $e');
      return [];
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
  // PAYROLL (HR Core)
  // ========================

  Future<List<PayrollRun>> getPayrollRuns(
    String professionId, {
    String? status,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('payroll_runs')
          .select()
          .eq('profession_id', professionId);
      if (status != null) {
        query = query.eq('status', status);
      }
      final response = await query
          .order('period_start', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => PayrollRun.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getPayrollRuns error: $e');
      return [];
    }
  }

  Future<PayrollRun?> createPayrollRun(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('payroll_runs')
          .insert(data)
          .select()
          .single();
      return PayrollRun.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] createPayrollRun error: $e');
      return null;
    }
  }

  Future<bool> updatePayrollRun(String id, Map<String, dynamic> data) async {
    try {
      await _client.from('payroll_runs').update(data).eq('id', id);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] updatePayrollRun error: $e');
      return false;
    }
  }

  Future<List<PayrollItem>> getPayrollItems(String payrollRunId) async {
    try {
      final response = await _client
          .from('payroll_items')
          .select()
          .eq('payroll_run_id', payrollRunId)
          .order('created_at', ascending: true);
      return (response as List)
          .map((e) => PayrollItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getPayrollItems error: $e');
      return [];
    }
  }

  Future<bool> insertPayrollItems(List<Map<String, dynamic>> items) async {
    try {
      await _client.from('payroll_items').insert(items);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] insertPayrollItems error: $e');
      return false;
    }
  }

  Future<HrSettings?> getHrSettings(String professionId) async {
    try {
      final response = await _client
          .from('hr_settings')
          .select()
          .eq('profession_id', professionId)
          .maybeSingle();
      if (response == null) return null;
      return HrSettings.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] getHrSettings error: $e');
      return null;
    }
  }

  Future<HrSettings?> upsertHrSettings(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('hr_settings')
          .upsert(data)
          .select()
          .single();
      return HrSettings.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] upsertHrSettings error: $e');
      return null;
    }
  }

  Future<Map<String, double>> calculateEmployeePayroll({
    required String employeeId,
    required String professionId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required HrSettings settings,
    required double baseSalary,
  }) async {
    final result = <String, double>{};

    result['base_salary'] = baseSalary;

    try {
      final otResponse = await _client
          .from('time_attendances')
          .select('attendance_status')
          .eq('profession_id', professionId)
          .eq('employee_id', employeeId)
          .gte('clock_in_time', periodStart.toIso8601String())
          .lte('clock_in_time', periodEnd.toIso8601String());

      final attendances = otResponse as List;
      int otCount = 0;
      int lateCount = 0;
      int absentCount = 0;
      for (final att in attendances) {
        final status = att['attendance_status'] as String? ?? 'on_time';
        if (status == 'overtime') otCount++;
        if (status == 'late') lateCount++;
        if (status == 'absent') absentCount++;
      }

      final hourlyRate = baseSalary / (settings.defaultWorkHoursPerDay * 30);
      final otAmount = otCount * hourlyRate * settings.otMultiplierWeekday;
      result['overtime'] = otAmount;

      final isDiligent = lateCount == 0 && absentCount == 0;
      result['diligence_allowance'] =
          isDiligent ? settings.diligenceAllowanceAmount : 0.0;
    } catch (e) {
      result['overtime'] = 0.0;
      result['diligence_allowance'] = 0.0;
    }

    try {
      final commResponse = await _client
          .from('commissions')
          .select('calculated_amount, adjusted_amount, status')
          .eq('profession_id', professionId)
          .eq('employee_id', employeeId)
          .eq('status', 'approved')
          .gte('period_start', periodStart.toIso8601String().split('T')[0])
          .lte('period_end', periodEnd.toIso8601String().split('T')[0]);

      double commissionTotal = 0;
      for (final comm in commResponse as List) {
        final adjusted = (comm['adjusted_amount'] as num?)?.toDouble();
        final calculated = (comm['calculated_amount'] as num?)?.toDouble() ?? 0;
        commissionTotal += adjusted ?? calculated;
      }
      result['commission'] = commissionTotal;
    } catch (e) {
      result['commission'] = 0.0;
    }

    final socialSecurity =
        (baseSalary * settings.socialSecurityRate).clamp(0.0, 750.0);
    result['social_security'] = socialSecurity;

    final gross = (result['base_salary'] ?? 0) +
        (result['overtime'] ?? 0) +
        (result['diligence_allowance'] ?? 0) +
        (result['commission'] ?? 0);
    final deductions = result['social_security'] ?? 0;
    result['gross'] = gross;
    result['deductions'] = deductions;
    result['net'] = gross - deductions;

    return result;
  }

  /// Server-side payroll calculation via RPC (preferred over client-side)
  Future<PayrollRun?> runPayrollCalculationRpc({
    required String payrollRunId,
    required String professionId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    try {
      final response = await _client.rpc(
        'run_payroll_calculation',
        params: {
          'p_payroll_run_id': payrollRunId,
          'p_profession_id': professionId,
          'p_period_start': periodStart.toIso8601String().split('T')[0],
          'p_period_end': periodEnd.toIso8601String().split('T')[0],
        },
      );
      if (response == null) return null;
      return PayrollRun.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] runPayrollCalculationRpc error: $e');
      return null;
    }
  }

  /// Server-side payroll approval via RPC (preferred — auto-creates GL entries)
  Future<PayrollRun?> approvePayrollRunRpc({
    required String payrollRunId,
    required String approvedBy,
  }) async {
    try {
      final response = await _client.rpc(
        'approve_payroll_run',
        params: {
          'p_payroll_run_id': payrollRunId,
          'p_approved_by': approvedBy,
        },
      );
      if (response == null) return null;
      return PayrollRun.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] approvePayrollRunRpc error: $e');
      return null;
    }
  }

  // ========================
  // OUTBOX EVENTS (Payroll → Accounting)
  // ========================

  Future<bool> insertOutboxEvent({
    required String professionId,
    required String aggregateType,
    required String aggregateId,
    required String eventType,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await _client.from('outbox_events').insert({
        'profession_id': professionId,
        'aggregate_type': aggregateType,
        'aggregate_id': aggregateId,
        'event_type': eventType,
        'payload': payload,
        'status': 'pending',
      });
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] insertOutboxEvent error: $e');
      return false;
    }
  }

  // ========================
  // SETTLEMENT LEDGERS (Settlement Core)
  // ========================

  Future<List<SettlementLedger>> getSettlementLedgers(
    String professionId, {
    String? status,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('settlement_ledgers')
          .select()
          .eq('profession_id', professionId);
      if (status != null) {
        query = query.eq('status', status);
      }
      final response = await query
          .order('period_end', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => SettlementLedger.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getSettlementLedgers error: $e');
      return [];
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

  // ========================
  // THAI HOLIDAYS (OT Multiplier)
  // ========================

  Future<List<ThaiHoliday>> getThaiHolidays({int? year}) async {
    try {
      if (year != null) {
        final startOfYear = DateTime(year, 1, 1).toIso8601String().split('T')[0];
        final endOfYear = DateTime(year, 12, 31).toIso8601String().split('T')[0];
        final response = await _client
            .from('thai_holidays')
            .select()
            .eq('is_active', true)
            .gte('holiday_date', startOfYear)
            .lte('holiday_date', endOfYear)
            .order('holiday_date');
        return (response as List)
            .map((e) => ThaiHoliday.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        final response = await _client
            .from('thai_holidays')
            .select()
            .eq('is_active', true)
            .order('holiday_date');
        return (response as List)
            .map((e) => ThaiHoliday.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e, st) {
      debugPrint('[Phase3Repo] getThaiHolidays error: $e');
      return [];
    }
  }

  Future<ThaiHoliday?> upsertThaiHoliday(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('thai_holidays')
          .upsert(data)
          .select()
          .single();
      return ThaiHoliday.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] upsertThaiHoliday error: $e');
      return null;
    }
  }

  Future<bool> deleteThaiHoliday(String id) async {
    try {
      await _client.from('thai_holidays').update({'is_active': false}).eq('id', id);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] deleteThaiHoliday error: $e');
      return false;
    }
  }

  // ========================
  // EMPLOYEE TAX ALLOWANCES
  // ========================

  Future<List<EmployeeTaxAllowance>> getTaxAllowances(
    String employeeId, {
    int? year,
  }) async {
    try {
      var query = _client
          .from('employee_tax_allowances')
          .select()
          .eq('employee_id', employeeId);
      if (year != null) {
        query = query.eq('effective_year', year);
      }
      final response = await query.order('allowance_type');
      return (response as List)
          .map((e) => EmployeeTaxAllowance.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getTaxAllowances error: $e');
      return [];
    }
  }

  Future<EmployeeTaxAllowance?> createTaxAllowance(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('employee_tax_allowances')
          .insert(data)
          .select()
          .single();
      return EmployeeTaxAllowance.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] createTaxAllowance error: $e');
      return null;
    }
  }

  Future<bool> deleteTaxAllowance(String id) async {
    try {
      await _client.from('employee_tax_allowances').delete().eq('id', id);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3Repo] deleteTaxAllowance error: $e');
      return false;
    }
  }

  // ========================
  // HR SETTINGS RPC (with new fields)
  // ========================

  Future<HrSettings?> upsertHrSettingsRpc(Map<String, dynamic> params) async {
    try {
      final response = await _client.rpc(
        'upsert_hr_settings',
        params: params,
      );
      if (response == null) return null;
      return HrSettings.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] upsertHrSettingsRpc error: $e');
      return null;
    }
  }
}
