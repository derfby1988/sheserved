import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sheserved/features/sport_club/shared/application/sports_hub_bar_controller.dart';

void main() {
  group('SportsHubBarController', () {
    test('starts expanded and collapses when the active page scrolls down', () {
      final bar = SportsHubBarController();
      var notified = 0;
      bar.addListener(() => notified++);

      bar.setActivePage(1);
      bar.reportScroll(1, 10);
      expect(bar.isCollapsed, isFalse);

      bar.reportScroll(1, 100);
      expect(bar.isCollapsed, isTrue);
      expect(notified, greaterThan(0));
    });

    test('scrolling an inactive page does not collapse the bar', () {
      final bar = SportsHubBarController()..setActivePage(1);

      bar.reportScroll(0, 500);
      expect(bar.isCollapsed, isFalse);
    });

    test('switching pages restores that page collapse state', () {
      final bar = SportsHubBarController()..setActivePage(1);

      bar.reportScroll(1, 100); // buddies scrolled down -> collapsed
      expect(bar.isCollapsed, isTrue);

      bar.setActivePage(0); // courts at top -> expanded
      expect(bar.isCollapsed, isFalse);

      bar.setActivePage(1); // back to buddies -> collapsed again
      expect(bar.isCollapsed, isTrue);
    });

    test('scrolling back up expands again', () {
      final bar = SportsHubBarController()..setActivePage(1);
      bar.reportScroll(1, 200);
      expect(bar.isCollapsed, isTrue);
      bar.reportScroll(1, 150);
      expect(bar.isCollapsed, isFalse);
    });

    test('expand resets the active page state', () {
      final bar = SportsHubBarController()..setActivePage(2);
      bar.reportScroll(2, 300);
      expect(bar.isCollapsed, isTrue);
      bar.expand();
      expect(bar.isCollapsed, isFalse);
      // The stored per-page state is cleared too.
      bar.setActivePage(0);
      bar.setActivePage(2);
      expect(bar.isCollapsed, isFalse);
    });

    testWidgets('trailing registry renders per-page controls', (
      tester,
    ) async {
      final bar = SportsHubBarController()..setActivePage(0);
      bar.setTrailing(
        2,
        (_) => const Icon(Icons.school, key: Key('coach-trailing')),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: bar,
            builder: (context, _) => Scaffold(
              body: bar.buildTrailing(context, bar.activePage) ??
                  const SizedBox.shrink(),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('coach-trailing')), findsNothing);

      bar.setActivePage(2);
      await tester.pump();
      expect(find.byKey(const Key('coach-trailing')), findsOneWidget);
    });
  });
}
