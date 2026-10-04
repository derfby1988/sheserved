import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/venue_unit_label_editor_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

({String? override, String? referenceSportId})? _result;

Widget _host({
  Map<String, String> sports = const {'s1': 'แบดมินตัน'},
  Map<String, String> suggestions = const {'s1': 'ยิม'},
  String? override,
  String? reference,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          _result = await VenueUnitLabelEditorDialog.show(
            context,
            sports: sports,
            suggestions: suggestions,
            currentOverride: override,
            currentReferenceSportId: reference,
          );
        },
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(
  WidgetTester tester, {
  Map<String, String> sports = const {'s1': 'แบดมินตัน'},
  Map<String, String> suggestions = const {'s1': 'ยิม'},
  String? override,
  String? reference,
}) {
  return tester
      .pumpWidget(
        _host(
          sports: sports,
          suggestions: suggestions,
          override: override,
          reference: reference,
        ),
      )
      .then((_) => tester.tap(find.text('open')))
      .then((_) => tester.pumpAndSettle());
}

Finder get _save => find.byWidgetPredicate(
  (widget) => widget is GlassActionButton && widget.label == 'บันทึก',
);

void main() {
  setUp(() => _result = null);

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('single sport auto-selects it as the reference', (tester) async {
    await _open(tester);
    expect(
      find.textContaining('ตัวอย่างที่ผู้ใช้จะเห็น: "ยิม"'),
      findsOneWidget,
    );
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(_result?.override, isNull);
    expect(_result?.referenceSportId, 's1');
  });

  testWidgets('generic fallback previews and returns a null reference', (
    tester,
  ) async {
    await _open(tester, sports: {'s1': 'แบดมินตัน', 's2': 'เทนนิส'});
    // No current reference + multiple sports -> nothing preselected.
    expect(find.text('ตัวอย่างที่ผู้ใช้จะเห็น: "สนาม"'), findsOneWidget);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(_result?.override, isNull);
    expect(_result?.referenceSportId, isNull);
  });

  testWidgets('reference picker shows the per-sport suggestion', (
    tester,
  ) async {
    await _open(
      tester,
      sports: {'s1': 'แบดมินตัน', 's2': 'ว่ายน้ำ'},
      suggestions: {'s1': 'ยิม', 's2': 'สระว่ายน้ำ'},
    );
    await tester.tap(find.byKey(const ValueKey('venue-label-reference')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ว่ายน้ำ → สระว่ายน้ำ').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('ตัวอย่างที่ผู้ใช้จะเห็น: "สระว่ายน้ำ"'),
      findsOneWidget,
    );
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(_result?.referenceSportId, 's2');
  });

  testWidgets('custom mode validates non-empty and submits the text', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('กำหนดเอง'));
    await tester.pumpAndSettle();
    // Empty custom text disables save.
    expect(tester.widget<GlassActionButton>(_save).onTap, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'ชื่อเรียกสถานที่'),
      'สตูดิโอ',
    );
    await tester.pump();
    expect(
      find.textContaining('ตัวอย่างที่ผู้ใช้จะเห็น: "สตูดิโอ"'),
      findsOneWidget,
    );
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(_result?.override, 'สตูดิโอ');
    // The reference is still returned so the caller can write both fields.
    expect(_result?.referenceSportId, 's1');
  });

  testWidgets('existing override opens in custom mode', (tester) async {
    await _open(tester, override: 'โดม');
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'ชื่อเรียกสถานที่'))
          .controller
          ?.text,
      'โดม',
    );
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(_result?.override, 'โดม');
  });
}
