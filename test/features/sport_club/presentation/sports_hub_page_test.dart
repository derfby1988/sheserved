import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/pages/book_court_page.dart';
import 'package:sheserved/features/sport_club/find_coach/presentation/pages/find_coach_page.dart';
import 'package:sheserved/features/sport_club/presentation/pages/sports_hub_page.dart';
import 'package:sheserved/features/sport_club/shared/presentation/widgets/sports_hub_page_indicator.dart';

void main() {
  group('SportsHubPager', () {
    testWidgets('starts on Find Buddies and supports horizontal swipes', (
      tester,
    ) async {
      final changedPages = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SportsHubPager(
              bookCourtPage: const Center(child: Text('Book Court content')),
              findBuddiesPage: const Center(
                child: Text('Find Buddies content'),
              ),
              findCoachPage: const Center(child: Text('Find Coach content')),
              onPageChanged: changedPages.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Find Buddies content'), findsOneWidget);
      expect(find.text('หาเพื่อนออกกำลังกาย'), findsOneWidget);
      expect(find.text('Book Court content'), findsNothing);
      expect(find.text('Find Coach content'), findsNothing);

      final pageView = find.byKey(
        const PageStorageKey<String>('sports_hub_page_view'),
      );
      await tester.drag(pageView, const Offset(-520, 0));
      await tester.pumpAndSettle();

      expect(find.text('Find Coach content'), findsOneWidget);
      expect(find.text('หาโค้ช/เทรนเนอร์'), findsOneWidget);

      await tester.drag(pageView, const Offset(520, 0));
      await tester.pumpAndSettle();

      expect(find.text('Find Buddies content'), findsOneWidget);
      await tester.drag(pageView, const Offset(520, 0));
      await tester.pumpAndSettle();

      expect(find.text('Book Court content'), findsOneWidget);
      expect(changedPages, containsAll([2, 1, 0]));
    });

    testWidgets('placeholder pages preserve horizontal PageView swipes', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SportsHubPager(
              bookCourtPage: const BookCourtPage(),
              findBuddiesPage: const Center(
                child: Text('Find Buddies content'),
              ),
              findCoachPage: const FindCoachPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pageView = find.byKey(
        const PageStorageKey<String>('sports_hub_page_view'),
      );
      await tester.drag(pageView, const Offset(-520, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<int>(2)), findsOneWidget);
      expect(
        find.text('พื้นที่สำหรับฟีเจอร์นี้กำลังอยู่ระหว่างการพัฒนา'),
        findsOneWidget,
      );

      await tester.drag(pageView, const Offset(520, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<int>(1)), findsOneWidget);
    });

    testWidgets('selector and arrows change the selected page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SportsHubPager(
              bookCourtPage: const Center(child: Text('Book Court content')),
              findBuddiesPage: const Center(
                child: Text('Find Buddies content'),
              ),
              findCoachPage: const Center(child: Text('Find Coach content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('ไปหน้าโค้ช: หาโค้ช/เทรนเนอร์'));
      await tester.pumpAndSettle();
      expect(find.text('Find Coach content'), findsOneWidget);

      await tester.tap(find.byTooltip('จองสนามกีฬา'));
      await tester.pumpAndSettle();
      expect(find.text('Book Court content'), findsOneWidget);
    });

    testWidgets('dragging the ruler changes the selected page', (tester) async {
      final originalSize = tester.view.physicalSize;
      final originalDevicePixelRatio = tester.view.devicePixelRatio;
      addTearDown(() {
        tester.view.physicalSize = originalSize;
        tester.view.devicePixelRatio = originalDevicePixelRatio;
      });
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SportsHubPager(
              bookCourtPage: const Center(child: Text('Book Court content')),
              findBuddiesPage: const Center(
                child: Text('Find Buddies content'),
              ),
              findCoachPage: const Center(child: Text('Find Coach content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      final ruler = find.bySemanticsLabel('แถบเลื่อนเปลี่ยนหน้า');
      await tester.drag(ruler, const Offset(100, 0));
      await tester.pumpAndSettle();

      expect(find.text('Find Coach content'), findsOneWidget);
      expect(find.text('หาโค้ช/เทรนเนอร์'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('SportsHubPageIndicator', () {
    testWidgets('keeps all page labels available on a narrow screen', (
      tester,
    ) async {
      final originalSize = tester.view.physicalSize;
      final originalDevicePixelRatio = tester.view.devicePixelRatio;
      addTearDown(() {
        tester.view.physicalSize = originalSize;
        tester.view.devicePixelRatio = originalDevicePixelRatio;
      });
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SportsHubPageIndicator(
              currentPage: 1,
              onPageSelected: _ignorePageSelection,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('จองสนามกีฬา'), findsOneWidget);
      expect(find.byTooltip('หาเพื่อนออกกำลังกาย'), findsOneWidget);
      expect(find.byTooltip('หาโค้ช/เทรนเนอร์'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(
        tester.getSize(find.byType(SportsHubPageIndicator)).height,
        lessThanOrEqualTo(100),
      );
      expect(tester.takeException(), isNull);

      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('แถบเลื่อนเปลี่ยนหน้า'), findsOneWidget);
      expect(find.text('หาเพื่อนออกกำลังกาย'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('selector hit targets meet the minimum touch size', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SportsHubPageIndicator(
              currentPage: 1,
              onPageSelected: _ignorePageSelection,
            ),
          ),
        ),
      );

      for (final tooltip in [
        'จองสนามกีฬา',
        'หาเพื่อนออกกำลังกาย',
        'หาโค้ช/เทรนเนอร์',
        'ลากเพื่อเปลี่ยนหน้า',
      ]) {
        final size = tester.getSize(find.byTooltip(tooltip));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });
  });
}

void _ignorePageSelection(int page) {}
