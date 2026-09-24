import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/domain/book_court_filter.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/book_court_filter_sheet.dart';

void main() {
  testWidgets('edits the shared venue query in the filter sheet', (
    tester,
  ) async {
    const currentFilter = BookCourtFilter(minPrice: 100.0);
    BookCourtFilterSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await BookCourtFilterSheet.show(
                    context,
                    current: currentFilter,
                    currentQuery: 'Old court',
                  );
                },
                child: const Text('เปิดตัวกรอง'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดตัวกรอง'));
    await tester.pumpAndSettle();

    final queryField = find.byKey(const ValueKey('book_court_search_query'));
    expect(tester.widget<TextField>(queryField).controller?.text, 'Old court');

    await tester.enterText(queryField, '  New court  ');
    await tester.ensureVisible(find.text('ใช้ตัวกรอง'));
    await tester.tap(find.text('ใช้ตัวกรอง'));
    await tester.pumpAndSettle();

    expect(result?.query, 'New court');
    expect(result?.filter.minPrice, 100.0);
  });

  testWidgets('close button dismisses without applying changes', (
    tester,
  ) async {
    BookCourtFilterSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await BookCourtFilterSheet.show(
                    context,
                    current: const BookCourtFilter(),
                    currentQuery: 'Current query',
                  );
                },
                child: const Text('เปิดตัวกรอง'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดตัวกรอง'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();

    expect(find.text('ตัวกรองสนาม'), findsNothing);
    expect(result, isNull);
  });
}
