import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/employee.dart';
import '../../data/models/employee_invitation.dart';
import '../../data/models/gl_entry.dart';
import '../../data/models/dashboard_snapshot.dart';
import '../../data/models/chart_of_account.dart';
import '../../data/models/accounts_receivable.dart';
import '../../data/models/accounts_payable.dart';
import '../../data/models/shift.dart';
import '../../data/models/settlement_ledger.dart';
import '../../data/models/payroll_run.dart';
import '../../data/models/payroll_item.dart';
import '../../data/models/hr_settings.dart';
import '../../data/models/thai_holiday.dart';
import '../../data/models/employee_tax_allowance.dart';
import '../../data/repositories/phase_three_repository.dart';

final phaseThreeRepositoryProvider = Provider<PhaseThreeRepository>((ref) {
  return PhaseThreeRepository(Supabase.instance.client);
});

// ========================
// State
// ========================
class PhaseThreeState {
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  final List<Employee> employees;
  final List<EmployeeInvitation> employeeInvitations;
  final List<Map<String, dynamic>> availableUsersForInvite;
  final List<Map<String, dynamic>> pendingInvitationsForCurrentUser;
  final List<GlEntry> glEntries;
  final List<DashboardSnapshot> snapshots;
  final List<ChartOfAccount> chartOfAccounts;
  final List<AccountsReceivable> accountsReceivable;
  final List<AccountsPayable> accountsPayable;
  final List<Shift> shifts;
  final List<SettlementLedger> settlementLedgers;
  final List<PayrollRun> payrollRuns;
  final List<PayrollItem> payrollItems;
  final HrSettings? hrSettings;
  final List<ThaiHoliday> thaiHolidays;
  final List<EmployeeTaxAllowance> taxAllowances;

  PhaseThreeState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.employees = const [],
    this.employeeInvitations = const [],
    this.availableUsersForInvite = const [],
    this.pendingInvitationsForCurrentUser = const [],
    this.glEntries = const [],
    this.snapshots = const [],
    this.chartOfAccounts = const [],
    this.accountsReceivable = const [],
    this.accountsPayable = const [],
    this.shifts = const [],
    this.settlementLedgers = const [],
    this.payrollRuns = const [],
    this.payrollItems = const [],
    this.hrSettings,
    this.thaiHolidays = const [],
    this.taxAllowances = const [],
  });

  PhaseThreeState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    List<Employee>? employees,
    List<EmployeeInvitation>? employeeInvitations,
    List<Map<String, dynamic>>? availableUsersForInvite,
    List<Map<String, dynamic>>? pendingInvitationsForCurrentUser,
    List<GlEntry>? glEntries,
    List<DashboardSnapshot>? snapshots,
    List<ChartOfAccount>? chartOfAccounts,
    List<AccountsReceivable>? accountsReceivable,
    List<AccountsPayable>? accountsPayable,
    List<Shift>? shifts,
    List<SettlementLedger>? settlementLedgers,
    List<PayrollRun>? payrollRuns,
    List<PayrollItem>? payrollItems,
    HrSettings? hrSettings,
    List<ThaiHoliday>? thaiHolidays,
    List<EmployeeTaxAllowance>? taxAllowances,
  }) {
    final shouldClearError = clearError ||
        ((isLoading != null && !isLoading) || (isSaving != null && !isSaving));
    return PhaseThreeState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      employees: employees ?? this.employees,
      employeeInvitations: employeeInvitations ?? this.employeeInvitations,
      availableUsersForInvite: availableUsersForInvite ?? this.availableUsersForInvite,
      pendingInvitationsForCurrentUser: pendingInvitationsForCurrentUser ?? this.pendingInvitationsForCurrentUser,
      glEntries: glEntries ?? this.glEntries,
      snapshots: snapshots ?? this.snapshots,
      chartOfAccounts: chartOfAccounts ?? this.chartOfAccounts,
      accountsReceivable: accountsReceivable ?? this.accountsReceivable,
      accountsPayable: accountsPayable ?? this.accountsPayable,
      shifts: shifts ?? this.shifts,
      settlementLedgers: settlementLedgers ?? this.settlementLedgers,
      payrollRuns: payrollRuns ?? this.payrollRuns,
      payrollItems: payrollItems ?? this.payrollItems,
      hrSettings: hrSettings ?? this.hrSettings,
      thaiHolidays: thaiHolidays ?? this.thaiHolidays,
      taxAllowances: taxAllowances ?? this.taxAllowances,
    );
  }
}

