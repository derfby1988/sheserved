import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository that only handles emergency-safe queries (patient_id based) so
/// we do not require a consultation_id when fetching health data.
class EmergencyHealthRepository {
  final SupabaseClient _client;

  EmergencyHealthRepository(this._client);

  /// Ensures the JSONB health_info contains the keys we expect before we
  /// render the checkboxes. Returns true when all keys are present.
  Future<bool> verifyHealthInfoKeys(String patientId, List<String> requiredKeys) async {
    final profile = await _client
        .from('consumer_profiles')
        .select('health_info')
        .eq('user_id', patientId)
        .maybeSingle();

    if (profile == null) return false;
    final healthInfo = profile['health_info'] as Map?;
    if (healthInfo == null) return false;

    return requiredKeys.every((key) => healthInfo.containsKey(key));
  }

  Future<Map<String, dynamic>> fetchGeneralHealthInfo(String patientId) async {
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
    }..removeWhere((key, value) => value == null);
  }

  Future<List<Map<String, dynamic>>> fetchRecentPrescriptions(
    String patientId, {
    int limit = 5,
  }) async {
    final rows = await _client
        .from('prescriptions')
        .select('id, medications, notes, status, issued_at')
        .eq('patient_id', patientId)
        .order('issued_at', ascending: false)
        .limit(limit);

    if (rows is! List) return [];
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchRecentConsultationNotes(
    String patientId, {
    int limit = 5,
  }) async {
    final rows = await _client
        .from('consultation_notes')
        .select(
            'id, consultation_id, provider_id, chief_complaint, diagnosis, treatment_plan, recommendations, created_at, follow_up_date')
        .eq('patient_id', patientId)
        .order('created_at', ascending: false)
        .limit(limit);

    if (rows is! List) return [];
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> fetchLatestDeviceMetrics(String patientId,
      {int limitPerMetric = 5}) async {
    final rows = await _client
        .from('device_health_metrics')
        .select('metric_type, value, unit, measured_at, source_name')
        .eq('user_id', patientId)
        .order('measured_at', ascending: false)
        .limit(limitPerMetric * 5);

    final grouped = <String, List<Map<String, dynamic>>>{};
    if (rows is List) {
      for (final entry in rows) {
        final map = Map<String, dynamic>.from(entry as Map);
        final type = (map['metric_type'] as String?) ?? 'unknown';
        grouped.putIfAbsent(type, () => []);
        if (grouped[type]!.length < limitPerMetric) {
          grouped[type]!.add(map);
        }
      }
    }

    return {'metrics': grouped};
  }

  Future<List<Map<String, dynamic>>> fetchWeightHistory(
    String patientId, {
    int limit = 10,
  }) async {
    final rows = await _client
        .from('health_data_logs')
        .select('new_value, created_at')
        .eq('user_id', patientId)
        .eq('field_type', 'weight')
        .order('created_at', ascending: false)
        .limit(limit);

    if (rows is! List) return [];
    return rows.map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      final rawValue = map['new_value']?.toString() ?? '';
      final numeric = rawValue.split(' ').first;
      return {
        'value': numeric,
        'unit': 'กก.',
        'measured_at': map['created_at'],
      };
    }).toList();
  }
}
