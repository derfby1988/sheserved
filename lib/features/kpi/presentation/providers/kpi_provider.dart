import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/kpi_models.dart';
import '../../data/repositories/kpi_repository.dart';

/// Global KPI Repository Provider
final kpiRepositoryProvider = Provider<KpiRepository>((ref) {
  return KpiRepository(Supabase.instance.client);
});

// ========================
// KPI State
// ========================

class KpiState {
  final bool isLoading;
  final bool isRefreshing;
  final String? errorMessage;

  // Filters
  final String? selectedProfessionId;
  final String? selectedBranchId;
  final String? selectedEmployeeId;
  final String selectedTargetType; // 'revenue', 'net_profit', etc.
  final String selectedPeriodType;   // 'daily', 'weekly', 'monthly'

  // Data
  final List<KpiActual> kpiActuals;
  final List<KpiTarget> kpiTargets;
  final List<KpiAlertThreshold> alertThresholds;
  final KpiDashboardSummary? dashboardSummary;

  // Refresh result
  final Map<String, int>? lastRefreshResult;

  KpiState({
    this.isLoading = false,
    this.isRefreshing = false,
    this.errorMessage,
    this.selectedProfessionId,
    this.selectedBranchId,
    this.selectedEmployeeId,
    this.selectedTargetType = 'revenue',
    this.selectedPeriodType = 'daily',
    this.kpiActuals = const [],
    this.kpiTargets = const [],
    this.alertThresholds = const [],
    this.dashboardSummary,
    this.lastRefreshResult,
  });

  KpiState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
    String? selectedProfessionId,
    String? selectedBranchId,
    String? selectedEmployeeId,
    String? selectedTargetType,
    String? selectedPeriodType,
    List<KpiActual>? kpiActuals,
    List<KpiTarget>? kpiTargets,
    List<KpiAlertThreshold>? alertThresholds,
    KpiDashboardSummary? dashboardSummary,
    Map<String, int>? lastRefreshResult,
  }) {
    final shouldClearError = clearError || (isLoading != null && !isLoading);
    return KpiState(
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      selectedProfessionId: selectedProfessionId ?? this.selectedProfessionId,
      selectedBranchId: selectedBranchId ?? this.selectedBranchId,
      selectedEmployeeId: selectedEmployeeId ?? this.selectedEmployeeId,
      selectedTargetType: selectedTargetType ?? this.selectedTargetType,
      selectedPeriodType: selectedPeriodType ?? this.selectedPeriodType,
      kpiActuals: kpiActuals ?? this.kpiActuals,
      kpiTargets: kpiTargets ?? this.kpiTargets,
      alertThresholds: alertThresholds ?? this.alertThresholds,
      dashboardSummary: dashboardSummary ?? this.dashboardSummary,
      lastRefreshResult: lastRefreshResult ?? this.lastRefreshResult,
    );
  }
}

// ========================
// KPI Notifier
// ========================

class KpiNotifier extends StateNotifier<KpiState> {
  KpiNotifier(this._repository) : super(KpiState());

  final KpiRepository _repository;

  /// ตั้งค่า profession / branch / employee filters
  void setFilters({
    String? professionId,
    String? branchId,
    String? employeeId,
    String? targetType,
    String? periodType,
  }) {
    state = state.copyWith(
      selectedProfessionId: professionId,
      selectedBranchId: branchId,
      selectedEmployeeId: employeeId,
      selectedTargetType: targetType,
      selectedPeriodType: periodType,
      clearError: true,
    );
  }

