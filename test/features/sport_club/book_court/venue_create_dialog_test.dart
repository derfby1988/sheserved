import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/venue_create_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

({String name, String? venueUnitLabelOverride})? _result;

Widget _host() => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          _result = await VenueCreateDialog.show(context);
        },
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) {
  return tester
      .pumpWidget(_host())
      .then((_) => tester.tap(find.text('open')))
      .then((_) => tester.pumpAndSettle());
}

Finder get _create => find.byWidgetPredicate(
  (widget) => widget is GlassActionButton && widget.label == 'สร้าง',
);

void main() {
  setUp(() => _result = null);

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('generic mode creates with a null label override', (
    tester,
  ) async {
    await _open(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'ชื่อสถานที่ *'),
      'สนาม ABC',
    );
    await tester.pump();
    await tester.tap(_create);
    await tester.pumpAndSettle();
    expect(_result?.name, 'สนาม ABC');
    expect(_result?.venueUnitLabelOverride, isNull);
  });

  testWidgets('custom mode requires a label and submits it', (tester) async {
    await _open(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'ชื่อสถานที่ *'),
      'ยิม XYZ',
    );
    await tester.tap(find.text('กำหนดเอง'));
    await tester.pumpAndSettle();
    // Custom mode with an empty label disables create.
    expect(tester.widget<GlassActionButton>(_create).onTap, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'ชื่อเรียกสถานที่ *'),
      'ยิม',
    );
    await tester.pump();
    await tester.tap(_create);
    await tester.pumpAndSettle();
    expect(_result?.name, 'ยิม XYZ');
    expect(_result?.venueUnitLabelOverride, 'ยิม');
  });

  testWidgets('empty name disables create', (tester) async {
    await _open(tester);
    expect(tester.widget<GlassActionButton>(_create).onTap, isNull);
  });
}
