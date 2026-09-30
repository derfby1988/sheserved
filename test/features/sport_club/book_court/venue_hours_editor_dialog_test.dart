import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/venue_hours_editor_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

List<Map<String, dynamic>>? _result;

Widget _host(List<VenueOperatingHours> current) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          _result = await VenueHoursEditorDialog.show(
            context,
            current: current,
          );
        },
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, List<VenueOperatingHours> current) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester
      .pumpWidget(_host(current))
      .then((_) => tester.tap(find.text('open')))
      .then((_) => tester.pumpAndSettle());
}

Finder get _saveButton => find.widgetWithText(GlassActionButton, 'บันทึก');

GlassActionButton _save(WidgetTester tester) =>
    tester.widget<GlassActionButton>(_saveButton);

List<VenueOperatingHours> _closedWeek() => [
  for (var d = 0; d < 7; d++) VenueOperatingHours(dayOfWeek: d, isClosed: true),
];

void main() {
  setUp(() => _result = null);

  testWidgets('unset days are not auto-filled; save stays disabled', (
    tester,
  ) async {
    await _open(tester, const []);
    // No persisted hours -> every day shows placeholders, not 09:00–21:00.
    expect(find.text('--:--'), findsNWidgets(14));
    expect(find.text('09:00'), findsNothing);
    expect(find.text('21:00'), findsNothing);
    expect(find.textContaining('ยังไม่ระบุ 7 วัน'), findsOneWidget);
    expect(_save(tester).onTap, isNull);
  });

  testWidgets('24/7 toggle submits an explicit all-day week', (tester) async {
    await _open(tester, const []);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(_save(tester).onTap, isNotNull);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result, isNotNull);
    expect(_result!.length, 7);
    expect(
      _result!.every(
        (r) => r['open'] == '00:00' && r['close'] == '23:59' && !r['closed'],
      ),
      isTrue,
    );
  });

  testWidgets('specifying every day as closed enables save', (tester) async {
    await _open(tester, const []);
    // Flip each day's open switch off -> explicitly closed.
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.byType(Switch).at(1 + i)); // [0] is 24/7 tile
      await tester.pump();
    }
    expect(_save(tester).onTap, isNotNull);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result, isNotNull);
    expect(_result!.length, 7);
    expect(_result!.every((r) => r['closed'] == true), isTrue);
  });

  testWidgets('persisted closed week loads and re-saves', (tester) async {
    await _open(tester, _closedWeek());
    expect(find.text('--:--'), findsNothing);
    expect(_save(tester).onTap, isNotNull);
  });
}
