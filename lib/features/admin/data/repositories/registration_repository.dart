import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/profession.dart';
import '../../models/owner_onboarding_tracking.dart';

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
      // 1. Update application status — guard: ต้องเป็น pending เท่านั้น (กัน race condition)
      final updatedRows = await _client.from('registration_applications').update({
        'status': 'approved',
        'reviewed_by': reviewedBy,
        'reviewed_at': now,
        'updated_at': now,
      }).eq('id', application.id).eq('status', 'pending').select();

      if ((updatedRows as List).isEmpty) {
        throw Exception(
          'ไม่สามารถอนุมัติได้: ใบสมัครไม่อยู่ในสถานะ pending หรือถูกยกเลิกไปแล้ว',
        );
      }

      // 2. ตรวจสอบว่า user ยังอยู่ในอาชีพนี้หรือไม่
      final userRes = await _client
          .from('users')
          .select('profession_id')
          .eq('id', application.oderId)
          .single();

      if (userRes['profession_id'] != application.professionId) {
        // user เปลี่ยนอาชีพไปแล้ว → auto-cancel และแจ้ง admin
        await _client.from('registration_applications').update({
          'status': 'cancelled',
          'cancelled_by': 'auto_profession_change',
          'cancelled_at': now,
          'updated_at': now,
        }).eq('id', application.id);
        throw Exception(
          'ผู้สมัครเปลี่ยนอาชีพไปแล้ว ใบสมัครนี้ถูกยกเลิกอัตโนมัติ',
        );
      }

      // 3. Update user's profession and verification status
      await _client.from('users').update({
        'profession_id': application.professionId,
        'verification_status': 'verified',
        'updated_at': now,
      }).eq('id', application.oderId);

      // 4. Create provider profile and credentials if profession requires verification
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

      // 5. Fallback/Local handling: If DB trigger doesn't run, ensure Owner role is bound
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

  /// ผู้ใช้ยกเลิกใบสมัครของตัวเอง (ต้องเป็น pending เท่านั้น)
  /// ใช้ RPC atomic — cancel + reset profession ใน transaction เดียว
  Future<void> cancelApplication(String applicationId, String userId) async {
    try {
      await _client.rpc(
        'cancel_registration_application',
        params: {
          'p_application_id': applicationId,
          'p_user_id': userId,
        },
      );
      debugPrint('Cancelled application $applicationId for user $userId');
    } on PostgrestException catch (e) {
      final msg = e.message;
      if (msg.contains('NOT_PENDING_OR_NOT_OWNER')) {
        throw Exception(
          'ไม่สามารถยกเลิกได้: ใบสมัครไม่อยู่ในสถานะ pending หรือไม่ใช่ของผู้ใช้คนนี้',
        );
      }
      rethrow;
    } catch (e) {
      debugPrint('RegistrationRepository.cancelApplication error: $e');
      rethrow;
    }
  }

  /// ดึงใบสมัคร pending ล่าสุดของ user (สำหรับแสดงในหน้า Profile)
  Future<RegistrationApplication?> getPendingApplicationForUser(String userId) async {
    try {
      final response = await _client
          .from('registration_applications')
          .select('*, profession:professions(*)')
          .eq('user_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);

      if ((response as List).isEmpty) return null;
      return RegistrationApplication.fromJson(response[0]);
    } catch (e) {
      debugPrint('RegistrationRepository.getPendingApplicationForUser error: $e');
      return null;
    }
  }

  /// ปฏิเสธใบสมัคร (atomic — reject + reset profession ใน transaction เดียว)
  Future<void> rejectApplication(
    RegistrationApplication application,
    String note, {
    String? reviewedBy,
  }) async {
    try {
      await _client.rpc(
        'reject_registration_application',
        params: {
          'p_application_id': application.id,
          'p_review_note': note,
          'p_reviewed_by': reviewedBy,
        },
      );
      debugPrint('Rejected application for user: ${application.oderId}');
    } on PostgrestException catch (e) {
      final msg = e.message;
      if (msg.contains('NOT_PENDING')) {
        throw Exception(
          'ไม่สามารถปฏิเสธได้: ใบสมัครไม่อยู่ในสถานะ pending หรือถูกยกเลิกไปแล้ว',
        );
      }
      rethrow;
    } catch (e) {
      debugPrint('RegistrationRepository.rejectApplication error: $e');
      rethrow;
    }
  }

  /// ดึงสถานะการอนุมัติผู้ดูแล ERP (Owner Onboarding) เฉพาะใบสมัครที่ขอเป็น Owner
  /// (registration_data.is_owner_request = true) สถานะ pending/approved/rejected
  /// ยกเว้น cancelled (เคสยกเลิกไม่อยู่ใน pipeline onboarding อีกต่อไป)
  /// โดยตรวจสอบ employee_roles และ employees เพื่อคำนวณว่าแต่ละเคสค้างอยู่ขั้นตอนใด
  Future<List<OwnerOnboardingTracking>> getOwnerOnboardingTracking() async {
    try {
      // 1. ดึงใบสมัครที่ขอเป็น Owner ทุกสถานะ ยกเว้น cancelled
      final appsRes = await _client
          .from('registration_applications')
          .select('*, profession:professions(*)')
          .eq('registration_data->>is_owner_request', 'true')
          .neq('status', 'cancelled')
          .order('created_at', ascending: false);

      final applications = (appsRes as List)
          .map((json) => RegistrationApplication.fromJson(json))
          .toList();

      if (applications.isEmpty) return [];

      // Map for looking up cancelled_by/cancelled_at by application id
      final cancelledInfo = <String, Map<String, dynamic>>{};
      for (final row in appsRes) {
        cancelledInfo[row['id']] = row;
      }

      final professionIds =
          applications.map((a) => a.professionId).toSet().toList();
      final userIds = applications.map((a) => a.oderId).toSet().toList();

      // 2. ดึง owner role id ของแต่ละ profession
      final rolesRes = await _client
          .from('organization_roles')
          .select('id, profession_id')
          .eq('role_name', 'owner')
          .inFilter('profession_id', professionIds);

      final ownerRoleIdByProfession = <String, String>{};
      for (final row in (rolesRes as List)) {
        ownerRoleIdByProfession[row['profession_id'] as String] =
            row['id'] as String;
      }
      final ownerRoleIds = ownerRoleIdByProfession.values.toList();

      // 3. ดึง employee_roles ที่ active และมี role_id ตรงกับ owner role
      final Set<String> hasOwnerRoleKeys = {};
      if (ownerRoleIds.isNotEmpty) {
        final empRolesRes = await _client
            .from('employee_roles')
            .select('user_id, profession_id, role_id, is_active')
            .inFilter('user_id', userIds)
            .inFilter('profession_id', professionIds)
            .inFilter('role_id', ownerRoleIds)
            .eq('is_active', true);

        for (final row in (empRolesRes as List)) {
          hasOwnerRoleKeys
              .add('${row['profession_id']}_${row['user_id']}');
        }
      }

      // 4. ดึง employees ที่ผูกกับ user + profession นี้แล้ว
      final employeesRes = await _client
          .from('employees')
          .select('user_id, profession_id')
          .inFilter('user_id', userIds)
          .inFilter('profession_id', professionIds);

      final Set<String> hasEmployeeKeys = {};
      for (final row in (employeesRes as List)) {
        final uid = row['user_id'];
        if (uid == null) continue;
        hasEmployeeKeys.add('${row['profession_id']}_$uid');
      }

      // 5. ประกอบผลลัพธ์
      return applications.map((app) {
        final key = '${app.professionId}_${app.oderId}';
        return OwnerOnboardingTracking(
          applicationId: app.id,
          userId: app.oderId,
          fullName: app.fullName,
          username: app.username,
          professionId: app.professionId,
          professionName: app.profession?.name ?? 'ไม่ระบุ',
          status: app.status,
          reviewNote: app.reviewNote,
          createdAt: app.createdAt,
          reviewedAt: app.reviewedAt,
          hasOwnerRole: hasOwnerRoleKeys.contains(key),
          hasEmployeeRecord: hasEmployeeKeys.contains(key),
          cancelledBy: cancelledInfo[app.id]?['cancelled_by'] as String?,
          cancelledAt: cancelledInfo[app.id]?['cancelled_at'] != null
              ? DateTime.parse(cancelledInfo[app.id]!['cancelled_at'] as String)
              : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('RegistrationRepository.getOwnerOnboardingTracking error: $e');
      return [];
    }
  }
}
