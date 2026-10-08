import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/feed/filter_collapse_box.dart';

int taps = 0;

void main() {
  Widget host({required bool collapsed, required bool collapseHeight}) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            FilterCollapseBox(
              collapsed: collapsed,
              collapseHeight: collapseHeight,
              child: SizedBox(
                height: 44,
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('ตัวกรอง'),
                ),
              ),
            ),
            const Text('list'),
          ],
        ),
      ),
    );
  }

  testWidgets('expanded: keeps its height and stays tappable', (tester) async {
    taps = 0;
    await tester.pumpWidget(host(collapsed: false, collapseHeight: true));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(FilterCollapseBox)).height, 44);
    await tester.tap(find.text('ตัวกรอง'));
    expect(taps, 1);
  });

  testWidgets('collapsed: height collapses and taps are ignored', (
    tester,
  ) async {
    taps = 0;
    await tester.pumpWidget(host(collapsed: true, collapseHeight: true));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(FilterCollapseBox)).height, 0);
    // The child stays mounted (only hidden), so the finder still resolves.
    expect(find.text('ตัวกรอง'), findsOneWidget);
    await tester.tap(find.text('ตัวกรอง'), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('collapsed without collapseHeight: keeps the layout height', (
    tester,
  ) async {
    taps = 0;
    await tester.pumpWidget(host(collapsed: true, collapseHeight: false));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(FilterCollapseBox)).height, 44);
    await tester.tap(find.text('ตัวกรอง'), warnIfMissed: false);
    expect(taps, 0);
  });
}
