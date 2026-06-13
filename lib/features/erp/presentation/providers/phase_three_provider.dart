import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/employee.dart';
import '../../data/models/gl_entry.dart';
import '../../data/models/dashboard_snapshot.dart';
import '../../data/models/chart_of_account.dart';
import '../../data/models/accounts_receivable.dart';
import '../../data/models/accounts_payable.dart';
import '../../data/models/shift.dart';
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
  final List<GlEntry> glEntries;
  final List<DashboardSnapshot> snapshots;
  final List<ChartOfAccount> chartOfAccounts;
  final List<AccountsReceivable> accountsReceivable;
  final List<AccountsPayable> accountsPayable;
  final List<Shift> shifts;

  PhaseThreeState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.employees = const [],
    this.glEntries = const [],
    this.snapshots = const [],
    this.chartOfAccounts = const [],
    this.accountsReceivable = const [],
    this.accountsPayable = const [],
    this.shifts = const [],
  });

  PhaseThreeState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    List<Employee>? employees,
    List<GlEntry>? glEntries,
    List<DashboardSnapshot>? snapshots,
    List<ChartOfAccount>? chartOfAccounts,
    List<AccountsReceivable>? accountsReceivable,
    List<AccountsPayable>? accountsPayable,
    List<Shift>? shifts,
  }) {
    final shouldClearError = clearError ||
        ((isLoading != null && !isLoading) || (isSaving != null && !isSaving));
    return PhaseThreeState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      employees: employees ?? this.employees,
      glEntries: glEntries ?? this.glEntries,
      snapshots: snapshots ?? this.snapshots,
      chartOfAccounts: chartOfAccounts ?? this.chartOfAccounts,
      accountsReceivable: accountsReceivable ?? this.accountsReceivable,
      accountsPayable: accountsPayable ?? this.accountsPayable,
      shifts: shifts ?? this.shifts,
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
              commissionRate: data['commission_rate'] != null
                  ? (data['commission_rate'] as num).toDouble()
                  : e.commissionRate,
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
}

// ========================
// Provider
// ========================
final phaseThreeProvider =
    StateNotifierProvider<PhaseThreeNotifier, PhaseThreeState>((ref) {
  final repo = ref.watch(phaseThreeRepositoryProvider);
  return PhaseThreeNotifier(repo);
});
