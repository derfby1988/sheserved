import 'package:supabase_flutter/supabase_flutter.dart';

/// RPC-backed sport catalog + usage tracking for the shared Sports Hub
/// sport bar (plan 21.7.13).
class SportsHubCatalogRepository {
  final SupabaseClient _client;

  SportsHubCatalogRepository(this._client);

  /// Approved sports ordered by the user's detail-open usage. When the user
  /// has no events (or is signed out) the RPC returns the deterministic
  /// Thai-name order.
  Future<List<Map<String, dynamic>>> listRankedApprovedSports(
    String? userId,
  ) async {
    final res = await _client.rpc(
      'list_sport_ranking',
      params: {'p_user_id': userId},
    );
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Plain catalog fallback used when the ranking RPC fails.
  Future<List<Map<String, dynamic>>> listApprovedSports() async {
    final res = await _client
        .from('sports')
        .select('id,name_th,name_en,icon,status')
        .eq('status', 'approved')
        .order('name_th');
    return List<Map<String, dynamic>>.from(res);
  }

  /// Records a real user detail-open. Idempotent per [eventId]; repeated
  /// opens of the same entity within 24h are dropped server-side.
  Future<bool> recordDetailOpen({
    required String userId,
    required String eventId,
    required String sportId,
    required String domain,
    String? entityId,
  }) async {
    final res = await _client.rpc(
      'record_sport_detail_open',
      params: {
        'p_user_id': userId,
        'p_event_id': eventId,
        'p_sport_id': sportId,
        'p_source_domain': domain,
        'p_entity_id': entityId,
      },
    );
    return res == true;
  }
}
