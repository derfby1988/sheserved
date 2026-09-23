import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/feed/sport_club_filter_button.dart';

void main() {
  group('SportClubFilterButton', () {
    testWidgets('shows the active filter badge and reports taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SportClubFilterButton(
              activeFilterCount: 3,
              filterSummary: 'ตัวกรอง 3 รายการ',
              onTap: () => taps++,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('เปิดตัวกรองทั้งหมด')),
        findsOneWidget,
      );
      semantics.dispose();

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('hides the badge when no filter is active', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SportClubFilterButton(
              activeFilterCount: 0,
              filterSummary: 'ไม่มีตัวกรอง',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('0'), findsNothing);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    });
  });
}
