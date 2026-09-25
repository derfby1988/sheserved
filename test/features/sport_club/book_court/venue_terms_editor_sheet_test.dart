import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/venue_terms_editor_sheet.dart';

({String text, int cutoffMinutes})? _result;

Widget _host({String? text, int? cutoff}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          _result = await VenueTermsEditorSheet.show(
            context,
            currentText: text,
            currentCutoffMinutes: cutoff,
          );
        },
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, {String? text, int? cutoff}) {
  return tester
      .pumpWidget(_host(text: text, cutoff: cutoff))
      .then((_) => tester.tap(find.text('open')))
      .then((_) => tester.pumpAndSettle());
}

FilledButton _save(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  setUp(() => _result = null);

  testWidgets('malformed cutoff disables publish instead of defaulting', (
    tester,
  ) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 60);
    // Terms already filled; corrupt the cutoff field.
    await tester.enterText(find.byType(TextField).at(1), 'abc');
    await tester.pump();
    expect(_save(tester).onPressed, isNull);
    expect(find.textContaining('จำนวนเต็ม'), findsOneWidget);
  });

  testWidgets('negative cutoff disables publish', (tester) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 60);
    await tester.enterText(find.byType(TextField).at(1), '-5');
    await tester.pump();
    expect(_save(tester).onPressed, isNull);
  });

  testWidgets('empty terms disables publish', (tester) async {
    await _open(tester, text: '', cutoff: 60);
    expect(_save(tester).onPressed, isNull);
  });

  testWidgets('valid draft returns parsed cutoff', (tester) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 60);
    await tester.enterText(find.byType(TextField).at(1), '120');
    await tester.pump();
    expect(_save(tester).onPressed, isNotNull);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(_result?.text, 'กฎของสนาม');
    expect(_result?.cutoffMinutes, 120);
  });

  testWidgets('zero cutoff is a valid explicit value', (tester) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 30);
    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.pump();
    expect(_save(tester).onPressed, isNotNull);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(_result?.cutoffMinutes, 0);
  });
}
