import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';

void main() {
  group('21.7.19 two-level unit labels', () {
    test('VenueSummary parses the resolved venue unit label', () {
      final venue = VenueSummary.fromJson({
        'id': 'v1',
        'name': 'Gym One',
        'venue_unit_label': 'ยิม',
      });
      expect(venue.venueUnitLabel, 'ยิม');

      // The camelCase key used by RPC JSON payloads parses too.
      final fromRpc = VenueSummary.fromJson({
        'id': 'v1',
        'name': 'Gym One',
        'venueUnitLabel': 'สตูดิโอ',
      });
      expect(fromRpc.venueUnitLabel, 'สตูดิโอ');

      final legacy = VenueSummary.fromJson({'id': 'v1', 'name': 'Gym One'});
      expect(legacy.venueUnitLabel, isNull);
    });

    test('VenueCourt keeps resolved label and raw override separate', () {
      final court = VenueCourt.fromJson({
        'id': 'c1',
        'venue_id': 'v1',
        'sport_id': 's1',
        'name': 'Table 1',
        'unit_label': 'โต๊ะ', // resolved, live from the helper
        'unit_label_override': 'โต๊ะ', // raw owner-typed override
      });
      expect(court.unitLabel, 'โต๊ะ');
      expect(court.unitLabelOverride, 'โต๊ะ');

      final inherited = VenueCourt.fromJson({
        'id': 'c2',
        'venue_id': 'v1',
        'sport_id': 's1',
        'name': 'Court 1',
        'unit_label': 'คอร์ท',
        'unit_label_override': null,
      });
      expect(inherited.unitLabel, 'คอร์ท');
      expect(inherited.unitLabelOverride, isNull);
    });

    test('VenueBooking exposes the venue label snapshot', () {
      final booking = VenueBooking.fromJson({
        'id': 'b1',
        'court_id': 'c1',
        'venue_id': 'v1',
        'sport_id': 's1',
        'starts_at': '2026-10-10T10:00:00Z',
        'ends_at': '2026-10-10T11:00:00Z',
        'status': 'confirmed',
        'unitLabel': 'คอร์ท',
        'venueUnitLabel': 'ยิม',
      });
      expect(booking.unitLabel, 'คอร์ท');
      expect(booking.venueUnitLabel, 'ยิม');
    });

    test('legacy bookings without a venue snapshot parse as null', () {
      final booking = VenueBooking.fromJson({
        'id': 'b1',
        'court_id': 'c1',
        'venue_id': 'v1',
        'sport_id': 's1',
        'starts_at': '2026-10-10T10:00:00Z',
        'ends_at': '2026-10-10T11:00:00Z',
        'status': 'confirmed',
        'unit_label': 'คอร์ท',
      });
      expect(booking.unitLabel, 'คอร์ท');
      expect(booking.venueUnitLabel, isNull);
    });
  });
}
