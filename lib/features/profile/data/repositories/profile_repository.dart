import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../admin/models/profession.dart';
import '../../../admin/models/registration_field_config.dart';
import '../../../auth/data/models/user_model.dart';

/// Profile Repository - Manages dynamic profile data and combined profile views
class ProfileRepository {
  final SupabaseClient _client;

  ProfileRepository(this._client);

  /// Get combined profile data for a user
  Future<Map<String, dynamic>> getFullProfileData(String userId) async {
    try {
      // 1. Get core user data
      final userResponse = await _client.from('users').select('*, professions(is_volunteer), role').eq('id', userId).single();
      final user = UserModel.fromJson(userResponse);

      // 2. Get profession and its field configurations
      Profession? profession;
      List<RegistrationFieldConfig> fields = [];
      
      if (user.professionId != null) {
        final profResponse = await _client.from('professions').select('*, category_data:user_categories(*)').eq('id', user.professionId!).single();
        profession = Profession.fromJson(profResponse);
        
        final fieldsResponse = await _client
            .from('registration_field_configs')
            .select()
            .eq('profession_id', user.professionId!)
            .eq('is_active', true)
            .order('field_order');
        
        fields = (fieldsResponse as List).map((f) => RegistrationFieldConfig.fromJson(f)).toList();
      }

      // 3. Get specific profile data based on UserType
      dynamic specificProfile;
      if (user.userType == UserType.consumer) {
        final res = await _client.from('consumer_profiles').select().eq('user_id', userId).maybeSingle();
        if (res != null) specificProfile = ConsumerProfile.fromJson(res);
      } else if (user.userType == UserType.expert) {
        final res = await _client.from('expert_profiles').select().eq('user_id', userId).maybeSingle();
        if (res != null) specificProfile = ExpertProfile.fromJson(res);
      } else if (user.userType == UserType.clinic) {
        final res = await _client.from('clinic_profiles').select().eq('user_id', userId).maybeSingle();
        if (res != null) specificProfile = ClinicProfile.fromJson(res);
      }

      // 4. Get dynamic registration data
      final regDataResponse = await _client.from('user_registration_data').select().eq('user_id', userId);
      final Map<String, String> dynamicData = {};
      for (final row in (regDataResponse as List)) {
        dynamicData[row['field_id']] = row['field_value'] ?? '';
      }

      return {
        'user': user,
        'profession': profession,
        'fields': fields,
        'specificProfile': specificProfile,
        'dynamicData': dynamicData,
      };
    } catch (e) {
      debugPrint('ProfileRepository.getFullProfileData error: $e');
      rethrow;
    }
  }

  /// Update profile data
  Future<void> updateProfile({
    required String userId,
    Map<String, dynamic>? coreData,
    Map<String, dynamic>? specificData,
    Map<String, String>? dynamicData,
    UserType? userType,
  }) async {
    final now = DateTime.now().toIso8601String();
    
    try {
      // 1. Update core user table if needed
      if (coreData != null && coreData.isNotEmpty) {
        coreData['updated_at'] = now;
        await _client.from('users').update(coreData).eq('id', userId);
      }

      // 2. Update specific profile table
      if (specificData != null && specificData.isNotEmpty && userType != null) {
        specificData['updated_at'] = now;
        String table = '';
        if (userType == UserType.consumer) {
          table = 'consumer_profiles';
        } else if (userType == UserType.expert) {
          table = 'expert_profiles';
        } else if (userType == UserType.clinic) {
          table = 'clinic_profiles';
        }
        
        if (table.isNotEmpty) {
          await _client.from(table).update(specificData).eq('user_id', userId);
        }
      }

      // 3. Update dynamic registration data
      if (dynamicData != null && dynamicData.isNotEmpty) {
        final records = dynamicData.entries.map((e) => {
          'user_id': userId,
          'field_id': e.key,
          'field_value': e.value,
          'updated_at': now,
        }).toList();

        await _client.from('user_registration_data').upsert(
          records,
          onConflict: 'user_id,field_id',
        );
      }
    } catch (e) {
      debugPrint('ProfileRepository.updateProfile error: $e');
      rethrow;
    }
  }
}
