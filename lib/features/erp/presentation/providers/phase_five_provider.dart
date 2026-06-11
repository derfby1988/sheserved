import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/refund_request.dart';
import '../../data/models/loyalty_rule.dart';
import '../../data/models/scheduled_report.dart';
import '../../data/repositories/phase_five_repository.dart';

final phaseFiveRepositoryProvider = Provider<PhaseFiveRepository>((ref) {
  return PhaseFiveRepository(Supabase.instance.client);
});

class PhaseFiveState {
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  final List<RefundRequest> refundRequests;
  final List<LoyaltyRule> loyaltyRules;
  final List<ScheduledReport> scheduledReports;
  final Map<String, dynamic>? reportPayload;

  PhaseFiveState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.refundRequests = const [],
    this.loyaltyRules = const [],
    this.scheduledReports = const [],
    this.reportPayload,
  });

  PhaseFiveState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    List<RefundRequest>? refundRequests,
    List<LoyaltyRule>? loyaltyRules,
    List<ScheduledReport>? scheduledReports,
    Map<String, dynamic>? reportPayload,
  }) {
    final shouldClearError = clearError ||
        ((isLoading != null && !isLoading) || (isSaving != null && !isSaving));
    return PhaseFiveState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      refundRequests: refundRequests ?? this.refundRequests,
      loyaltyRules: loyaltyRules ?? this.loyaltyRules,
      scheduledReports: scheduledReports ?? this.scheduledReports,
      reportPayload: reportPayload ?? this.reportPayload,
    );
  }
}

class PhaseFiveNotifier extends StateNotifier<PhaseFiveState> {
  final PhaseFiveRepository _repository;

  PhaseFiveNotifier(this._repository) : super(PhaseFiveState());

  Future<void> loadRefundRequests(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final refunds = await _repository.getRefundRequests(professionId);
      state = state.copyWith(isLoading: false, refundRequests: refunds);
    } catch (e) {
      debugPrint('[Phase5] loadRefundRequests ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดรายการคืนเงินล้มเหลว: $e');
    }
  }

  Future<String?> requestRefund(Map<String, dynamic> params) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final id = await _repository.requestRefund(params);
      state = state.copyWith(isSaving: false);
      return id;
    } catch (e) {
      debugPrint('[Phase5] requestRefund ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างคำขอคืนเงินล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> reviewRefund(String refundId, String status, String reviewedBy, {String? notes}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final ok = await _repository.reviewRefund(refundId, status, reviewedBy, notes: notes);
      state = state.copyWith(isSaving: false);
      return ok;
    } catch (e) {
      debugPrint('[Phase5] reviewRefund ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อนุมัติ/ปฏิเสธคืนเงินล้มเหลว: $e');
      return false;
    }
  }

  Future<void> loadLoyaltyRules(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final rules = await _repository.getLoyaltyRules(professionId);
      state = state.copyWith(isLoading: false, loyaltyRules: rules);
    } catch (e) {
      debugPrint('[Phase5] loadLoyaltyRules ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดกฎแต้มล้มเหลว: $e');
    }
  }

  Future<LoyaltyRule?> createLoyaltyRule(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final rule = await _repository.createLoyaltyRule(data);
      if (rule != null) {
        state = state.copyWith(isSaving: false, loyaltyRules: [...state.loyaltyRules, rule]);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return rule;
    } catch (e) {
      debugPrint('[Phase5] createLoyaltyRule ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างกฎแต้มล้มเหลว: $e');
      return null;
    }
  }

  Future<void> loadScheduledReports(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final reports = await _repository.getScheduledReports(professionId);
      state = state.copyWith(isLoading: false, scheduledReports: reports);
    } catch (e) {
      debugPrint('[Phase5] loadScheduledReports ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดรายงานล้มเหลว: $e');
    }
  }

  Future<void> generateReport(String professionId, String reportType, DateTime startDate, DateTime endDate) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final payload = await _repository.generateReportPayload(professionId, reportType, startDate, endDate);
      state = state.copyWith(isLoading: false, reportPayload: payload);
    } catch (e) {
      debugPrint('[Phase5] generateReport ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'สร้างรายงานล้มเหลว: $e');
    }
  }
}

final phaseFiveProvider =
    StateNotifierProvider<PhaseFiveNotifier, PhaseFiveState>((ref) {
  final repo = ref.watch(phaseFiveRepositoryProvider);
  return PhaseFiveNotifier(repo);
});