  /// โหลดข้อมูล Dashboard ทั้งหมด
  Future<void> loadDashboardData() async {
    final professionId = state.selectedProfessionId;
    if (professionId == null || professionId.isEmpty) {
      state = state.copyWith(
        errorMessage: 'กรุณาเลือก Profession',
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final results = await Future.wait([
        _repository.getKpiActuals(
          professionId: professionId,
          branchId: state.selectedBranchId,
          employeeId: state.selectedEmployeeId,
          targetType: state.selectedTargetType,
          periodType: state.selectedPeriodType,
          limit: 90,
        ),
        _repository.getDashboardSummary(
          professionId: professionId,
          branchId: state.selectedBranchId,
          targetType: state.selectedTargetType,
          periodType: state.selectedPeriodType,
        ),
        _repository.getAlertThresholds(professionId: professionId),
      ]);

      final actuals = results[0] as List<KpiActual>;
      final summary = results[1] as KpiDashboardSummary;
      final thresholds = results[2] as List<KpiAlertThreshold>;

      state = state.copyWith(
        isLoading: false,
        kpiActuals: actuals,
        dashboardSummary: summary,
        alertThresholds: thresholds,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'โหลดข้อมูลไม่สำเร็จ: $e',
      );
    }
  }

  /// โหลด Targets สำหรับหน้าจัดการเป้าหมาย
  Future<void> loadTargets() async {
    final professionId = state.selectedProfessionId;
    if (professionId == null || professionId.isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final targets = await _repository.getKpiTargets(
        professionId: professionId,
        branchId: state.selectedBranchId,
        employeeId: state.selectedEmployeeId,
        targetType: state.selectedTargetType,
        periodType: state.selectedPeriodType,
      );
      state = state.copyWith(isLoading: false, kpiTargets: targets);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'โหลดเป้าหมายไม่สำเร็จ: $e',
      );
    }
  }

  /// สร้าง Target ใหม่
  Future<bool> createTarget(KpiTarget target) async {
    try {
      await _repository.createKpiTarget(target);
      await loadTargets();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'สร้างเป้าหมายไม่สำเร็จ: $e');
      return false;
    }
  }

  /// อัปเดต Target
  Future<bool> updateTarget(String id, Map<String, dynamic> updates) async {
    try {
      await _repository.updateKpiTarget(id, updates);
      await loadTargets();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'อัปเดตเป้าหมายไม่สำเร็จ: $e');
      return false;
    }
  }

  /// ลบ Target
  Future<bool> deleteTarget(String id) async {
    try {
      await _repository.deleteKpiTarget(id);
      await loadTargets();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'ลบเป้าหมายไม่สำเร็จ: $e');
      return false;
    }
  }

  /// Refresh KPI Actuals ด้วย RPC
  Future<void> refreshActuals() async {
    final professionId = state.selectedProfessionId;
    if (professionId == null || professionId.isEmpty) return;

    state = state.copyWith(isRefreshing: true, clearError: true);

    try {
      final result = await _repository.refreshKpiActuals(
        professionId: professionId,
        periodType: state.selectedPeriodType,
        targetType: state.selectedTargetType,
      );

      // Refresh employee actuals ถ้าเลือก target type = revenue
      if (state.selectedTargetType == 'revenue') {
        await _repository.refreshKpiEmployeeActuals(
          professionId: professionId,
          periodType: state.selectedPeriodType,
        );
      }

      // Refresh appointments ถ้าเลือก target type = appointments
      if (state.selectedTargetType == 'appointments') {
        await _repository.refreshKpiAppointments(
          professionId: professionId,
          periodType: state.selectedPeriodType,
        );
      }

      state = state.copyWith(
        isRefreshing: false,
        lastRefreshResult: result,
      );

      // โหลดข้อมูลใหม่
      await loadDashboardData();
    } catch (e) {
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: 'รีเฟรชข้อมูลไม่สำเร็จ: $e',
      );
    }
  }

  /// อัปเดต Alert Threshold
  Future<bool> updateAlertThreshold(String id, Map<String, dynamic> updates) async {
    try {
      await _repository.updateAlertThreshold(id, updates);
      await loadDashboardData(); // โหลด thresholds ใหม่
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'อัปเดตเกณฑ์ไม่สำเร็จ: $e');
      return false;
    }
  }
}

// ========================
// Global Provider
// ========================

final kpiProvider = StateNotifierProvider<KpiNotifier, KpiState>((ref) {
  final repo = ref.watch(kpiRepositoryProvider);
  return KpiNotifier(repo);
});
