import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/domain/venue_setup_progress.dart';

List<VenueSetupStep> _steps({
  bool ownerApproved = true,
  bool venueCreated = true,
  bool hasSports = false,
  bool hoursComplete = false,
  bool amenitiesDone = false,
  bool termsDone = false,
  bool hasActiveCourts = false,
  VenueStatus? venueStatus = VenueStatus.draft,
}) => computeVenueSetupSteps(
  ownerApproved: ownerApproved,
  venueCreated: venueCreated,
  hasSports: hasSports,
  hoursComplete: hoursComplete,
  amenitiesDone: amenitiesDone,
  termsDone: termsDone,
  hasActiveCourts: hasActiveCourts,
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

    test('steps 1-2 are read-only and never actionable on this page', () {
      final steps = _steps(ownerApproved: false, venueCreated: false);
      expect(_step(steps, VenueSetupStepId.ownerApproved).actionable, isFalse);
      expect(_step(steps, VenueSetupStepId.venueCreated).actionable, isFalse);
      // and explain instead of showing a tap affordance
      expect(_step(steps, VenueSetupStepId.ownerApproved).note, isNotNull);
      expect(_step(steps, VenueSetupStepId.venueCreated).note, isNotNull);
    });

    test('optional steps done by explicit confirmation, not by empty rows', () {
      // amenitiesDone/termsDone reflect the persisted confirmations
      // ("ยืนยันว่าไม่มี", platform base terms) — not the presence of rows.
      final steps = _steps(amenitiesDone: true, termsDone: true);
      expect(_step(steps, VenueSetupStepId.amenities).done, isTrue);
      expect(_step(steps, VenueSetupStepId.terms).done, isTrue);
    });

    test('partial hours do not complete the hours step', () {
      // hoursComplete is only true when all 7 days are specified upstream.
      final steps = _steps();
      expect(_step(steps, VenueSetupStepId.hours).done, isFalse);
      final done = _steps(hoursComplete: true);
      expect(_step(done, VenueSetupStepId.hours).done, isTrue);
    });

    test('inactive-only courts do not complete the courts step', () {
      final steps = _steps(hasSports: true);
      expect(_step(steps, VenueSetupStepId.courts).done, isFalse);
      final withActive = _steps(hasSports: true, hasActiveCourts: true);
      expect(_step(withActive, VenueSetupStepId.courts).done, isTrue);
    });

    group('venueApproved step reports the real review status', () {
      for (final status in VenueStatus.values) {
        test('$status', () {
          final steps = _steps(venueStatus: status);
          final step = _step(steps, VenueSetupStepId.venueApproved);
          expect(step.actionable, isFalse);
          expect(step.done, status == VenueStatus.approved);
          if (status == VenueStatus.approved) {
            expect(step.note, isNull);
          } else {
            expect(step.note, isNotNull);
          }
        });
      }

      test('draft invites submission; pending waits; rejected resubmits', () {
        expect(
          _step(
            _steps(venueStatus: VenueStatus.draft),
            VenueSetupStepId.venueApproved,
          ).note,
          contains('ส่งตรวจสอบ'),
        );
        expect(
          _step(
            _steps(venueStatus: VenueStatus.pending),
            VenueSetupStepId.venueApproved,
          ).note,
          contains('รอทีมงาน'),
        );
        expect(
          _step(
            _steps(venueStatus: VenueStatus.rejected),
            VenueSetupStepId.venueApproved,
          ).note,
          contains('ส่งตรวจใหม่'),
        );
        expect(
          _step(
            _steps(venueStatus: VenueStatus.suspended),
            VenueSetupStepId.venueApproved,
          ).note,
          contains('อุทธรณ์'),
        );
      });
    });

    test('fully configured approved venue completes the checklist', () {
      final steps = _steps(
        hasSports: true,
        hoursComplete: true,
        amenitiesDone: true,
        termsDone: true,
        hasActiveCourts: true,
        venueStatus: VenueStatus.approved,
      );
      expect(steps.every((s) => s.done), isTrue);
      expect(steps.where((s) => s.actionable).isEmpty, isTrue);
      expect(venueSetupStepsComplete(steps), isTrue);
    });
  });

  group('venueSetupStepsComplete', () {
    test('true when owner-owned steps done even before admin approval', () {
      final steps = _steps(
        hasSports: true,
        hoursComplete: true,
        amenitiesDone: true,
        termsDone: true,
        hasActiveCourts: true,
        venueStatus: VenueStatus.draft,
      );
      expect(venueSetupStepsComplete(steps), isTrue);
    });

    test('false when any required step is missing', () {
      expect(
        venueSetupStepsComplete(
          _steps(
            hasSports: true,
            hoursComplete: true,
            amenitiesDone: true,
            termsDone: true,
            // no active courts
          ),
        ),
        isFalse,
      );
      expect(
        venueSetupStepsComplete(
          _steps(
            hasSports: true,
            hoursComplete: true,
            amenitiesDone: true,
            termsDone: true,
            hasActiveCourts: true,
            ownerApproved: false,
          ),
        ),
        isFalse,
      );
    });
  });
}
