import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/application/feed_filter_collapse_controller.dart';

void main() {
  group('FeedFilterCollapseController', () {
    test('stays expanded while scrolling within the threshold', () {
      final controller = FeedFilterCollapseController(collapseThreshold: 56);

      expect(controller.update(10), isFalse);
      expect(controller.update(40), isFalse);
      expect(controller.update(56), isFalse);
      expect(controller.isCollapsed, isFalse);
    });

    test('collapses after scrolling down past the threshold', () {
      final controller = FeedFilterCollapseController(collapseThreshold: 56);

      expect(controller.update(30), isFalse);
      expect(controller.update(80), isTrue);
      expect(controller.isCollapsed, isTrue);
    });

    test('stays collapsed while continuing to scroll down', () {
      final controller = FeedFilterCollapseController(collapseThreshold: 56);

      controller.update(100);
      expect(controller.update(150), isFalse);
      expect(controller.isCollapsed, isTrue);
    });

    test('expands on any upward scroll of the content', () {
      final controller = FeedFilterCollapseController(collapseThreshold: 56);

      controller.update(120);
      expect(controller.isCollapsed, isTrue);

      expect(controller.update(119), isFalse);
      expect(controller.isCollapsed, isTrue);

      expect(controller.update(110), isTrue);
      expect(controller.isCollapsed, isFalse);
    });

    test('stays collapsed while the offset is unchanged', () {
      final controller = FeedFilterCollapseController(collapseThreshold: 56);

      controller.update(120);
      expect(controller.update(120), isFalse);
      expect(controller.isCollapsed, isTrue);
    });

    test('expand restores the filters immediately', () {
      final controller = FeedFilterCollapseController(collapseThreshold: 56);

      controller.update(120);
      controller.expand();

      expect(controller.isCollapsed, isFalse);
    });

    test(
      'does not report a change while already collapsed at the same offset',
      () {
        final controller = FeedFilterCollapseController(collapseThreshold: 56);

        controller.update(100);
        expect(controller.update(100), isFalse);
        expect(controller.isCollapsed, isTrue);
      },
    );
  });
}
