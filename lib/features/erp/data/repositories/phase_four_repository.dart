import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/emr_record.dart';
import '../models/opd_visit.dart';

/// Repository สำหรับ ERP Phase 4 — Clinical & Advanced (HIS, LIS, CDP)
class PhaseFourRepository {
  final SupabaseClient _client;

  PhaseFourRepository(this._client);

  // ========================
  // EMR RECORDS
  // ========================

  Future<List<EmrRecord>> getEmrRecords(String professionId) async {
    try {
      final response = await _client
          .from('emr_records')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => EmrRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase4Repo] getEmrRecords error: $e');
      return [];
    }
  }

  Future<EmrRecord?> createEmrRecord(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('emr_records')
          .insert(data)
          .select()
          .single();
      return EmrRecord.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase4Repo] createEmrRecord error: $e');
      return null;
    }
  }

  // ========================
  // OPD VISITS
  // ========================

  Future<List<OpdVisit>> getOpdVisits(String professionId) async {
    try {
      final response = await _client
          .from('opd_visits')
          .select()
          .eq('profession_id', professionId)
          .order('visit_date', ascending: false);
      return (response as List)
          .map((e) => OpdVisit.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase4Repo] getOpdVisits error: $e');
      return [];
    }
  }

  Future<String?> createOpdVisit({
    required String professionId,
    required String patientId,
    String? doctorId,
    String? chiefComplaint,
    bool isWalkIn = true,
  }) async {
    try {
      final response = await _client.rpc(
        'create_opd_visit',
        params: {
          'p_profession_id': professionId,
          'p_patient_id': patientId,
          'p_doctor_id': doctorId,
          'p_chief_complaint': chiefComplaint,
          'p_is_walk_in': isWalkIn,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase4Repo] createOpdVisit error: $e');
      return null;
    }
  }

  Future<bool> updateOpdStatus(String visitId, String status) async {
    try {
      await _client
          .from('opd_visits')
          .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', visitId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase4Repo] updateOpdStatus error: $e');
      return false;
    }
  }

  // ========================
  // MEDICAL PRESCRIPTIONS (ERP HIS)
  // ========================

  Future<List<Map<String, dynamic>>> getPrescriptions(String professionId) async {
    try {
      final response = await _client
          .from('medical_prescriptions')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e, st) {
      debugPrint('[Phase4Repo] getPrescriptions error: $e');
      return [];
    }
  }

  // ========================
  // LAB RESULTS
  // ========================

  Future<List<Map<String, dynamic>>> getLabResults(String professionId) async {
    try {
      final response = await _client
          .from('lab_results')
          .select('*, lab_tests(*)')
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e, st) {
      debugPrint('[Phase4Repo] getLabResults error: $e');
      return [];
    }
  }

  // ========================
  // CUSTOMER COHORTS
  // ========================

  Future<List<Map<String, dynamic>>> getCohorts(String professionId) async {
    try {
      final response = await _client
          .from('customer_cohorts')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e, st) {
      debugPrint('[Phase4Repo] getCohorts error: $e');
      return [];
    }
  }

  Future<bool> addPatientToCohort(String cohortId, String patientId, {String? reason}) async {
    try {
      final response = await _client.rpc(
        'add_patient_to_cohort',
        params: {
          'p_cohort_id': cohortId,
          'p_patient_id': patientId,
          'p_reason': reason,
        },
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase4Repo] addPatientToCohort error: $e');
      return false;
    }
  }
}
