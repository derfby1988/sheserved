import '../data/book_court_models.dart';

/// Step in the owner venue-setup flow (Phase 21.7.11).
///
/// Mirrors the supply checklist from Match_Sport_PLAN.md so the owner can see
/// at a glance what remains before the venue can go live.
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

  const VenueSetupStep({
    required this.id,
    required this.label,
    required this.done,
    this.actionable = false,
  });
}

/// Ordered checklist shown on the owner venue-manage page. Steps a venue can
/// only reach later in the flow stay disabled until their prerequisites are
/// done; the admin-review step is informational (never actionable).
List<VenueSetupStep> computeVenueSetupSteps({
  required bool ownerApproved,
  required bool venueCreated,
  required bool hasSports,
  required bool hasHours,
  required bool hasAmenities,
  required bool hasTerms,
  required bool hasCourts,
  required VenueStatus? venueStatus,
}) {
  final venueApproved = venueStatus == VenueStatus.approved;
  return [
    VenueSetupStep(
      id: VenueSetupStepId.ownerApproved,
      label: 'ลงทะเบียนและได้รับอนุมัติเป็นเจ้าของสนาม',
      done: ownerApproved,
      actionable: !ownerApproved,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.venueCreated,
      label: 'สร้างสนาม',
      done: venueCreated,
      actionable: ownerApproved && !venueCreated,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.sports,
      label: 'ตั้งค่ากีฬาของสนาม',
      done: hasSports,
      actionable: venueCreated && !hasSports,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.hours,
      label: 'ตั้งเวลาเปิด–ปิด',
      done: hasHours,
      actionable: venueCreated && !hasHours,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.amenities,
      label: 'ตั้งสิ่งอำนวยความสะดวก',
      done: hasAmenities,
      actionable: venueCreated && !hasAmenities,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.terms,
      label: 'กำหนดเงื่อนไขการใช้สนาม',
      done: hasTerms,
      actionable: venueCreated && !hasTerms,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.courts,
      label: 'เพิ่มคอร์ท',
      done: hasCourts,
      actionable: hasSports && !hasCourts,
    ),
    VenueSetupStep(
      id: VenueSetupStepId.venueApproved,
      label: 'ทีมงานอนุมัติสนาม → เปิดรับการจอง',
      done: venueApproved,
      actionable: false,
    ),
  ];
}
