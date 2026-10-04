import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/venue_sports_editor_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

Map<String, dynamic>? _result;

const _sports = [
  {'id': 's1', 'name_th': 'แบดมินตัน', 'name_en': 'Badminton'},
  {'id': 's2', 'name_th': 'ว่ายน้ำ', 'name_en': 'Swimming'},
];

Widget _host({
  Map<String, String> selectedUnits = const {},
  String? reference,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          _result = await VenueSportsEditorDialog.show(
            context,
            sports: _sports,
            selectedUnits: selectedUnits,
            venueUnitSuggestions: const {
              's1': 'ยิม',
              's2': 'สระว่ายน้ำ',
            },
            referenceSportId: reference,
          );
        },
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(
  WidgetTester tester, {
  Map<String, String> selectedUnits = const {'s1': ''},
  String? reference,
}) {
  return tester
      .pumpWidget(_host(selectedUnits: selectedUnits, reference: reference))
      .then((_) => tester.tap(find.text('open')))
      .then((_) => tester.pumpAndSettle());
}

Future<void> _openReferencePicker(WidgetTester tester) async {
  final field = find.byKey(const ValueKey('venue-label-reference'));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
}

Finder get _save => find.byWidgetPredicate(
  (widget) => widget is GlassActionButton && widget.label == 'บันทึก',
);

void main() {
  setUp(() => _result = null);

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('returns the sports list and reference sport together', (
    tester,
  ) async {
    await _open(tester, selectedUnits: {'s1': ''});
    await tester.tap(_save);
    await tester.pumpAndSettle();
    final sports = _result?['sports'] as List;
    expect(sports.single['sport_id'], 's1');
    // Single selected sport auto-fills the reference.
    expect(_result?['referenceSportId'], 's1');
  });

  testWidgets('reference picker lists selected sports with suggestions', (
    tester,
  ) async {
    await _open(tester, selectedUnits: {'s1': '', 's2': ''});
    await _openReferencePicker(tester);
    await tester.tap(find.text('ว่ายน้ำ → สระว่ายน้ำ').last);
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(_result?['referenceSportId'], 's2');
  });

  testWidgets('deselecting the reference sport clears the reference', (
    tester,
  ) async {
    await _open(
      tester,
      selectedUnits: {'s1': '', 's2': ''},
      reference: 's2',
    );
    // Uncheck ว่ายน้ำ — the reference must not point outside the member set.
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'ว่ายน้ำ'),
    );
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(_result?['referenceSportId'], isNull);
    expect((_result?['sports'] as List).single['sport_id'], 's1');
  });

  testWidgets('choosing ไม่เลือก returns a null reference', (tester) async {
    await _open(tester, selectedUnits: {'s1': ''}, reference: 's1');
    await _openReferencePicker(tester);
    await tester.tap(find.text('ไม่เลือก — ใช้คำกลาง "สนาม"').last);
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(_result?['referenceSportId'], isNull);
  });
}
