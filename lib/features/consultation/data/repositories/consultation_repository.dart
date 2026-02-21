import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/consultation_request_model.dart';
import 'package:sheserved/config/app_config.dart';

class ConsultationRepository {
  final SupabaseClient _client;

  ConsultationRepository(this._client);

  /// Create a new consultation request
  Future<ConsultationRequestModel> createRequest({
    required String userId,
    String? packageId,
    required String packageName,
    required double price,
    Map<String, dynamic> bodyArea = const {},
    Map<String, dynamic> symptomsChart = const {},
  }) async {
    final now = DateTime.now();
    final data = {
      'user_id': userId,
      'package_id': packageId,
      'package_name': packageName,
      'price': price,
      'body_area': bodyArea,
      'symptoms_chart': symptomsChart,
      'status': 'pending',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    if (AppConfig.databaseMode == DatabaseMode.localOnly) {
      // Local setup logic if needed.
    }

    final response = await _client
        .from('consultation_requests')
        .insert(data)
        .select()
        .single();
    return ConsultationRequestModel.fromJson(response);
  }

  /// Get consultation requests for a user
  Future<List<ConsultationRequestModel>> getUserRequests(String userId) async {
    final response = await _client
        .from('consultation_requests')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((e) => ConsultationRequestModel.fromJson(e))
        .toList();
  }

  /// Update consultation request
  Future<ConsultationRequestModel> updateRequest(String id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    final response = await _client
        .from('consultation_requests')
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return ConsultationRequestModel.fromJson(response);
  }
}
