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

  /// Fetch attachments for a registration application
  Future<List<Map<String, dynamic>>> getApplicationAttachments(String applicationId) async {
    try {
      final response = await _client
          .from('registration_application_attachments')
          .select()
          .eq('application_id', applicationId);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('RegistrationRepository.getApplicationAttachments error: $e');
      return [];
    }
  }

  /// อนุมัติใบสมัคร พร้อมสร้าง provider profile/credential เมื่อจำเป็น
  Future<void> approveApplication(
    RegistrationApplication application, {
    String? reviewedBy,
  }) async {
    final now = DateTime.now().toIso8601String();

    try {
      // 1. Update application status
      await _client.from('registration_applications').update({
        'status': 'approved',
        'reviewed_by': reviewedBy,
        'reviewed_at': now,
        'updated_at': now,
      }).eq('id', application.id);

      // 2. Update user's profession and verification status
      await _client.from('users').update({
        'profession_id': application.professionId,
        'verification_status': 'verified',
        'updated_at': now,
      }).eq('id', application.oderId);

      // 3. Create provider profile and credentials if profession requires verification
      final profession = application.profession;
      if (profession != null && profession.requiresVerification) {
        // Upsert provider profile
        final profileData = {
          'user_id': application.oderId,
          'profession_id': application.professionId,
          'is_verified': true,
          'verified_at': now,
          'updated_at': now,
        };
        await _client.from('provider_profiles').upsert(profileData, onConflict: 'user_id,profession_id');

        // Fetch attachments to create credentials
        final attachments = await getApplicationAttachments(application.id);
        final credentials = <Map<String, dynamic>>[];

        for (final attachment in attachments) {
          final fieldKey = attachment['field_key'] as String? ?? '';
          final groupKey = attachment['attachment_group_key'] as String? ?? '';
          final fileUrl = attachment['file_url'] as String? ?? '';

          // Map attachment to credential types based on field_key / group_key
          String credentialType = 'license';
          if (fieldKey.contains('telemedicine') || groupKey.contains('telemedicine')) {
            credentialType = 'telemedicine_license';
          } else if (fieldKey.contains('id_card') || groupKey.contains('id_card')) {
            credentialType = 'id_card';
          } else if (profession.approvalRequiredLicenseTypes?.isNotEmpty ?? false) {
            // Check if this attachment matches any required license type
            for (final requiredType in profession.approvalRequiredLicenseTypes!) {
              if (fieldKey.toLowerCase().contains(requiredType.toLowerCase()) ||
                  groupKey.toLowerCase().contains(requiredType.toLowerCase())) {
                credentialType = requiredType;
                break;
              }
            }
          }

          credentials.add({
            'provider_id': application.oderId,
            'credential_type': credentialType,
            'credential_value': fieldKey,
            'evidence_image_url': fileUrl,
            'status': 'verified',
            'verified_at': now,
            'created_at': now,
            'updated_at': now,
          });
        }

        if (credentials.isNotEmpty) {
          await _client.from('provider_credentials').upsert(
            credentials,
            onConflict: 'provider_id,credential_type',
          );
        }
      }

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
  Future<void> rejectApplication(
    RegistrationApplication application,
    String note, {
    String? reviewedBy,
  }) async {
    final now = DateTime.now().toIso8601String();

    try {
      // 1. Update application status
      await _client.from('registration_applications').update({
        'status': 'rejected',
        'review_note': note,
        'reviewed_by': reviewedBy,
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
