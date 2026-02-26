import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupRoleRepository {
  final SupabaseClient _client;

  GroupRoleRepository(this._client);

  Future<void> addUserToGroup(String professionId, String userId, int roleLevel) async {
    final now = DateTime.now().toIso8601String();
    
    try {
      // 1. Add to user_group_roles (Optional fallback)
      await _client.from('user_group_roles').upsert({
        'profession_id': professionId,
        'user_id': userId,
        'role_level': roleLevel,
        'created_at': now,
        'updated_at': now,
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Optional user_group_roles update failed: $e');
    }

    // 2. Sync with users table (Primary source if table above is missing)
    await _client.from('users').update({
      'profession_id': professionId,
      'updated_at': now,
    }).eq('id', userId);
  }

  Future<void> removeUserFromGroup(String professionId, String userId) async {
    try {
      // 1. Remove from user_group_roles
      await _client
          .from('user_group_roles')
          .delete()
          .eq('profession_id', professionId)
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Optional user_group_roles delete failed: $e');
    }

    // 2. Clear from users table
    await _client.from('users').update({
      'profession_id': null,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId).eq('profession_id', professionId);
  }

  Future<void> updateUserRole(String professionId, String userId, int roleLevel) async {
    final now = DateTime.now().toIso8601String();
    try {
      await _client
          .from('user_group_roles')
          .update({
            'role_level': roleLevel,
            'updated_at': now,
          })
          .eq('profession_id', professionId)
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('updateUserRole in user_group_roles failed: $e');
      // No fallback for role level yet if table is missing as users table doesn't have it
    }
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(String professionId) async {
    final List<Map<String, dynamic>> members = [];
    final Set<String> processedUserIds = {};

    try {
      // 1. Try fetching from user_group_roles
      final response = await _client
          .from('user_group_roles')
          .select('''
            role_level,
            users:user_id (id, email, first_name, last_name, profile_image_url)
          ''')
          .eq('profession_id', professionId)
          .timeout(const Duration(seconds: 7));
          
      for (final row in (response as List)) {
        final userData = row['users'] as Map<String, dynamic>?;
        if (userData != null) {
          processedUserIds.add(userData['id'] as String);
          members.add({
            ...userData,
            'role_level': row['role_level'],
          });
        }
      }
    } catch (e) {
      debugPrint('getGroupMembers from user_group_roles failed (switching to fallback): $e');
    }
      
    try {
      // 2. Fallback/Complement: fetch from users table directly
      final primaryResponse = await _client
          .from('users')
          .select('id, email, first_name, last_name, profile_image_url')
          .eq('profession_id', professionId)
          .timeout(const Duration(seconds: 7));
          
      for (final user in (primaryResponse as List)) {
        final userId = user['id'] as String;
        if (!processedUserIds.contains(userId)) {
          members.add({
            ...user,
            'role_level': 3, // Default to Member level
          });
          processedUserIds.add(userId);
        }
      }
    } catch (e) {
      debugPrint('getGroupMembers from users table failed: $e');
      if (members.isEmpty) rethrow; // If both fail, then throw
    }

    members.sort((a, b) => (a['first_name'] ?? '').toString().compareTo((b['first_name'] ?? '').toString()));
    return members;
  }
}
