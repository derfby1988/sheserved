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

Finder get _cutoffSlider => find.descendant(
  of: find.byKey(const ValueKey('venue-terms-cutoff')),
  matching: find.byType(Slider),
);

/// Drive the preset slider by option index (0 = first preset).
void _selectCutoff(WidgetTester tester, int index) {
  tester.widget<Slider>(_cutoffSlider).onChanged!(index.toDouble());
}

void main() {
  setUp(() => _result = null);

  testWidgets('preset slider replaces the free-text cutoff field', (
    tester,
  ) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 60);
    expect(_cutoffSlider, findsOneWidget);
    expect(find.text('1 ชม.'), findsOneWidget);
    expect(find.text('ไม่จำกัด'), findsNothing);
  });

  testWidgets('defaults to 60 minutes when no version is published', (
    tester,
  ) async {
    await _open(tester, text: 'กฎของสนาม');
    expect(find.text('1 ชม.'), findsOneWidget);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.cutoffMinutes, 60);
  });

  testWidgets('selecting a preset publishes that cutoff', (tester) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 60);
    _selectCutoff(tester, 2);
    await tester.pump();
    expect(find.text('30 นาที'), findsOneWidget);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.cutoffMinutes, 30);
  });

  testWidgets('zero is selectable and means no advance cutoff', (tester) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 30);
    _selectCutoff(tester, 0);
    await tester.pump();
    expect(find.text('ไม่จำกัด'), findsOneWidget);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.cutoffMinutes, 0);
  });

  testWidgets('the last preset is 36 hours', (tester) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 60);
    final slider = tester.widget<Slider>(_cutoffSlider);
    _selectCutoff(tester, slider.max.round());
    await tester.pump();
    expect(find.text('36 ชม.'), findsOneWidget);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.cutoffMinutes, 2160);
  });

  testWidgets('a published cutoff outside the presets is preserved', (
    tester,
  ) async {
    await _open(tester, text: 'กฎของสนาม', cutoff: 2000);
    expect(find.text('2000 นาที'), findsOneWidget);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.cutoffMinutes, 2000);
  });

  testWidgets('empty terms disables publish', (tester) async {
    await _open(tester, text: '', cutoff: 60);
    expect(_save(tester).onTap, isNull);
  });
}
