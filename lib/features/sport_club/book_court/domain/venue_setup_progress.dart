import '../data/book_court_models.dart';

/// Step in the owner venue-setup flow (Phase 21.7.11).
///
/// Mirrors the supply checklist from Match_Sport_PLAN.md so the owner can see
/// at a glance what remains before the venue can go live. Every flag maps to
/// persisted data — partial rows never count as configured:
///   * hours  = all 7 weekdays explicitly set (open window or closed)
///   * amenities = at least one amenity OR the owner confirmed "ไม่มี"
///   * terms  = a custom active version OR confirmed platform base terms (v0)
///   * courts = at least one ACTIVE court (inactive-only does not count)
enum VenueSetupStepId {
  ownerApproved,
  venueCreated,
  sports,
  hours,
  amenities,
  terms,
  courts,
  venueApproved,
}

class VenueSetupStep {
  final VenueSetupStepId id;
  final String label;

  /// The requirement of this step is already satisfied.
  final bool done;

  /// The owner can act on this step right now — every prerequisite is met.
  /// Read-only waits (e.g. admin review) are never actionable.
  final bool actionable;

  /// Read-only explanation shown under the label (review status for step 8,
  /// or why a non-actionable prerequisite is unmet). Never set on rows the
  /// owner can simply tap to fix.
  final String? note;

  const VenueSetupStep({
    required this.id,
    required this.label,
    required this.done,
    this.actionable = false,
    this.note,
  });
}

/// Ordered checklist shown on the owner venue-manage page.
///
/// Steps 1–2 are read-only facts about the owner profile / venue itself —
/// the per-venue page never owns those actions. Steps 3–7 are actionable
/// while incomplete. Step 8 is informational and reports the real review
/// status (draft/pending/rejected/suspended/approved), not a generic wait.
List<VenueSetupStep> computeVenueSetupSteps({
  required bool ownerApproved,
  required bool venueCreated,
  required bool hasSports,
  required bool hoursComplete,
  required bool amenitiesDone,
  required bool termsDone,
  required bool hasActiveCourts,
  required VenueStatus? venueStatus,
}) {
  final venueApproved = venueStatus == VenueStatus.approved;
  final reviewNote = switch (venueStatus) {
    VenueStatus.draft => 'ตั้งค่าให้ครบแล้วกด "ส่งตรวจสอบ" ด้านบน',
    VenueStatus.pending => 'รอทีมงานตรวจสอบ',
    VenueStatus.rejected => 'ไม่ผ่านการตรวจสอบ — แก้ข้อมูลแล้วส่งตรวจใหม่',
    VenueStatus.suspended => 'ถูกระงับ — ติดต่อทีมงานเพื่ออุทธรณ์',
    _ => null,
  };
  return [
    VenueSetupStep(
      id: VenueSetupStepId.ownerApproved,
      label: 'เจ้าของสนามได้รับอนุมัติ',
      done: ownerApproved,
      note: ownerApproved
          ? null
          : 'บัญชีเจ้าของของสนามนี้ยังไม่อนุมัติ — ตรวจสอบที่แดชบอร์ด',
    ),
    VenueSetupStep(
      id: VenueSetupStepId.venueCreated,
      label: 'สร้างสนาม',
      done: venueCreated,
      note: venueCreated ? null : 'สร้างสนามจากแดชบอร์ด',
    ),
    VenueSetupStep(
      id: VenueSetupStepId.sports,
      label: 'ตั้งค่ากีฬาของสนาม',
      done: hasSports,
      actionable: venueCreated && !hasSports,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.hours,
      label: 'ตั้งเวลาเปิด–ปิด (ครบ 7 วัน)',
      done: hoursComplete,
      actionable: venueCreated && !hoursComplete,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.amenities,
      label: 'ตั้งสิ่งอำนวยความสะดวก หรือยืนยันว่าไม่มี',
      done: amenitiesDone,
      actionable: venueCreated && !amenitiesDone,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.terms,
      label: 'ใช้เงื่อนไขมาตรฐานหรือเผยแพร่เงื่อนไขของสนาม',
      done: termsDone,
      actionable: venueCreated && !termsDone,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.courts,
      label: 'มีคอร์ทที่เปิดใช้งานอย่างน้อย 1 รายการ',
      done: hasActiveCourts,
      actionable: hasSports && !hasActiveCourts,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.venueApproved,
      label: 'ทีมงานอนุมัติสนาม → เปิดรับการจอง',
      done: venueApproved,
      note: reviewNote,
    ),
  ];
}

/// True when every owner-owned step (1–7) is complete — the venue can be
/// submitted for review. Step 8 (admin approval) is never owner-owned.
bool venueSetupStepsComplete(List<VenueSetupStep> steps) => steps
    .where((s) => s.id != VenueSetupStepId.venueApproved)
    .every((s) => s.done);
