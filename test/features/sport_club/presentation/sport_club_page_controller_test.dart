import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/presentation/pages/sport_club_page.dart';

void main() {
  group('SportClubPageController.feedTitleFor', () {
    test('returns the sport name only while the filter bar is collapsed', () {
      expect(
        SportClubPageController.feedTitleFor(
          filtersCollapsed: true,
          sportName: 'แบดมินตัน',
        ),
        'แบดมินตัน',
      );
      expect(
        SportClubPageController.feedTitleFor(
          filtersCollapsed: false,
          sportName: 'แบดมินตัน',
        ),
        isNull,
      );
    });

    test('keeps the default title when the "ทั้งหมด" chip is selected', () {
      expect(
        SportClubPageController.feedTitleFor(
          filtersCollapsed: true,
          sportName: null,
        ),
        isNull,
      );
    });
  });

  group('SportClubPageController.feedTitle', () {
    test('starts empty and accepts a new title', () {
      final controller = SportClubPageController();
      addTearDown(controller.dispose);

      expect(controller.feedTitle.value, isNull);

      controller.feedTitle.value = 'เทนนิส';
      expect(controller.feedTitle.value, 'เทนนิส');
    });
  });
}
