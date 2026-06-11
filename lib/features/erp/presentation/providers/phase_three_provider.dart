import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/employee.dart';
import '../../data/models/gl_entry.dart';
import '../../data/models/dashboard_snapshot.dart';
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

  PhaseThreeState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.employees = const [],
    this.glEntries = const [],
    this.snapshots = const [],
  });

  PhaseThreeState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    List<Employee>? employees,
    List<GlEntry>? glEntries,
    List<DashboardSnapshot>? snapshots,
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
}

// ========================
// Provider
// ========================
final phaseThreeProvider =
    StateNotifierProvider<PhaseThreeNotifier, PhaseThreeState>((ref) {
  final repo = ref.watch(phaseThreeRepositoryProvider);
  return PhaseThreeNotifier(repo);
});
