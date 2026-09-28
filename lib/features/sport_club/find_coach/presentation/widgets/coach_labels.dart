import 'package:flutter/material.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';

import '../../data/coach_models.dart';

/// Shared Thai labels and formatting for the Find Coach domain.
class CoachLabels {
  const CoachLabels._();

  static String mode(TeachingMode m) => switch (m) {
    TeachingMode.online => 'ออนไลน์',
    TeachingMode.both => 'ออนไซต์ + ออนไลน์',
    _ => 'ออนไซต์',
  };

  static String level(String level) => switch (level) {
    'beginner' => 'เริ่มต้น',
    'intermediate' => 'ระดับกลาง',
    'advanced' => 'ขั้นสูง',
    'pro' => 'อาชีพ',
    _ => level,
  };

  static String dayOfWeek(int dow) => switch (dow) {
    0 => 'อาทิตย์',
    1 => 'จันทร์',
    2 => 'อังคาร',
    3 => 'พุธ',
    4 => 'พฤหัสบดี',
    5 => 'ศุกร์',
    6 => 'เสาร์',
    _ => '',
  };

  static String offeringType(CoachOfferingType t) => switch (t) {
    CoachOfferingType.oneOnOne => 'สอนตัวต่อตัว',
    CoachOfferingType.groupClass => 'คลาสกลุ่ม',
    CoachOfferingType.course => 'หลักสูตร',
  };

  static String pricingUnit(CoachPricingUnit u) => switch (u) {
    CoachPricingUnit.perHour => 'ต่อชั่วโมง',
    CoachPricingUnit.perPerson => 'ต่อคน/ครั้ง',
    CoachPricingUnit.perGroup => 'เหมาทั้งกลุ่ม/ครั้ง',
    CoachPricingUnit.perSession => 'ต่อรอบ',
    CoachPricingUnit.package => 'เหมาทั้งหลักสูตร',
  };

  static String offeringStatus(CoachOfferingStatus s) => switch (s) {
    CoachOfferingStatus.draft => 'แบบร่าง',
    CoachOfferingStatus.published => 'เปิดรับสมัคร',
    CoachOfferingStatus.closed => 'ปิดรับสมัคร',
    CoachOfferingStatus.cancelled => 'ยกเลิก',
    CoachOfferingStatus.completed => 'จบแล้ว',
  };

  static Color offeringStatusColor(CoachOfferingStatus s) => switch (s) {
    CoachOfferingStatus.published => const Color(0xFF2E7D32),
    CoachOfferingStatus.closed => const Color(0xFFEF6C00),
    CoachOfferingStatus.draft => const Color(0xFF64748B),
    _ => const Color(0xFF94A3B8),
  };

  static String slotStatus(CoachSlotStatus s) => switch (s) {
    CoachSlotStatus.draft => 'แบบร่าง',
    CoachSlotStatus.published => 'เปิดจอง',
    CoachSlotStatus.booked => 'จองแล้ว',
    CoachSlotStatus.cancelled => 'ยกเลิก',
    CoachSlotStatus.expired => 'หมดอายุ',
  };

  static String enrollmentStatus(CoachEnrollmentStatus s) => switch (s) {
    CoachEnrollmentStatus.pending => 'รอโค้ชอนุมัติ',
    CoachEnrollmentStatus.confirmed => 'ยืนยันแล้ว',
    CoachEnrollmentStatus.rejected => 'ถูกปฏิเสธ',
    CoachEnrollmentStatus.cancelled => 'ยกเลิกแล้ว',
    CoachEnrollmentStatus.expired => 'หมดอายุ',
    CoachEnrollmentStatus.completed => 'เรียนจบแล้ว',
  };

  static Color enrollmentStatusColor(CoachEnrollmentStatus s) =>
      switch (s) {
        CoachEnrollmentStatus.pending => const Color(0xFFEF6C00),
        CoachEnrollmentStatus.confirmed => const Color(0xFF2E7D32),
        CoachEnrollmentStatus.completed => const Color(0xFF1565C0),
        CoachEnrollmentStatus.expired => const Color(0xFF64748B),
        _ => const Color(0xFFC62828),
      };

  static String requestStatus(CoachRequestStatus s) => switch (s) {
    CoachRequestStatus.pending => 'รอโค้ชตอบรับ',
    CoachRequestStatus.confirmed => 'ยืนยันแล้ว',
    CoachRequestStatus.completed => 'เสร็จสิ้น',
    CoachRequestStatus.cancelled => 'ยกเลิก',
    CoachRequestStatus.rejected => 'ปฏิเสธ',
    CoachRequestStatus.expired => 'หมดอายุ',
  };

  static Color requestStatusColor(CoachRequestStatus s) => switch (s) {
    CoachRequestStatus.pending => const Color(0xFFEF6C00),
    CoachRequestStatus.confirmed => const Color(0xFF2E7D32),
    CoachRequestStatus.completed => const Color(0xFF1565C0),
    CoachRequestStatus.expired => const Color(0xFF64748B),
    _ => const Color(0xFFC62828),
  };

  static String coachStatus(CoachStatus s) => switch (s) {
    CoachStatus.pending => 'รอการอนุมัติ',
    CoachStatus.approved => 'อนุมัติแล้ว',
    CoachStatus.rejected => 'ถูกปฏิเสธ',
    CoachStatus.suspended => 'ถูกระงับ',
  };

