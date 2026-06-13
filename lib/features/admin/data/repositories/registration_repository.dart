import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/profession.dart';

class RegistrationRepository {
  final SupabaseClient _client;

  RegistrationRepository(this._client);

  /// ดึงใบสมัครตามสถานะ
  Future<List<RegistrationApplication>> getApplications(VerificationStatus status) async {
    try {
      final response = await _client
          .from('registration_applications')
          .select('*, profession:professions(*)')
          .eq('status', status.value)
          .order('created_at', ascending: false);

      return (response as List).map((json) => RegistrationApplication.fromJson(json)).toList();
    } catch (e) {
      debugPrint('RegistrationRepository.getApplications error: $e');
      return [];
    }
  }

  /// อนุมัติใบสมัคร
  Future<void> approveApplication(RegistrationApplication application) async {
    final now = DateTime.now().toIso8601String();
    
    try {
      // 1. Update application status
      await _client.from('registration_applications').update({
        'status': 'approved',
        'reviewed_at': now,
        'updated_at': now,
      }).eq('id', application.id);

      // 2. Update user's profession and verification status
      // Note: Application uses oderId (which is user_id in DB)
      await _client.from('users').update({
        'profession_id': application.professionId,
        'verification_status': 'verified',
        'updated_at': now,
      }).eq('id', application.oderId);

      // 3. Fallback/Local handling: If DB trigger doesn't run, ensure Owner role is bound
      final isOwnerReq = application.registrationData['is_owner_request'] == 'true' ||
          application.registrationData['is_owner_request'] == true;
      
      if (isOwnerReq) {
        try {
          // Find owner role
          final roleRes = await _client
              .from('organization_roles')
              .select('id')
              .eq('profession_id', application.professionId)
              .eq('role_name', 'owner')
              .limit(1);
          
          if (roleRes != null && (roleRes as List).isNotEmpty) {
            final ownerRoleId = roleRes[0]['id'];
            
            // Find main branch
            final branchRes = await _client
                .from('organization_branches')
                .select('id')
                .eq('profession_id', application.professionId)
                .order('is_main_branch', ascending: false)
                .limit(1);
            
            final branchId = (branchRes != null && (branchRes as List).isNotEmpty)
                ? branchRes[0]['id']
                : null;
            
            // Insert employee role
            await _client.from('employee_roles').insert({
              'profession_id': application.professionId,
              'branch_id': branchId,
              'user_id': application.oderId,
              'role_id': ownerRoleId,
              'is_active': true,
            });
            debugPrint('Successfully assigned Owner role to user: ${application.oderId}');
          }
        } catch (e) {
          debugPrint('Error assigning Owner role in repository: $e (This is expected if Supabase trigger already did it)');
        }
      }

      debugPrint('Approved application for user: ${application.oderId}');
    } catch (e) {
      debugPrint('RegistrationRepository.approveApplication error: $e');
      rethrow;
    }
  }

  /// ปฏิเสธใบสมัคร
  Future<void> rejectApplication(RegistrationApplication application, String note) async {
    final now = DateTime.now().toIso8601String();
    
    try {
      // 1. Update application status
      await _client.from('registration_applications').update({
        'status': 'rejected',
        'review_note': note,
        'reviewed_at': now,
        'updated_at': now,
      }).eq('id', application.id);

      // 2. Update user's verification status
      await _client.from('users').update({
        'verification_status': 'rejected',
        'updated_at': now,
      }).eq('id', application.oderId);

      debugPrint('Rejected application for user: ${application.oderId}');
    } catch (e) {
      debugPrint('RegistrationRepository.rejectApplication error: $e');
      rethrow;
    }
  }
}
