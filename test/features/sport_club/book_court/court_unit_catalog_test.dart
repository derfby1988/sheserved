import 'package:flutter_test/flutter_test.dart';

import 'package:sheserved/features/sport_club/book_court/domain/court_unit_catalog.dart';

void main() {
  group('CourtUnitCatalog.resolve', () {
    test('court label wins over overrides and catalog defaults', () {
      expect(
        CourtUnitCatalog.resolve(
          courtLabel: 'คอร์ท VIP',
          overrideLabel: 'คอร์ท',
          catalogDefault: 'สนาม',
        ),
        'คอร์ท VIP',
      );
    });

    test('venue+sport override wins over catalog default', () {
      expect(
        CourtUnitCatalog.resolve(overrideLabel: 'โต๊ะ', catalogDefault: 'สนาม'),
        'โต๊ะ',
      );
    });

    test('falls back to the catalog default', () {
      expect(CourtUnitCatalog.resolve(catalogDefault: 'สนาม'), 'สนาม');
    });

    test('falls back to the generic label when everything is empty', () {
      expect(CourtUnitCatalog.resolve(), 'สนาม');
      expect(
        CourtUnitCatalog.resolve(courtLabel: '  ', overrideLabel: ''),
        'สนาม',
      );
    });
  });
}
