import '../models/profession.dart';

/// สถานะแต่ละขั้นตอนของการอนุมัติผู้ดูแล ERP (Owner Onboarding)
///
/// step1: ส่งใบสมัคร (รอตรวจสอบ)
/// step2: Admin อนุมัติใบสมัคร
/// step3: ระบบมอบสิทธิ์ Owner + เปิดใช้งาน Feature Flags สำเร็จ (เกิดพร้อมกันผ่าน DB trigger)
/// step4: ผู้ใช้กดสร้างพนักงานเจ้าของสำเร็จ (จุดที่มักค้างจริงเพราะต้องรอผู้ใช้ทำเอง)
enum OwnerOnboardingStep {
  submitted, // step 1
  approved, // step 2
  roleAndFlagsGranted, // step 3
  employeeCreated, // step 4
}

extension OwnerOnboardingStepExtension on OwnerOnboardingStep {
  int get stepNumber {
    switch (this) {
      case OwnerOnboardingStep.submitted:
        return 1;
      case OwnerOnboardingStep.approved:
        return 2;
      case OwnerOnboardingStep.roleAndFlagsGranted:
        return 3;
      case OwnerOnboardingStep.employeeCreated:
        return 4;
    }
  }

  String get label {
    switch (this) {
      case OwnerOnboardingStep.submitted:
        return 'ส่งใบสมัคร';
      case OwnerOnboardingStep.approved:
        return 'Admin อนุมัติ';
      case OwnerOnboardingStep.roleAndFlagsGranted:
        return 'มอบสิทธิ์ Owner + เปิด Feature Flags';
      case OwnerOnboardingStep.employeeCreated:
        return 'สร้างพนักงานเจ้าของสำเร็จ';
    }
  }
}

/// ข้อมูลติดตามสถานะการอนุมัติผู้ดูแล ERP (Owner) รายเคส
class OwnerOnboardingTracking {
  final String applicationId;
  final String userId;
  final String fullName;
  final String username;
  final String professionId;
  final String professionName;
  final VerificationStatus status;
  final String? reviewNote;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  /// true ถ้าเจอ employee_roles ที่ role_name = 'owner' และ is_active = true
  final bool hasOwnerRole;

  /// true ถ้าเจอ record ใน employees ของ user นี้ในองค์กรนี้
  final bool hasEmployeeRecord;

  /// ใครยกเลิก: 'user', 'auto_profession_change', null (ถ้าไม่ใช่ cancelled)
  final String? cancelledBy;

  /// เวลาที่ยกเลิก
  final DateTime? cancelledAt;

  const OwnerOnboardingTracking({
    required this.applicationId,
    required this.userId,
    required this.fullName,
    required this.username,
    required this.professionId,
    required this.professionName,
    required this.status,
    this.reviewNote,
    required this.createdAt,
    this.reviewedAt,
    required this.hasOwnerRole,
    required this.hasEmployeeRecord,
    this.cancelledBy,
    this.cancelledAt,
  });

  /// ขั้นตอนปัจจุบันที่ "เสร็จสมบูรณ์แล้ว" ล่าสุด (1-4)
  /// ถ้าเคสถูกปฏิเสธจะคืนค่า null (ใช้ [isRejected] แทนในการแสดงผล)
  int? get currentStepNumber {
    if (status == VerificationStatus.rejected) return null;
    if (status == VerificationStatus.cancelled) return null;
    if (status == VerificationStatus.pending) {
      return OwnerOnboardingStep.submitted.stepNumber;
    }
    // status == approved
    if (!hasOwnerRole) return OwnerOnboardingStep.approved.stepNumber;
    if (!hasEmployeeRecord) {
      return OwnerOnboardingStep.roleAndFlagsGranted.stepNumber;
    }
    return OwnerOnboardingStep.employeeCreated.stepNumber;
  }

  bool get isRejected => status == VerificationStatus.rejected;

  bool get isCancelled => status == VerificationStatus.cancelled;

  String get cancelledByLabel {
    switch (cancelledBy) {
      case 'user':
        return 'ยกเลิกโดยผู้สมัคร';
      case 'auto_profession_change':
        return 'เปลี่ยนกลุ่มแล้ว';
      default:
        return 'ยกเลิกแล้ว';
    }
  }

  bool get isFullyCompleted => currentStepNumber == 4;

  /// true ถ้าอนุมัติแล้วแต่ยังไม่ครบทุกขั้นตอน (ถือว่า "ค้าง")
  bool get isStuck =>
      status == VerificationStatus.approved && !isFullyCompleted;
}
