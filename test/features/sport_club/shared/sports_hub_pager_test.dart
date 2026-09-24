import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sheserved/features/sport_club/presentation/pages/sports_hub_page.dart';

Widget _page(String label) => Scaffold(body: Center(child: Text(label)));

void main() {
  group('SportsHubPager', () {
    testWidgets('defaults to Find Buddies at index 1', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SportsHubPager(
            bookCourtPage: _page('courts'),
            findBuddiesPage: _page('buddies'),
            findCoachPage: _page('coaches'),
          ),
        ),
      );

      expect(find.text('buddies'), findsOneWidget);
      expect(find.text('courts'), findsNothing);
      expect(find.text('coaches'), findsNothing);
    });

    testWidgets('honours a non-default initial page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SportsHubPager(
            initialPage: 0,
            bookCourtPage: _page('courts'),
            findBuddiesPage: _page('buddies'),
            findCoachPage: _page('coaches'),
          ),
        ),
      );

      expect(find.text('courts'), findsOneWidget);
      expect(find.text('buddies'), findsNothing);
    });

    testWidgets('clamps an out-of-range initial page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SportsHubPager(
            initialPage: 9,
            bookCourtPage: _page('courts'),
            findBuddiesPage: _page('buddies'),
            findCoachPage: _page('coaches'),
          ),
        ),
      );

      expect(find.text('coaches'), findsOneWidget);
    });

    testWidgets('reports page changes through the callback', (tester) async {
      var lastPage = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: SportsHubPager(
            bookCourtPage: _page('courts'),
            findBuddiesPage: _page('buddies'),
            findCoachPage: _page('coaches'),
            onPageChanged: (page) => lastPage = page,
          ),
        ),
      );

      await tester.drag(find.byType(PageView), const Offset(-800, 0));
      await tester.pumpAndSettle();
      expect(lastPage, 2);
      expect(find.text('coaches'), findsOneWidget);
    });
  });
}
