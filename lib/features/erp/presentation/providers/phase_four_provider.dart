import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/emr_record.dart';
import '../../data/models/opd_visit.dart';
import '../../data/repositories/phase_four_repository.dart';

final phaseFourRepositoryProvider = Provider<PhaseFourRepository>((ref) {
  return PhaseFourRepository(Supabase.instance.client);
});

class PhaseFourState {
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  final List<EmrRecord> emrRecords;
  final List<OpdVisit> opdVisits;
  final List<Map<String, dynamic>> prescriptions;
  final List<Map<String, dynamic>> labResults;
  final List<Map<String, dynamic>> cohorts;

  PhaseFourState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.emrRecords = const [],
    this.opdVisits = const [],
    this.prescriptions = const [],
    this.labResults = const [],
    this.cohorts = const [],
  });

  PhaseFourState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    List<EmrRecord>? emrRecords,
    List<OpdVisit>? opdVisits,
    List<Map<String, dynamic>>? prescriptions,
    List<Map<String, dynamic>>? labResults,
    List<Map<String, dynamic>>? cohorts,
  }) {
    final shouldClearError = clearError ||
        ((isLoading != null && !isLoading) || (isSaving != null && !isSaving));
    return PhaseFourState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      emrRecords: emrRecords ?? this.emrRecords,
      opdVisits: opdVisits ?? this.opdVisits,
      prescriptions: prescriptions ?? this.prescriptions,
      labResults: labResults ?? this.labResults,
      cohorts: cohorts ?? this.cohorts,
    );
  }
}

class PhaseFourNotifier extends StateNotifier<PhaseFourState> {
  final PhaseFourRepository _repository;

  PhaseFourNotifier(this._repository) : super(PhaseFourState());

  Future<void> loadEmrRecords(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final records = await _repository.getEmrRecords(professionId);
      state = state.copyWith(isLoading: false, emrRecords: records);
    } catch (e, st) {
      debugPrint('[Phase4] loadEmrRecords ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลด EMR ล้มเหลว: $e');
    }
  }

  Future<EmrRecord?> createEmrRecord(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final record = await _repository.createEmrRecord(data);
      if (record != null) {
        state = state.copyWith(isSaving: false, emrRecords: [...state.emrRecords, record]);
      } else {
        state = state.copyWith(isSaving: false);
      }
      return record;
    } catch (e, st) {
      debugPrint('[Phase4] createEmrRecord ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้าง EMR ล้มเหลว: $e');
      return null;
    }
  }

  Future<void> loadOpdVisits(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final visits = await _repository.getOpdVisits(professionId);
      state = state.copyWith(isLoading: false, opdVisits: visits);
    } catch (e, st) {
      debugPrint('[Phase4] loadOpdVisits ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลด OPD ล้มเหลว: $e');
    }
  }

  Future<String?> createOpdVisit(Map<String, dynamic> params) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final id = await _repository.createOpdVisit(
        professionId: params['profession_id'],
        patientId: params['patient_id'],
        doctorId: params['doctor_id'],
        chiefComplaint: params['chief_complaint'],
        isWalkIn: params['is_walk_in'] ?? true,
      );
      state = state.copyWith(isSaving: false);
      return id;
    } catch (e, st) {
      debugPrint('[Phase4] createOpdVisit ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้าง OPD visit ล้มเหลว: $e');
      return null;
    }
  }

  Future<void> loadPrescriptions(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final prescriptions = await _repository.getPrescriptions(professionId);
      state = state.copyWith(isLoading: false, prescriptions: prescriptions);
    } catch (e, st) {
      debugPrint('[Phase4] loadPrescriptions ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดใบสั่งยา ล้มเหลว: $e');
    }
  }

  Future<void> loadLabResults(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await _repository.getLabResults(professionId);
      state = state.copyWith(isLoading: false, labResults: results);
    } catch (e, st) {
      debugPrint('[Phase4] loadLabResults ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดผลแล็บ ล้มเหลว: $e');
    }
  }

  Future<void> loadCohorts(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cohorts = await _repository.getCohorts(professionId);
      state = state.copyWith(isLoading: false, cohorts: cohorts);
    } catch (e, st) {
      debugPrint('[Phase4] loadCohorts ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลด cohort ล้มเหลว: $e');
    }
  }
}

final phaseFourProvider =
    StateNotifierProvider<PhaseFourNotifier, PhaseFourState>((ref) {
  final repo = ref.watch(phaseFourRepositoryProvider);
  return PhaseFourNotifier(repo);
});