// ========================
// Notifier
// ========================
class PhaseThreeNotifier extends StateNotifier<PhaseThreeState> {
  final PhaseThreeRepository _repository;

  PhaseThreeNotifier(this._repository) : super(PhaseThreeState());

  // ========================
  // EMPLOYEES
  // ========================

  Future<void> loadEmployees(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final employees = await _repository.getEmployees(professionId);
      state = state.copyWith(isLoading: false, employees: employees);
    } catch (e, st) {
      debugPrint('[Phase3] loadEmployees ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดข้อมูลพนักงานล้มเหลว: $e');
    }
  }

  Future<Employee?> createEmployee(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final employee = await _repository.createEmployee(data);
      if (employee != null) {
        final updated = [...state.employees, employee];
        state = state.copyWith(isSaving: false, employees: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return employee;
    } catch (e, st) {
      debugPrint('[Phase3] createEmployee ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างพนักงานล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> updateEmployee(String id, Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updateEmployee(id, data);
      if (success) {
        final updated = state.employees.map((e) {
          if (e.id == id) {
            return Employee(
              id: e.id,
              professionId: e.professionId,
              employeeCode: data['employee_code'] as String? ?? e.employeeCode,
              fullName: data['full_name'] as String? ?? e.fullName,
              email: data['email'] as String? ?? e.email,
              phone: data['phone'] as String? ?? e.phone,
              department: data['department'] as String? ?? e.department,
              jobTitle: data['job_title'] as String? ?? e.jobTitle,
              hireDate: data['hire_date'] != null
                  ? DateTime.parse(data['hire_date'] as String)
                  : e.hireDate,
              salary: data['salary'] != null
                  ? (data['salary'] as num).toDouble()
                  : e.salary,
              baseSalary: data['base_salary'] != null
                  ? (data['base_salary'] as num).toDouble()
                  : e.baseSalary,
              taxDeductibleExpenses: data['tax_deductible_expenses'] != null
                  ? (data['tax_deductible_expenses'] as num).toDouble()
                  : e.taxDeductibleExpenses,
              personalAllowance: data['personal_allowance'] != null
                  ? (data['personal_allowance'] as num).toDouble()
                  : e.personalAllowance,
              providentFundRate: data['provident_fund_rate'] != null
                  ? (data['provident_fund_rate'] as num).toDouble()
                  : e.providentFundRate,
              paymentMethod: data['payment_method'] as String? ?? e.paymentMethod,
              bankAccountNumber: data['bank_account_number'] as String? ?? e.bankAccountNumber,
              bankName: data['bank_name'] as String? ?? e.bankName,
              commissionRate: data['commission_rate'] != null
                  ? (data['commission_rate'] as num).toDouble()
                  : e.commissionRate,
              branchId: data['branch_id'] as String? ?? e.branchId,
              isActive: data['is_active'] as bool? ?? e.isActive,
              createdAt: e.createdAt,
              updatedAt: DateTime.now(),
            );
          }
          return e;
        }).toList();
        state = state.copyWith(isSaving: false, employees: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase3] updateEmployee ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อัปเดตพนักงานล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // EMPLOYEE INVITATIONS
  // ========================

  Future<void> loadEmployeeInvitations(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final invitations = await _repository.getEmployeeInvitations(professionId);
      state = state.copyWith(isLoading: false, employeeInvitations: invitations);
    } catch (e, st) {
      debugPrint('[Phase3] loadEmployeeInvitations ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดคำเชิญล้มเหลว: $e');
    }
  }

  Future<void> loadAvailableUsersForInvite(String professionId, {String? search}) async {
    try {
      final users = await _repository.getAvailableUsersForInvite(professionId, search: search);
      state = state.copyWith(availableUsersForInvite: users);
    } catch (e, st) {
      debugPrint('[Phase3] loadAvailableUsersForInvite ERROR: $e');
    }
  }

  Future<Map<String, dynamic>?> inviteEmployee(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final result = await _repository.inviteEmployee(data);
      state = state.copyWith(isSaving: false);
      if (result != null && result['success'] == true) {
        await loadEmployeeInvitations(data['profession_id'] as String);
      } else {
        state = state.copyWith(
          errorMessage: result?['error'] as String? ?? 'ส่งคำเชิญล้มเหลว',
        );
      }
      return result;
    } catch (e, st) {
      debugPrint('[Phase3] inviteEmployee ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ส่งคำเชิญล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> acceptEmployeeInvitation(String token, String professionId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final result = await _repository.acceptEmployeeInvitation(token);
      state = state.copyWith(isSaving: false);
      if (result != null && result['success'] == true) {
        await loadEmployeeInvitations(professionId);
        await loadEmployees(professionId);
        return true;
      } else {
        state = state.copyWith(
          errorMessage: result?['error'] as String? ?? 'ยอมรับคำเชิญล้มเหลว',
        );
        return false;
      }
    } catch (e, st) {
      debugPrint('[Phase3] acceptEmployeeInvitation ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ยอมรับคำเชิญล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> rejectEmployeeInvitation(
    String token,
    String professionId, {
    String? rejectionReason,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final result = await _repository.rejectEmployeeInvitation(
        token,
        rejectionReason: rejectionReason,
      );
      state = state.copyWith(isSaving: false);
      if (result != null && result['success'] == true) {
        await loadEmployeeInvitations(professionId);
        await loadPendingInvitationsForCurrentUser();
        return true;
      } else {
        state = state.copyWith(
          errorMessage: result?['error'] as String? ?? 'ปฏิเสธคำเชิญล้มเหลว',
        );
        return false;
      }
    } catch (e, st) {
      debugPrint('[Phase3] rejectEmployeeInvitation ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ปฏิเสธคำเชิญล้มเหลว: $e');
      return false;
    }
  }

  Future<void> loadPendingInvitationsForCurrentUser() async {
    try {
      final invitations = await _repository.getPendingInvitationsForCurrentUser();
      debugPrint('[Phase3] loadPendingInvitationsForCurrentUser: loaded ${invitations.length} invitations');
      state = state.copyWith(pendingInvitationsForCurrentUser: invitations);
    } catch (e, st) {
      debugPrint('[Phase3] loadPendingInvitationsForCurrentUser ERROR: $e\n$st');
    }
  }

  Future<bool> acceptEmployeeInvitationFromHome(String token) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final result = await _repository.acceptEmployeeInvitation(token);
      state = state.copyWith(isSaving: false);
      if (result != null && result['success'] == true) {
        await loadPendingInvitationsForCurrentUser();
        return true;
      } else {
        state = state.copyWith(
          errorMessage: result?['error'] as String? ?? 'ยอมรับคำเชิญล้มเหลว',
        );
        return false;
      }
    } catch (e, st) {
      debugPrint('[Phase3] acceptEmployeeInvitationFromHome ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ยอมรับคำเชิญล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> ensureOwnerAsEmployee(String professionId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final result = await _repository.ensureOwnerAsEmployee(professionId);
      state = state.copyWith(isSaving: false);
      if (result != null && result['success'] == true) {
        await loadEmployees(professionId);
        return true;
      } else {
        state = state.copyWith(
          errorMessage: result?['error'] as String? ?? 'สร้างพนักงานเจ้าของล้มเหลว',
        );
        return false;
      }
    } catch (e, st) {
      debugPrint('[Phase3] ensureOwnerAsEmployee ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างพนักงานเจ้าของล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // GL ENTRIES
  // ========================

  Future<void> loadGlEntries(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final entries = await _repository.getGlEntries(professionId);
      state = state.copyWith(isLoading: false, glEntries: entries);
    } catch (e, st) {
      debugPrint('[Phase3] loadGlEntries ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดข้อมูลบัญชีล้มเหลว: $e');
    }
  }

  Future<bool> createGlFromOrder(String orderId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.createGlFromOrder(orderId);
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e, st) {
      debugPrint('[Phase3] createGlFromOrder ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างบันทึกบัญชีล้มเหลว: $e');
      return false;
    }
  }

  Future<GlEntry?> createGlEntry(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final entry = await _repository.createGlEntry(data);
      if (entry != null) {
        final updated = [entry, ...state.glEntries];
        state = state.copyWith(isSaving: false, glEntries: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return entry;
    } catch (e, st) {
      debugPrint('[Phase3] createGlEntry ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างรายการบัญชีล้มเหลว: $e');
      return null;
    }
  }

  // ========================
  // DASHBOARD SNAPSHOTS
  // ========================

  Future<void> loadSnapshots(String professionId, {String type = 'daily'}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final snapshots = await _repository.getDashboardSnapshots(professionId, type: type);
      state = state.copyWith(isLoading: false, snapshots: snapshots);
    } catch (e, st) {
      debugPrint('[Phase3] loadSnapshots ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดข้อมูล analytics ล้มเหลว: $e');
    }
  }

  Future<String?> upsertSnapshot({
    required String professionId,
    required String type,
    required Map<String, dynamic> metrics,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final id = await _repository.upsertDashboardSnapshot(
        professionId: professionId,
        type: type,
        metrics: metrics,
      );
      state = state.copyWith(isSaving: false);
      return id;
    } catch (e, st) {
      debugPrint('[Phase3] upsertSnapshot ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'บันทึก snapshot ล้มเหลว: $e');
      return null;
    }
  }

  // ========================
  // CHART OF ACCOUNTS
  // ========================

  Future<void> loadChartOfAccounts(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.ensureChartOfAccountsSeeded(professionId);
      final accounts = await _repository.getChartOfAccounts(professionId);
      state = state.copyWith(isLoading: false, chartOfAccounts: accounts);
    } catch (e, st) {
      debugPrint('[Phase3] loadChartOfAccounts ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดผังบัญชีล้มเหลว: $e');
    }
  }

  Future<ChartOfAccount?> createChartOfAccount(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final account = await _repository.createChartOfAccount(data);
      if (account != null) {
        final updated = [...state.chartOfAccounts, account];
        state = state.copyWith(isSaving: false, chartOfAccounts: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return account;
    } catch (e, st) {
      debugPrint('[Phase3] createChartOfAccount ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างบัญชีล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> updateChartOfAccount(String id, Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updateChartOfAccount(id, data);
      if (success) {
        final updated = state.chartOfAccounts.map((a) {
          if (a.id == id) {
            return ChartOfAccount(
              id: a.id,
              professionId: a.professionId,
              accountCode: data['account_code'] as String? ?? a.accountCode,
              accountName: data['account_name'] as String? ?? a.accountName,
              accountType: data['account_type'] as String? ?? a.accountType,
              parentId: data['parent_id'] as String? ?? a.parentId,
              isActive: data['is_active'] as bool? ?? a.isActive,
              isCustom: true,
              createdAt: a.createdAt,
              updatedAt: DateTime.now(),
            );
          }
          return a;
        }).toList();
        state = state.copyWith(isSaving: false, chartOfAccounts: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase3] updateChartOfAccount ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อัปเดตบัญชีล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> resetChartOfAccount(String accountId, String professionId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.resetChartOfAccountToStandard(accountId);
      if (success) {
        await loadChartOfAccounts(professionId);
      } else {
        state = state.copyWith(isSaving: false, errorMessage: 'รีเซตล้มเหลว: ไม่พบผังบัญชีมาตรฐานสำหรับบัญชีนี้');
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase3] resetChartOfAccount ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'รีเซตผังบัญชีล้มเหลว: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> checkDeleteChartOfAccount(String accountId) async {
    try {
      return await _repository.getChartOfAccountDependencies(accountId);
    } catch (e, st) {
      debugPrint('[Phase3] checkDeleteChartOfAccount ERROR: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> deleteChartOfAccount(String accountId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final result = await _repository.deleteChartOfAccount(accountId);
      if (result['success'] == true) {
        final updated = state.chartOfAccounts.where((a) => a.id != accountId).toList();
        state = state.copyWith(isSaving: false, chartOfAccounts: updated);
      } else {
        state = state.copyWith(isSaving: false, errorMessage: result['error']?.toString());
      }
      return result;
    } catch (e, st) {
      debugPrint('[Phase3] deleteChartOfAccount ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ลบบัญชีล้มเหลว: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ========================
  // ACCOUNTS RECEIVABLE (AR)
  // ========================

  Future<void> loadAccountsReceivable(String professionId, {String? status}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repository.getAccountsReceivable(professionId, status: status);
      state = state.copyWith(isLoading: false, accountsReceivable: items);
    } catch (e, st) {
      debugPrint('[Phase3] loadAccountsReceivable ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดลูกหนี้ล้มเหลว: $e');
    }
  }

  Future<bool> updateArStatus(String id, String status, {double? paidAmount}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updateArStatus(id, status, paidAmount: paidAmount);
      if (success) {
        final updated = state.accountsReceivable.map((ar) {
          if (ar.id == id) {
            return AccountsReceivable(
              id: ar.id,
              professionId: ar.professionId,
              customerId: ar.customerId,
              orderId: ar.orderId,
              invoiceNumber: ar.invoiceNumber,
              amount: ar.amount,
              paidAmount: paidAmount ?? ar.paidAmount,
              balance: ar.amount - (paidAmount ?? ar.paidAmount),
              dueDate: ar.dueDate,
              status: status,
              notes: ar.notes,
              createdAt: ar.createdAt,
              updatedAt: DateTime.now(),
            );
          }
          return ar;
        }).toList();
        state = state.copyWith(isSaving: false, accountsReceivable: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase3] updateArStatus ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อัปเดตสถานะลูกหนี้ล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // ACCOUNTS PAYABLE (AP)
  // ========================

  Future<void> loadAccountsPayable(String professionId, {String? status}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repository.getAccountsPayable(professionId, status: status);
      state = state.copyWith(isLoading: false, accountsPayable: items);
    } catch (e, st) {
      debugPrint('[Phase3] loadAccountsPayable ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดเจ้าหนี้ล้มเหลว: $e');
    }
  }

  Future<bool> updateApStatus(String id, String status, {double? paidAmount}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updateApStatus(id, status, paidAmount: paidAmount);
      if (success) {
        final updated = state.accountsPayable.map((ap) {
          if (ap.id == id) {
            return AccountsPayable(
              id: ap.id,
              professionId: ap.professionId,
              supplierId: ap.supplierId,
              poId: ap.poId,
              invoiceNumber: ap.invoiceNumber,
              amount: ap.amount,
              paidAmount: paidAmount ?? ap.paidAmount,
              balance: ap.amount - (paidAmount ?? ap.paidAmount),
              dueDate: ap.dueDate,
              status: status,
              notes: ap.notes,
              createdAt: ap.createdAt,
              updatedAt: DateTime.now(),
            );
          }
          return ap;
        }).toList();
        state = state.copyWith(isSaving: false, accountsPayable: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase3] updateApStatus ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อัปเดตสถานะเจ้าหนี้ล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // SETTLEMENT LEDGERS
  // ========================

  Future<void> loadSettlementLedgers(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final ledgers = await _repository.getSettlementLedgers(professionId);
      state = state.copyWith(isLoading: false, settlementLedgers: ledgers);
    } catch (e, st) {
      debugPrint('[Phase3] loadSettlementLedgers ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดสรุปยอดล้มเหลว: $e');
    }
  }

  // ========================
  // PAYROLL
  // ========================

  Future<void> loadPayrollRuns(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final runs = await _repository.getPayrollRuns(professionId);
      state = state.copyWith(isLoading: false, payrollRuns: runs);
    } catch (e, st) {
      debugPrint('[Phase3] loadPayrollRuns ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดรอบเงินเดือนล้มเหลว: $e');
    }
  }

  Future<void> loadPayrollItems(String payrollRunId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _repository.getPayrollItems(payrollRunId);
      state = state.copyWith(isLoading: false, payrollItems: items);
    } catch (e, st) {
      debugPrint('[Phase3] loadPayrollItems ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดรายการเงินเดือนล้มเหลว: $e');
    }
  }

  Future<void> loadHrSettings(String professionId) async {
    try {
      final settings = await _repository.getHrSettings(professionId);
      state = state.copyWith(hrSettings: settings);
    } catch (e, st) {
      debugPrint('[Phase3] loadHrSettings ERROR: $e');
    }
  }

  Future<PayrollRun?> createPayrollRun(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final run = await _repository.createPayrollRun(data);
      if (run != null) {
        final updated = [run, ...state.payrollRuns];
        state = state.copyWith(isSaving: false, payrollRuns: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return run;
    } catch (e, st) {
      debugPrint('[Phase3] createPayrollRun ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างรอบเงินเดือนล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> runPayrollCalculation({
    required String payrollRunId,
    required String professionId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      // Try server-side RPC first (preferred — atomic, idempotent)
      final rpcResult = await _repository.runPayrollCalculationRpc(
        payrollRunId: payrollRunId,
        professionId: professionId,
        periodStart: periodStart,
        periodEnd: periodEnd,
      );

      if (rpcResult != null) {
        final updatedRuns = state.payrollRuns.map((r) {
          if (r.id == payrollRunId) return rpcResult;
          return r;
        }).toList();
        state = state.copyWith(isSaving: false, payrollRuns: updatedRuns);
        return true;
      }

      // Fallback: client-side calculation
      final settings = await _repository.getHrSettings(professionId);
      if (settings == null) {
        state = state.copyWith(isSaving: false, errorMessage: 'ไม่พบการตั้งค่า HR กรุณาตั้งค่าก่อนรัน Payroll');
        return false;
      }

      final employees = await _repository.getEmployees(professionId);
      if (employees.isEmpty) {
        state = state.copyWith(isSaving: false, errorMessage: 'ไม่พบพนักงานที่ใช้งานอยู่');
        return false;
      }

      final allItems = <Map<String, dynamic>>[];
      double totalGross = 0;
      double totalDeductions = 0;

      for (final emp in employees) {
        final calc = await _repository.calculateEmployeePayroll(
          employeeId: emp.id,
          professionId: professionId,
          periodStart: periodStart,
          periodEnd: periodEnd,
          settings: settings,
          baseSalary: emp.salary ?? 0,
        );

        final earningTypes = ['base_salary', 'overtime', 'diligence_allowance', 'commission'];
        for (final entry in calc.entries) {
          if (entry.key == 'gross' || entry.key == 'deductions' || entry.key == 'net') continue;
          final isEarning = earningTypes.contains(entry.key);
          final amount = entry.value;
          if (amount == 0) continue;

          allItems.add({
            'profession_id': professionId,
            'payroll_run_id': payrollRunId,
            'employee_id': emp.id,
            'item_type': entry.key,
            'amount': amount,
            'is_earning': isEarning,
          });

          if (isEarning) {
            totalGross += amount;
          } else {
            totalDeductions += amount;
          }
        }
      }

      if (allItems.isNotEmpty) {
        await _repository.insertPayrollItems(allItems);
      }

      await _repository.updatePayrollRun(payrollRunId, {
        'status': 'pending_approval',
        'total_gross': totalGross,
        'total_deductions': totalDeductions,
        'total_net': totalGross - totalDeductions,
      });

      await _repository.insertOutboxEvent(
        professionId: professionId,
        aggregateType: 'hr_payroll',
        aggregateId: payrollRunId,
        eventType: 'hr.payroll_calculated',
        payload: {
          'payroll_run_id': payrollRunId,
          'period_start': periodStart.toIso8601String().split('T')[0],
          'period_end': periodEnd.toIso8601String().split('T')[0],
          'total_gross': totalGross,
          'total_deductions': totalDeductions,
          'total_net': totalGross - totalDeductions,
          'employee_count': employees.length,
          'status': 'pending_approval',
        },
      );

      final updatedRuns = state.payrollRuns.map((r) {
        if (r.id == payrollRunId) {
          return PayrollRun(
            id: r.id,
            professionId: r.professionId,
            branchId: r.branchId,
            runName: r.runName,
            periodStart: r.periodStart,
            periodEnd: r.periodEnd,
            payDate: r.payDate,
            status: 'pending_approval',
            totalGross: totalGross,
            totalDeductions: totalDeductions,
            totalNet: totalGross - totalDeductions,
            employerSocialSecurity: r.employerSocialSecurity,
            employerProvidentFund: r.employerProvidentFund,
            totalEmployerCost: r.totalEmployerCost,
            approvedBy: r.approvedBy,
            approvedAt: r.approvedAt,
            notes: r.notes,
            createdAt: r.createdAt,
            updatedAt: DateTime.now(),
          );
        }
        return r;
      }).toList();

      state = state.copyWith(isSaving: false, payrollRuns: updatedRuns);
      return true;
    } catch (e, st) {
      debugPrint('[Phase3] runPayrollCalculation ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'คำนวณเงินเดือนล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> approvePayrollRun(String payrollRunId, String approvedBy) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      // Try server-side RPC first (auto-creates GL entries via outbox trigger)
      final rpcResult = await _repository.approvePayrollRunRpc(
        payrollRunId: payrollRunId,
        approvedBy: approvedBy,
      );

      if (rpcResult != null) {
        final updated = state.payrollRuns.map((r) {
          if (r.id == payrollRunId) return rpcResult;
          return r;
        }).toList();
        state = state.copyWith(isSaving: false, payrollRuns: updated);
        return true;
      }

      // Fallback: direct update + manual outbox event
      final success = await _repository.updatePayrollRun(payrollRunId, {
        'status': 'approved',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
      });
      if (success) {
        await _repository.insertOutboxEvent(
          professionId: state.payrollRuns
              .firstWhere((r) => r.id == payrollRunId)
              .professionId,
          aggregateType: 'hr_payroll',
          aggregateId: payrollRunId,
          eventType: 'hr.payroll_approved',
          payload: {
            'payroll_run_id': payrollRunId,
            'approved_by': approvedBy,
            'approved_at': DateTime.now().toIso8601String(),
            'total_net': state.payrollRuns
                .firstWhere((r) => r.id == payrollRunId)
                .totalNet,
          },
        );

        final updated = state.payrollRuns.map((r) {
          if (r.id == payrollRunId) {
            return PayrollRun(
              id: r.id,
              professionId: r.professionId,
              branchId: r.branchId,
              runName: r.runName,
              periodStart: r.periodStart,
              periodEnd: r.periodEnd,
              payDate: r.payDate,
              status: 'approved',
              totalGross: r.totalGross,
              totalDeductions: r.totalDeductions,
              totalNet: r.totalNet,
              employerSocialSecurity: r.employerSocialSecurity,
              employerProvidentFund: r.employerProvidentFund,
              totalEmployerCost: r.totalEmployerCost,
              approvedBy: approvedBy,
              approvedAt: DateTime.now(),
              notes: r.notes,
              createdAt: r.createdAt,
              updatedAt: DateTime.now(),
            );
          }
          return r;
        }).toList();
        state = state.copyWith(isSaving: false, payrollRuns: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase3] approvePayrollRun ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อนุมัติเงินเดือนล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // SHIFTS
  // ========================

  Future<void> loadShifts(
    String professionId, {
    String? employeeId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final shifts = await _repository.getShifts(
        professionId,
        employeeId: employeeId,
        fromDate: fromDate,
        toDate: toDate,
      );
      state = state.copyWith(isLoading: false, shifts: shifts);
    } catch (e, st) {
      debugPrint('[Phase3] loadShifts ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดตารางเวรล้มเหลว: $e');
    }
  }

  Future<Shift?> createShift(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final shift = await _repository.createShift(data);
      if (shift != null) {
        final updated = [...state.shifts, shift];
        state = state.copyWith(isSaving: false, shifts: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return shift;
    } catch (e, st) {
      debugPrint('[Phase3] createShift ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างเวรล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> updateShift(String id, Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updateShift(id, data);
      if (success) {
        final updated = state.shifts.map((s) {
          if (s.id == id) {
            return Shift(
              id: s.id,
              professionId: s.professionId,
              employeeId: data['employee_id'] as String? ?? s.employeeId,
              shiftDate: data['shift_date'] != null
                  ? DateTime.parse(data['shift_date'] as String)
                  : s.shiftDate,
              startTime: data['start_time'] != null
                  ? DateTime.parse(data['start_time'] as String)
                  : s.startTime,
              endTime: data['end_time'] != null
                  ? DateTime.parse(data['end_time'] as String)
                  : s.endTime,
              shiftType: data['shift_type'] as String? ?? s.shiftType,
              status: data['status'] as String? ?? s.status,
              notes: data['notes'] as String? ?? s.notes,
              createdAt: s.createdAt,
              updatedAt: DateTime.now(),
            );
          }
          return s;
        }).toList();
        state = state.copyWith(isSaving: false, shifts: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase3] updateShift ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อัปเดตเวรล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // THAI HOLIDAYS
  // ========================

  Future<void> loadThaiHolidays({int? year}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final holidays = await _repository.getThaiHolidays(year: year);
      state = state.copyWith(isLoading: false, thaiHolidays: holidays);
    } catch (e, st) {
      debugPrint('[Phase3] loadThaiHolidays ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดวันหยุดล้มเหลว: $e');
    }
  }

  Future<ThaiHoliday?> upsertThaiHoliday(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final holiday = await _repository.upsertThaiHoliday(data);
      if (holiday != null) {
        final updated = [...state.thaiHolidays.where((h) => h.id != holiday.id), holiday];
        updated.sort((a, b) => a.holidayDate.compareTo(b.holidayDate));
        state = state.copyWith(isSaving: false, thaiHolidays: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return holiday;
    } catch (e, st) {
      debugPrint('[Phase3] upsertThaiHoliday ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'บันทึกวันหยุดล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> deleteThaiHoliday(String id) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.deleteThaiHoliday(id);
      if (success) {
        final updated = state.thaiHolidays.where((h) => h.id != id).toList();
        state = state.copyWith(isSaving: false, thaiHolidays: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase3] deleteThaiHoliday ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ลบวันหยุดล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // EMPLOYEE TAX ALLOWANCES
  // ========================

  Future<void> loadTaxAllowances(String employeeId, {int? year}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final allowances = await _repository.getTaxAllowances(employeeId, year: year);
      state = state.copyWith(isLoading: false, taxAllowances: allowances);
    } catch (e, st) {
      debugPrint('[Phase3] loadTaxAllowances ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดค่าลดหย่อนล้มเหลว: $e');
    }
  }

  Future<EmployeeTaxAllowance?> createTaxAllowance(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final allowance = await _repository.createTaxAllowance(data);
      if (allowance != null) {
        final updated = [...state.taxAllowances, allowance];
        state = state.copyWith(isSaving: false, taxAllowances: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return allowance;
    } catch (e, st) {
      debugPrint('[Phase3] createTaxAllowance ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างค่าลดหย่อนล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> deleteTaxAllowance(String id) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.deleteTaxAllowance(id);
      if (success) {
        final updated = state.taxAllowances.where((a) => a.id != id).toList();
        state = state.copyWith(isSaving: false, taxAllowances: updated);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase3] deleteTaxAllowance ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ลบค่าลดหย่อนล้มเหลว: $e');
      return false;
    }
  }

  // ========================
  // HR SETTINGS (with new fields via RPC)
  // ========================

  Future<bool> saveHrSettings(Map<String, dynamic> params) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final settings = await _repository.upsertHrSettingsRpc(params);
      if (settings != null) {
        state = state.copyWith(isSaving: false, hrSettings: settings);
        return true;
      }
      state = state.copyWith(isSaving: false);
      return false;
    } catch (e, st) {
      debugPrint('[Phase3] saveHrSettings ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'บันทึกการตั้งค่าล้มเหลว: $e');
      return false;
    }
  }
}

// ========================
// Provider
// ========================
final phaseThreeProvider =
    StateNotifierProvider<PhaseThreeNotifier, PhaseThreeState>((ref) {
  final repo = ref.watch(phaseThreeRepositoryProvider);
  return PhaseThreeNotifier(repo);
});