  static String formatBaht(double? value) =>
      value == null ? '-' : '฿${value.toStringAsFixed(0)}';

  static String sessionRange(CoachOfferingSession s) =>
      formatThaiSessionRange(s.startsAt.toLocal(), s.endsAt.toLocal());

  /// Maps coach-domain RPC error codes to user-facing Thai messages.
  static String mapError(Object e) {
    final raw = e.toString();
    String? found(String code) =>
        raw.contains(code) ? code : null;
    final code =
        found('PROFILE_INCOMPLETE') ??
        found('SLOT_NOT_BOOKABLE') ??
        found('SLOT_ALREADY_BOOKED') ??
        found('SLOT_HAS_ENROLLMENT') ??
        found('SLOT_OVERLAP') ??
        found('OFFERING_NOT_PUBLISHED') ??
        found('SESSION_FULL') ??
        found('SESSION_NOT_SELECTABLE') ??
        found('SESSION_REQUIRED') ??
        found('ENROLLMENT_NOT_PENDING') ??
        found('ALREADY_ENROLLED') ??
        found('ENROLLMENT_NOT_FOUND') ??
        found('CUTOFF_PASSED') ??
        found('MINIMUM_NOT_DUE') ??
        found('REASON_REQUIRED') ??
        found('NOT_AUTHORIZED') ??
        found('UNAUTHORIZED') ??
        found('SELF_REVIEW_NOT_ALLOWED') ??
        found('ALREADY_REVIEWED') ??
        found('NOT_REVIEWABLE') ??
        found('MISSING_CATEGORY_SCORES') ??
        found('TOO_MANY_TAGS') ??
        found('INVALID_TAG') ??
        found('COMMENT_TOO_LONG') ??
        found('REQUEST_NOT_PENDING') ??
        found('SELF_REQUEST_NOT_ALLOWED') ??
        found('COACH_NOT_AVAILABLE') ??
        found('POLICY_ACCEPTANCE_REQUIRED') ??
        '';
    return switch (code) {
      'PROFILE_INCOMPLETE' => 'กรุณากรอกข้อมูลโปรไฟล์ให้ครบก่อนส่งตรวจ',
      'SLOT_NOT_BOOKABLE' => 'ช่วงเวลานี้ไม่เปิดให้จองแล้ว',
      'SLOT_ALREADY_BOOKED' => 'ช่วงเวลานี้ถูกจองแล้ว กรุณาเลือกเวลาอื่น',
      'SLOT_HAS_ENROLLMENT' =>
        'มีผู้เรียนในช่วงเวลานี้แล้ว ใช้การเสนอเปลี่ยนตารางแทน',
      'SLOT_OVERLAP' => 'ช่วงเวลานี้ซ้อนกับ slot อื่นของคุณ',
      'OFFERING_NOT_PUBLISHED' => 'รายการนี้ยังไม่เปิดรับสมัคร',
      'SESSION_FULL' => 'รอบนี้เต็มแล้ว กรุณาเลือกรอบอื่น',
      'SESSION_NOT_SELECTABLE' => 'รอบนี้ไม่สามารถเลือกได้แล้ว',
      'SESSION_REQUIRED' => 'กรุณาเลือกอย่างน้อยหนึ่งรอบ',
      'ENROLLMENT_NOT_PENDING' => 'รายการนี้ถูกจัดการไปแล้ว',
      'ALREADY_ENROLLED' => 'คุณมีการสมัครรายการนี้อยู่แล้ว',
      'ENROLLMENT_NOT_FOUND' => 'ไม่พบการสมัครนี้',
      'CUTOFF_PASSED' => 'เลยเวลาที่อนุญาตตามนโยบายแล้ว',
      'MINIMUM_NOT_DUE' => 'ยังไม่ถึงเวลาตัดสินใจจำนวนผู้เรียนขั้นต่ำ',
      'REASON_REQUIRED' => 'กรุณาระบุเหตุผล',
      'NOT_AUTHORIZED' => 'คุณไม่มีสิทธิ์ดำเนินการนี้',
      'UNAUTHORIZED' => 'กรุณาเข้าสู่ระบบใหม่',
      'SELF_REVIEW_NOT_ALLOWED' => 'ไม่สามารถรีวิวตัวเองได้',
      'ALREADY_REVIEWED' => 'คุณรีวิวรายการนี้แล้ว',
      'NOT_REVIEWABLE' => 'รีวิวได้หลังเรียนจบเท่านั้น',
      'MISSING_CATEGORY_SCORES' => 'กรุณาให้คะแนนครบทั้ง 5 หมวด',
      'TOO_MANY_TAGS' => 'เลือกแท็กได้ไม่เกิน 5 รายการ',
      'INVALID_TAG' => 'แท็กที่เลือกไม่ถูกต้อง',
      'COMMENT_TOO_LONG' => 'ความคิดเห็นยาวเกิน 500 ตัวอักษร',
      'REQUEST_NOT_PENDING' => 'คำขอนี้ถูกจัดการไปแล้ว',
      'SELF_REQUEST_NOT_ALLOWED' => 'ไม่สามารถส่งคำขอให้ตัวเองได้',
      'COACH_NOT_AVAILABLE' => 'โค้ชนี้ไม่เปิดรับคำขอแล้ว',
      'POLICY_ACCEPTANCE_REQUIRED' => 'กรุณายอมรับนโยบายการยกเลิกก่อน',
      _ => 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
    };
  }
}
