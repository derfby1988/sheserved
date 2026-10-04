import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/venue_release_editor_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

({bool cleared, int dayOfWeek, String time, int windowDays})? _result;

Widget _host({int? day, String? time, int? window}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          _result = await VenueReleaseEditorDialog.show(
            context,
            currentDayOfWeek: day,
            currentTime: time,
            currentWindowDays: window,
          );
        },
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(
  WidgetTester tester, {
  int? day,
  String? time,
  int? window,
}) {
  return tester
      .pumpWidget(_host(day: day, time: time, window: window))
      .then((_) => tester.tap(find.text('open')))
      .then((_) => tester.pumpAndSettle());
}

Finder get _saveButton => find.byWidgetPredicate(
  (widget) =>
      widget is GlassActionButton &&
      (widget.label == 'บันทึกรอบเปิดจอง' || widget.label == 'ปิดการจำกัด'),
);

GlassActionButton _save(WidgetTester tester) =>
    tester.widget<GlassActionButton>(_saveButton);

void main() {
  setUp(() => _result = null);

  testWidgets('empty state submits cleared: true (unlimited advance)', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.cleared, isTrue);
  });

  testWidgets('enabling the rule submits the weekly triple', (tester) async {
    await _open(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'จำกัดการจองล่วงหน้า'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '14'));
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.cleared, isFalse);
    expect(_result?.dayOfWeek, 1);
    expect(_result?.time, '09:00');
    expect(_result?.windowDays, 14);
  });

  testWidgets('prefills the current rule', (tester) async {
    await _open(tester, day: 5, time: '10:30', window: 30);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'จำกัดการจองล่วงหน้า'),
          )
          .value,
      isTrue,
    );
    expect(find.text('เวลา 10:30'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'กำหนดเอง (วัน)'),
          )
          .controller
          ?.text,
      '30',
    );
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.dayOfWeek, 5);
    expect(_result?.windowDays, 30);
  });

  testWidgets('custom window below 7 days disables save', (tester) async {
    await _open(tester, day: 1, time: '09:00', window: 7);
    await tester.enterText(
      find.widgetWithText(TextField, 'กำหนดเอง (วัน)'),
      '3',
    );
    await tester.pump();
    expect(find.text('อย่างน้อย 7 วัน'), findsOneWidget);
    expect(_save(tester).onTap, isNull);
  });
}
