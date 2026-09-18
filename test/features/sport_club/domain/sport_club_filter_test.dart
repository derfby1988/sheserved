import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/domain/sport_club_filter.dart';

void main() {
  group('SportClubFilter', () {
    test('uses defaults', () {
      const filter = SportClubFilter();

      expect(filter.sportId, isNull);
      expect(filter.q, '');
      expect(filter.province, isNull);
      expect(filter.district, isNull);
      expect(filter.openOnly, isFalse);
      expect(filter.joinedOnly, isFalse);
      expect(filter.managedOnly, isFalse);
      expect(filter.locationEnabled, isFalse);
      expect(filter.radiusKm, SportClubFilter.defaultRadiusKm);
      expect(filter.activeCount, 0);
      expect(filter.summary, 'ตัวกรอง');
    });

    test('copyWith updates values and clears nullable fields', () {
      const filter = SportClubFilter(
        sportId: 'sport-1',
        q: 'court',
        province: 'กรุงเทพมหานคร',
        district: 'จตุจักร',
        openOnly: true,
        joinedOnly: true,
        managedOnly: true,
        locationEnabled: true,
        radiusKm: 20,
      );

      final updated = filter.copyWith(
        sportId: 'sport-2',
        q: 'badminton',
        openOnly: false,
        radiusKm: 15,
      );

      expect(updated.sportId, 'sport-2');
      expect(updated.q, 'badminton');
      expect(updated.openOnly, isFalse);
      expect(updated.radiusKm, 15);
      expect(updated.joinedOnly, isTrue);
      expect(updated.managedOnly, isTrue);
      expect(updated.locationEnabled, isTrue);

      final cleared = updated.copyWith(
        clearSportId: true,
        clearProvince: true,
        clearDistrict: true,
      );
      expect(cleared.sportId, isNull);
      expect(cleared.province, isNull);
      expect(cleared.district, isNull);
    });

    test('activeCount and summary reflect all persisted filters', () {
      const filter = SportClubFilter(
        q: 'court',
        province: 'กรุงเทพมหานคร',
        district: 'จตุจักร',
        openOnly: true,
        joinedOnly: true,
        managedOnly: true,
        locationEnabled: true,
      );

      expect(filter.activeCount, 7);
      expect(filter.summary, 'ตัวกรอง (7)');
    });

    test('toggleQuickFilter flips only matching filter', () {
      const filter = SportClubFilter();

      expect(filter.toggleQuickFilter('open').openOnly, isTrue);
      expect(filter.toggleQuickFilter('joined').joinedOnly, isTrue);
      expect(filter.toggleQuickFilter('managed').managedOnly, isTrue);
      expect(filter.toggleQuickFilter('radius'), same(filter));
    });

    test('clearAll clears counted filters but preserves sport and radius', () {
      const filter = SportClubFilter(
        sportId: 'sport-1',
        q: 'court',
        province: 'กรุงเทพมหานคร',
        district: 'จตุจักร',
        openOnly: true,
        joinedOnly: true,
        managedOnly: true,
        locationEnabled: true,
        radiusKm: 50,
      );

      final cleared = filter.clearAll();

      expect(cleared.sportId, 'sport-1');
      expect(cleared.radiusKm, 50);
      expect(cleared.q, '');
      expect(cleared.province, isNull);
      expect(cleared.district, isNull);
      expect(cleared.openOnly, isFalse);
      expect(cleared.joinedOnly, isFalse);
      expect(cleared.managedOnly, isFalse);
      expect(cleared.locationEnabled, isFalse);
      expect(cleared.activeCount, 0);
    });

    test('json round trip preserves values', () {
      const filter = SportClubFilter(
        sportId: 'sport-1',
        q: 'court',
        province: 'กรุงเทพมหานคร',
        district: 'จตุจักร',
        openOnly: true,
        joinedOnly: true,
        managedOnly: true,
        locationEnabled: true,
        radiusKm: 25,
      );

      final restored = SportClubFilter.fromJson(filter.toJson());
      expect(restored, filter);
    });

    test('fromJson falls back to defaults for missing values', () {
      final filter = SportClubFilter.fromJson(const {});

      expect(filter, const SportClubFilter());
    });
  });
}
