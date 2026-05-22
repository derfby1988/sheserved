import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository layer for the Health Data Permission workflow (Phase 6.3)
class HealthDataPermissionRepository {
  final SupabaseClient _client;

  HealthDataPermissionRepository(this._client);

  /// Request permission from a patient to read their health data.
  /// If a pending request already exists for the same consultation & doctor,
  /// we simply return it to avoid duplicated rows.
  Future<Map<String, dynamic>> requestPermission({
    required String consultationId,
    required String doctorId,
    required String patientId,
    required Map<String, bool> requestedFields,
    String? doctorName,
  }) async {
    try {
      final existing = await _client
          .from('health_data_permission_requests')
          .select()
          .match({
            'consultation_id': consultationId,
            'doctor_id': doctorId,
          })
          .order('requested_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null && existing['status'] == 'pending') {
        return Map<String, dynamic>.from(existing);
      }

      final payload = {
        'consultation_id': consultationId,
        'doctor_id': doctorId,
        'doctor_name': doctorName ?? 'Doctor',
        'patient_id': patientId,
        'status': 'pending',
        'requested_at': DateTime.now().toIso8601String(),
        'granted_fields': requestedFields,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await _client
          .from('health_data_permission_requests')
          .insert(payload)
          .select()
          .single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('[HealthDataPermissionRepository] requestPermission error: $e');
      rethrow;
    }
  }

  /// Update a pending request with the patient's decision.
  Future<Map<String, dynamic>> respondPermission({
    required String requestId,
    required bool granted,
    required Map<String, bool> grantedFields,
  }) async {
    try {
      final data = {
        'status': granted ? 'granted' : 'denied',
        'granted_fields': grantedFields,
        'granted_at': granted ? DateTime.now().toIso8601String() : null,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await _client
          .from('health_data_permission_requests')
          .update(data)
          .eq('id', requestId)
          .select()
          .single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('[HealthDataPermissionRepository] respondPermission error: $e');
      rethrow;
    }
  }

  /// Fetch the latest request for a consultation to drive UI state.
  Future<Map<String, dynamic>?> getLatestRequest({
    required String consultationId,
    required String doctorId,
  }) async {
    try {
      final response = await _client
          .from('health_data_permission_requests')
          .select()
          .match({
            'consultation_id': consultationId,
            'doctor_id': doctorId,
          })
          .order('requested_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response == null ? null : Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('[HealthDataPermissionRepository] getLatestRequest error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getLatestForConsultation(
      String consultationId) async {
    try {
      final response = await _client
          .from('health_data_permission_requests')
          .select()
          .eq('consultation_id', consultationId)
          .order('requested_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response == null ? null : Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint(
          '[HealthDataPermissionRepository] getLatestForConsultation error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPendingForPatient({
    required String consultationId,
    required String patientId,
  }) async {
    try {
      final response = await _client
          .from('health_data_permission_requests')
          .select()
          .match({
            'consultation_id': consultationId,
            'patient_id': patientId,
          })
          .inFilter('status', ['pending', 'granted'])
          .order('requested_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response == null ? null : Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint(
          '[HealthDataPermissionRepository] getPendingForPatient error: $e');
      return null;
    }
  }
}
