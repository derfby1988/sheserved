import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/venue_release_editor_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

({bool cleared, List<int> daysOfWeek, String time, int windowDays})? _result;

Widget _host({List<int>? days, int? day, String? time, int? window}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              _result = await VenueReleaseEditorDialog.show(
                context,
                currentDaysOfWeek: days,
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
  List<int>? days,
  int? day,
  String? time,
  int? window,
}) {
  return tester
      .pumpWidget(_host(days: days, day: day, time: time, window: window))
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
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'จำกัดการจองล่วงหน้า'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '14'));
    await tester.tap(find.widgetWithText(ChoiceChip, '14'));
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.cleared, isFalse);
    expect(_result?.daysOfWeek, [1]);
    expect(_result?.time, '09:00');
    expect(_result?.windowDays, 14);
  });

  testWidgets('offers a one-tap every-day schedule', (tester) async {
    await _open(tester, day: 1, time: '09:00', window: 7);
    expect(
      find.byKey(const ValueKey('venue-release-all-days')),
      findsOneWidget,
    );
  });

  testWidgets(
    'every-day selection shares one time and permits a one-day window',
    (tester) async {
      await _open(tester, day: 1, time: '09:00', window: 7);
      await tester.tap(find.byKey(const ValueKey('venue-release-all-days')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'จำนวนวันล่วงหน้า'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'จำนวนวันล่วงหน้า'),
        '1',
      );
      await tester.pump();
      expect(find.text('รอบ: ทุกวัน เวลา 09:00'), findsOneWidget);
      expect(_save(tester).onTap, isNotNull);
      await tester.ensureVisible(_saveButton);
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(_result?.daysOfWeek, [0, 1, 2, 3, 4, 5, 6]);
      expect(_result?.windowDays, 1);
    },
  );

  testWidgets('supports multiple selected weekdays with one shared time', (
    tester,
  ) async {
    await _open(tester, days: [1], time: '09:00', window: 7);
    await tester.ensureVisible(
      find.byKey(const ValueKey('venue-release-day-3')),
    );
    await tester.tap(find.byKey(const ValueKey('venue-release-day-3')));
    await tester.pumpAndSettle();
    expect(
      find.text('รอบ: ทุกสัปดาห์ วันจันทร์ และวันพุธ เวลา 09:00'),
      findsOneWidget,
    );
    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.daysOfWeek, [1, 3]);
    expect(_result?.time, '09:00');
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
    expect(find.text('เวลาเดียวกันทุกวันที่เลือก · 10:30'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'จำนวนวันล่วงหน้า'))
          .controller
          ?.text,
      '30',
    );
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?.daysOfWeek, [5]);
    expect(_result?.windowDays, 30);
  });

  testWidgets('custom window below 7 days disables save', (tester) async {
    await _open(tester, day: 1, time: '09:00', window: 7);
    await tester.enterText(
      find.widgetWithText(TextField, 'จำนวนวันล่วงหน้า'),
      '3',
    );
    await tester.pump();
    expect(find.text('อย่างน้อย 7 วัน'), findsOneWidget);
    expect(_save(tester).onTap, isNull);
  });
}
