import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_review_sheet.dart';

const _categories = [
  VenueReviewCategory(
    id: 'cat-surface',
    key: 'surface',
    labelTh: 'สภาพพื้น/คุณภาพสนาม',
  ),
  VenueReviewCategory(
    id: 'cat-equipment',
    key: 'equipment',
    labelTh: 'อุปกรณ์และสิ่งอำนวยความสะดวก',
  ),
  VenueReviewCategory(
    id: 'cat-location',
    key: 'location',
    labelTh: 'ทำเล/การเดินทาง',
  ),
  VenueReviewCategory(id: 'cat-service', key: 'service', labelTh: 'การบริการ'),
  VenueReviewCategory(id: 'cat-value', key: 'value', labelTh: 'ความคุ้มค่า'),
];

const _tags = [
  VenueReviewTag(id: 'tag-1', labelTh: 'สะอาด/ดูแลดี'),
  VenueReviewTag(id: 'tag-2', labelTh: 'คุ้มค่าราคา'),
];

Widget _harness({required void Function(CourtReviewDraft?) onDone}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              onDone(
                await CourtReviewSheet.show(
                  context,
                  venueName: 'สนามทดสอบ',
                  tagCatalog: _tags,
                  categories: _categories,
                ),
              );
            },
            child: const Text('เปิดรีวิว'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('เปิดรีวิว'));
  await tester.pumpAndSettle();
}

Future<void> _tapChip(WidgetTester tester, String key) async {
  final chip = find.byKey(ValueKey(key));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

void main() {
  testWidgets('submit stays disabled until overall and every category '
      'score are chosen', (tester) async {
    await tester.pumpWidget(_harness(onDone: (_) {}));
    await _openSheet(tester);

    FilledButton submit() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'ส่งรีวิว'),
    );

    expect(submit().onPressed, isNull);

    await _tapChip(tester, 'overall-score-8');
    // Overall alone is not enough: all five categories are mandatory.
    expect(submit().onPressed, isNull);

    for (final c in _categories) {
      await _tapChip(tester, 'category-${c.key}-9');
    }
    await tester.pumpAndSettle();

    expect(submit().onPressed, isNotNull);
  });

  testWidgets('returns rating10 + per-category scores + comment + tags', (
    tester,
  ) async {
    CourtReviewDraft? draft;
    await tester.pumpWidget(_harness(onDone: (d) => draft = d));
    await _openSheet(tester);

    await _tapChip(tester, 'overall-score-8');
    for (final c in _categories) {
      await _tapChip(tester, 'category-${c.key}-7');
    }

    await tester.enterText(
      find.byType(TextField).first,
      'สนามสะอาดดี',
    );
    await tester.ensureVisible(find.text('สะอาด/ดูแลดี'));
    await tester.tap(find.text('สะอาด/ดูแลดี'));
    await tester.pump();

    await tester.ensureVisible(find.text('ส่งรีวิว'));
    await tester.tap(find.text('ส่งรีวิว'));
    await tester.pumpAndSettle();

    expect(draft, isNotNull);
    expect(draft!.rating10, 8);
    expect(draft!.categoryScores.length, 5);
    expect(draft!.categoryScores['cat-surface'], 7);
    expect(draft!.comment, 'สนามสะอาดดี');
    expect(draft!.tagIds, {'tag-1'});
  });
}
