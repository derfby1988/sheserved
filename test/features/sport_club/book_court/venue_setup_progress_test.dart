import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/domain/venue_setup_progress.dart';

List<VenueSetupStep> _steps({
  bool ownerApproved = true,
  bool venueCreated = true,
  bool hasSports = false,
  bool hasHours = false,
  bool hasAmenities = false,
  bool hasTerms = false,
  bool hasCourts = false,
  VenueStatus? venueStatus = VenueStatus.pending,
}) => computeVenueSetupSteps(
  ownerApproved: ownerApproved,
  venueCreated: venueCreated,
  hasSports: hasSports,
  hasHours: hasHours,
  hasAmenities: hasAmenities,
  hasTerms: hasTerms,
  hasCourts: hasCourts,
  venueStatus: venueStatus,
);

VenueSetupStep _step(List<VenueSetupStep> steps, VenueSetupStepId id) =>
    steps.firstWhere((s) => s.id == id);

void main() {
  group('computeVenueSetupSteps', () {
    test('returns all 8 flow steps in order', () {
      final steps = _steps();
      expect(steps.length, 8);
      expect(steps.first.id, VenueSetupStepId.ownerApproved);
      expect(steps.last.id, VenueSetupStepId.venueApproved);
    });

    test('freshly created venue: sports/hours/amenities/terms actionable, '
        'courts blocked until a sport is set', () {
      final steps = _steps();
      for (final id in [
        VenueSetupStepId.sports,
        VenueSetupStepId.hours,
        VenueSetupStepId.amenities,
        VenueSetupStepId.terms,
      ]) {
        expect(_step(steps, id).actionable, isTrue, reason: '$id');
      }
      expect(_step(steps, VenueSetupStepId.courts).actionable, isFalse);
    });

    test('court step unlocks only after a venue sport exists', () {
      final steps = _steps(hasSports: true);
      expect(_step(steps, VenueSetupStepId.courts).actionable, isTrue);
      expect(_step(steps, VenueSetupStepId.courts).done, isFalse);
    });

    test(
      'admin review step is done for approved venue and never actionable',
      () {
        final pending = _steps();
        expect(_step(pending, VenueSetupStepId.venueApproved).done, isFalse);
        expect(
          _step(pending, VenueSetupStepId.venueApproved).actionable,
          isFalse,
        );

        final approved = _steps(venueStatus: VenueStatus.approved);
        expect(_step(approved, VenueSetupStepId.venueApproved).done, isTrue);
        expect(
          _step(approved, VenueSetupStepId.venueApproved).actionable,
          isFalse,
        );
      },
    );

    test('fully configured approved venue completes the checklist', () {
      final steps = _steps(
        hasSports: true,
        hasHours: true,
        hasAmenities: true,
        hasTerms: true,
        hasCourts: true,
        venueStatus: VenueStatus.approved,
      );
      expect(steps.every((s) => s.done), isTrue);
      expect(steps.where((s) => s.actionable).isEmpty, isTrue);
    });

    test('owner not yet approved blocks venue creation and setup steps', () {
      final steps = _steps(ownerApproved: false, venueCreated: false);
      expect(_step(steps, VenueSetupStepId.ownerApproved).actionable, isTrue);
      expect(_step(steps, VenueSetupStepId.venueCreated).actionable, isFalse);
      expect(_step(steps, VenueSetupStepId.sports).actionable, isFalse);
    });
  });
}
