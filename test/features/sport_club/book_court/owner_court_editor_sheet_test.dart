import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/owner_court_editor_sheet.dart';

Map<String, dynamic>? _result;

Widget _host({
  VenueCourt? court,
  String sportId = 's1',
  Map<String, String>? choices,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          _result = await OwnerCourtEditorSheet.show(
            context,
            court: court,
            sportId: sportId,
            sportChoices: choices,
          );
        },
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(
  WidgetTester tester, {
  VenueCourt? court,
  String sportId = 's1',
  Map<String, String>? choices,
}) {
  return tester
      .pumpWidget(_host(court: court, sportId: sportId, choices: choices))
      .then((_) => tester.tap(find.text('open')))
      .then((_) => tester.pumpAndSettle());
}

VenueCourt _court({
  String sportId = 's1',
  bool isActive = true,
  int capacity = 1,
}) => VenueCourt(
  id: 'c1',
  venueId: 'v1',
  sportId: sportId,
  name: 'Court 1',
  capacity: capacity,
  isActive: isActive,
);

FilledButton _save(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  setUp(() => _result = null);

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('sport removed from venue requires explicit reselection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final court = _court(sportId: 'removed-sport');
    await _open(
      tester,
      court: court,
      sportId: 'removed-sport',
      choices: {'s1': 'Badminton', 's2': 'Tennis'},
    );
    // The missing sport is shown as an explicit warning, never silently
    // swapped to the first choice.
    expect(find.textContaining('กีฬาเดิมถูกเอาออก'), findsOneWidget);
    expect(_save(tester).onPressed, isNull);
  });

  testWidgets('is_active is preserved and toggleable when editing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(
      tester,
      court: _court(isActive: false),
      choices: {'s1': 'Badminton'},
    );
    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'เปิดใช้งานคอร์ท'),
    );
    expect(toggle.value, isFalse);
    // Re-enable and submit -> draft carries is_active through.
    await tester.tap(find.widgetWithText(SwitchListTile, 'เปิดใช้งานคอร์ท'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(_result?['is_active'], isTrue);
    expect(_result?['sport_id'], 's1');
  });

  testWidgets('new court defaults is_active true', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, choices: {'s1': 'Badminton'});
    expect(find.text('เปิดใช้งานคอร์ท'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'ชื่อสนาม/คอร์ท *').first,
      'Court X',
    );
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(_result?['is_active'], isTrue);
  });

  testWidgets('capacity outside 1-100 disables save', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, court: _court(), choices: {'s1': 'Badminton'});
    await tester.enterText(
      find.widgetWithText(TextField, 'จำนวนการจองซ้ำได้'),
      '0',
    );
    await tester.pump();
    expect(_save(tester).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'จำนวนการจองซ้ำได้'),
      '101',
    );
    await tester.pump();
    expect(_save(tester).onPressed, isNull);
  });

  testWidgets('malformed price disables save', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, court: _court(), choices: {'s1': 'Badminton'});
    await tester.enterText(find.widgetWithText(TextField, 'ราคา (บาท)'), 'abc');
    await tester.pump();
    expect(find.text('ราคาไม่ถูกต้อง'), findsOneWidget);
    expect(_save(tester).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'ราคา (บาท)'), '-10');
    await tester.pump();
    expect(_save(tester).onPressed, isNull);
  });
}
