import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/venue_terms_editor_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

({String text, int cutoffMinutes})? _result;

Widget _host({String? text, int? cutoff}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          _result = await VenueTermsEditorDialog.show(
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

Finder get _saveButton =>
    find.widgetWithText(GlassActionButton, 'เผยแพร่เวอร์ชันใหม่');

GlassActionButton _save(WidgetTester tester) =>
    tester.widget<GlassActionButton>(_saveButton);

void main() {
  setUp(() => _result = null);

  testWidgets('malformed cutoff disables publish instead of defaulting', (
    tester,
  ) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 60);
    // Terms already filled; corrupt the cutoff field.
    await tester.enterText(find.byType(TextField).at(1), 'abc');
    await tester.pump();
    expect(_save(tester).onTap, isNull);
    expect(find.textContaining('จำนวนเต็ม'), findsOneWidget);
  });

  testWidgets('negative cutoff disables publish', (tester) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 60);
    await tester.enterText(find.byType(TextField).at(1), '-5');
    await tester.pump();
    expect(_save(tester).onTap, isNull);
  });

  testWidgets('empty terms disables publish', (tester) async {
    await _open(tester, text: '', cutoff: 60);
    expect(_save(tester).onTap, isNull);
  });

  testWidgets('valid draft returns parsed cutoff', (tester) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 60);
    await tester.enterText(find.byType(TextField).at(1), '120');
    await tester.pump();
    expect(_save(tester).onTap, isNotNull);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.text, 'กฎของสนาม');
    expect(_result?.cutoffMinutes, 120);
  });

  testWidgets('zero cutoff is a valid explicit value', (tester) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 30);
    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.pump();
    expect(_save(tester).onTap, isNotNull);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.cutoffMinutes, 0);
  });
}
