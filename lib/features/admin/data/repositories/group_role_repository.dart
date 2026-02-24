import 'package:supabase_flutter/supabase_flutter.dart';

class GroupRoleRepository {
  final SupabaseClient _client;

  GroupRoleRepository(this._client);

  Future<void> addUserToGroup(String professionId, String userId, int roleLevel) async {
    final now = DateTime.now().toIso8601String();
    await _client.from('user_group_roles').upsert({
      'profession_id': professionId,
      'user_id': userId,
      'role_level': roleLevel,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> removeUserFromGroup(String professionId, String userId) async {
    await _client
        .from('user_group_roles')
        .delete()
        .eq('profession_id', professionId)
        .eq('user_id', userId);
  }

  Future<void> updateUserRole(String professionId, String userId, int roleLevel) async {
    final now = DateTime.now().toIso8601String();
    await _client
        .from('user_group_roles')
        .update({
          'role_level': roleLevel,
          'updated_at': now,
        })
        .eq('profession_id', professionId)
        .eq('user_id', userId);
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(String professionId) async {
    final response = await _client
        .from('user_group_roles')
        .select('''
          *,
          users:user_id(id, email, raw_user_meta_data)
        ''')
        .eq('profession_id', professionId)
        .order('role_level', ascending: true);
        
    return List<Map<String, dynamic>>.from(response);
  }
}
