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

  /// Fetch the patient's health data respecting granted fields.
  /// Throws if the latest request is not granted or patient info is missing.
  Future<Map<String, dynamic>> fetchGrantedHealthData({
    required String consultationId,
    required String doctorId,
    Map<String, dynamic>? existingRequest,
  }) async {
    Map<String, dynamic>? request = existingRequest != null
        ? Map<String, dynamic>.from(existingRequest)
        : await getLatestRequest(
            consultationId: consultationId,
            doctorId: doctorId,
          );

    if (request == null) {
      throw Exception('ไม่พบคำขอสิทธิ์ข้อมูลสุขภาพล่าสุด');
    }
    if (request['status'] != 'granted') {
      throw Exception('ยังไม่ได้รับการอนุญาตให้เข้าถึงข้อมูลสุขภาพ');
    }

    final patientId = request['patient_id'] as String?;
    if (patientId == null) {
      throw Exception('ไม่พบรหัสผู้ป่วยในคำขอสิทธิ์ข้อมูลสุขภาพ');
    }

    final grantedFields = Map<String, bool>.from(
      (request['granted_fields'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value == true),
          ) ??
          const {
            'general': true,
            'history': true,
            'labs': true,
            'medications': true,
          },
    );

    final result = <String, dynamic>{
      'request': request,
      'patientId': patientId,
      'grantedFields': grantedFields,
    };

    if (grantedFields['general'] == true) {
      result['general'] = await _fetchGeneralHealthInfo(patientId);
    }
    if (grantedFields['history'] == true) {
      result['history'] = await _fetchConsultationNotes(
        consultationId: consultationId,
        patientId: patientId,
      );
    }
    if (grantedFields['labs'] == true) {
      result['labs'] = await _fetchDeviceMetrics(patientId);
    }
    if (grantedFields['medications'] == true) {
      result['medications'] = await _fetchPrescriptions(
        consultationId: consultationId,
        patientId: patientId,
      );
    }

    return result;
  }

  Future<Map<String, dynamic>> _fetchGeneralHealthInfo(String patientId) async {
    final profile = await _client
        .from('consumer_profiles')
        .select('health_info, birthday, emergency_contact, emergency_phone')
        .eq('user_id', patientId)
        .maybeSingle();

    final user = await _client
        .from('users')
        .select('first_name, last_name, profile_image_url')
        .eq('id', patientId)
        .maybeSingle();

    return {
      'profile': user,
      'health_info': profile?['health_info'],
      'birthday': profile?['birthday'],
      'emergency_contact': profile?['emergency_contact'],
      'emergency_phone': profile?['emergency_phone'],
      'weight_history': await _fetchWeightHistory(patientId),
    }..removeWhere((key, value) => value == null);
  }

  Future<List<Map<String, dynamic>>> _fetchWeightHistory(String patientId) async {
    try {
      final rows = await _client
          .from('health_data_logs')
          .select('new_value, created_at')
          .eq('user_id', patientId)
          .eq('field_type', 'weight')
          .order('created_at', ascending: false)
          .limit(10);

      if (rows is! List) return <Map<String, dynamic>>[];

      return rows.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        final rawValue = map['new_value']?.toString() ?? '';
        final numeric = rawValue.split(' ').first;
        return <String, dynamic>{
          'value': numeric,
          'unit': 'กก.',
          'measured_at': map['created_at'],
        };
      }).toList();
    } catch (e) {
      debugPrint('[HealthDataPermissionRepository] _fetchWeightHistory error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchConsultationNotes({
    required String consultationId,
    required String patientId,
  }) async {
    final rows = await _client
        .from('consultation_notes')
        .select(
            'id, consultation_id, provider_id, chief_complaint, diagnosis, treatment_plan, recommendations, created_at, follow_up_date')
        .eq('patient_id', patientId)
        .eq('consultation_id', consultationId)
        .order('created_at', ascending: false)
        .limit(5);

    return rows is List
        ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> _fetchDeviceMetrics(String patientId) async {
    final rows = await _client
        .from('device_health_metrics')
        .select('metric_type, value, unit, measured_at, source_name')
        .eq('user_id', patientId)
        .order('measured_at', ascending: false)
        .limit(40);

    final grouped = <String, List<Map<String, dynamic>>>{};
    if (rows is List) {
      for (final item in rows) {
        final map = Map<String, dynamic>.from(item as Map);
        final type = (map['metric_type'] as String?) ?? 'unknown';
        grouped.putIfAbsent(type, () => []);
        if (grouped[type]!.length < 5) {
          grouped[type]!.add(map);
        }
      }
    }
    return {'metrics': grouped};
  }

  Future<List<Map<String, dynamic>>> _fetchPrescriptions({
    required String consultationId,
    required String patientId,
  }) async {
    final rows = await _client
        .from('prescriptions')
        .select('id, medications, notes, status, issued_at')
        .eq('patient_id', patientId)
        .eq('consultation_id', consultationId)
        .order('issued_at', ascending: false)
        .limit(5);

    return rows is List
        ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
  }
}
