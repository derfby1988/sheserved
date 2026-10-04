import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/owner_court_editor_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

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
          _result = await OwnerCourtEditorDialog.show(
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

/// The filled save action — 'บันทึก' when editing, 'เพิ่มสนาม' when adding.
Finder get _saveButton => find.byWidgetPredicate(
  (widget) =>
      widget is GlassActionButton &&
      (widget.label == 'บันทึก' || widget.label == 'เพิ่มรายการ'),
);

GlassActionButton _save(WidgetTester tester) =>
    tester.widget<GlassActionButton>(_saveButton);

/// A segment inside the release-mode segmented button — 'กำหนดเอง' also
/// exists on the unit-label segmented button (21.7.19).
Finder _releaseSegment(String label) => find.descendant(
  of: find.byKey(const ValueKey('court-release-mode')),
  matching: find.text(label),
);

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
    expect(_save(tester).onTap, isNull);
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
      find.widgetWithText(SwitchListTile, 'เปิดใช้งานรายการ'),
    );
    expect(toggle.value, isFalse);
    // Re-enable and submit -> draft carries is_active through.
    await tester.tap(find.widgetWithText(SwitchListTile, 'เปิดใช้งานรายการ'));
    await tester.pumpAndSettle();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(_result?['is_active'], isTrue);
    expect(_result?['sport_id'], 's1');
  });

  testWidgets('new court defaults is_active true', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, choices: {'s1': 'Badminton'});
    expect(find.text('เปิดใช้งานรายการ'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'ชื่อรายการ *').first,
      'Court X',
    );
    await tester.pump();
    await tester.tap(_saveButton);
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
    expect(_save(tester).onTap, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'จำนวนการจองซ้ำได้'),
      '101',
    );
    await tester.pump();
    expect(_save(tester).onTap, isNull);
  });

  testWidgets('malformed price disables save', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, court: _court(), choices: {'s1': 'Badminton'});
    await tester.enterText(
      find.widgetWithText(TextField, 'ราคาเริ่มต้น (บาท/ชม.)'),
      'abc',
    );
    await tester.pump();
    expect(find.text('ราคาไม่ถูกต้อง'), findsOneWidget);
    expect(_save(tester).onTap, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'ราคาเริ่มต้น (บาท/ชม.)'),
      '-10',
    );
    await tester.pump();
    expect(_save(tester).onTap, isNull);
  });

  testWidgets('saves owner-defined hourly price windows', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, choices: {'s1': 'Badminton'});
    final nameField = find.widgetWithText(TextField, 'ชื่อรายการ *');
    await tester.enterText(nameField, 'Court X');

    await tester.ensureVisible(find.text('เพิ่มช่วงราคา'));
    await tester.tap(find.text('เพิ่มช่วงราคา'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'ราคา/ชั่วโมง'),
      '125.50',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'ราคา/ชั่วโมง'))
          .controller
          ?.text,
      '125.50',
    );
    expect(find.text('กรุณากรอกราคา/ชั่วโมงไม่เกิน 2 ตำแหน่ง'), findsNothing);
    expect(find.text('เวลาเริ่มต้องน้อยกว่าเวลาสิ้นสุด'), findsNothing);
    expect(find.text('ช่วงเวลาราคาทับซ้อนกัน'), findsNothing);
    await tester.ensureVisible(_saveButton);
    expect(_save(tester).onTap, isNotNull);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    final rules = _result?['price_rules'] as List?;
    expect(rules, hasLength(1));
    expect(rules!.single, {
      'day_of_week': null,
      'start_time': '18:00',
      'end_time': '22:00',
      'price_per_hour': 125.5,
    });
  });

  group('booking release override (21.7.18)', () {
    testWidgets('inherit mode submits the mode with a null triple', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, choices: {'s1': 'Badminton'});
      await tester.enterText(
        find.widgetWithText(TextField, 'ชื่อรายการ *'),
        'Court X',
      );
      await tester.pump();
      await tester.ensureVisible(_saveButton);
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(_result?['booking_release_mode'], 'inherit');
      expect(_result?['booking_release_day_of_week'], isNull);
      expect(_result?['booking_release_days'], isNull);
      expect(_result?['booking_release_time'], isNull);
      expect(_result?['booking_release_window_days'], isNull);
    });

    testWidgets('custom release selects every day at one shared time', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, choices: {'s1': 'Badminton'});
      await tester.enterText(
        find.widgetWithText(TextField, 'ชื่อรายการ *'),
        'Court X',
      );
      await tester.pump();
      await tester.ensureVisible(_releaseSegment('กำหนดเอง'));
      await tester.tap(_releaseSegment('กำหนดเอง'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'เลือกได้หลายวัน โดยใช้เวลาเดียวกัน ส่วนวันอื่นใช้รอบของสถานที่',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('court-release-all-days')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'แต่ละรอบเปิดสล็อตล่วงหน้า (วัน)'),
        '1',
      );
      await tester.pump();
      await tester.ensureVisible(_saveButton);
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(_result?['booking_release_days'], [0, 1, 2, 3, 4, 5, 6]);
      expect(_result?['booking_release_time'], '09:00');
      expect(_result?['booking_release_window_days'], 1);
    });

    testWidgets('custom mode submits the full release triple', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, choices: {'s1': 'Badminton'});
      await tester.enterText(
        find.widgetWithText(TextField, 'ชื่อรายการ *'),
        'Court X',
      );
      await tester.pump();
      await tester.ensureVisible(_releaseSegment('กำหนดเอง'));
      await tester.tap(_releaseSegment('กำหนดเอง'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'แต่ละรอบเปิดสล็อตล่วงหน้า (วัน)'),
        '14',
      );
      await tester.pump();
      await tester.ensureVisible(_saveButton);
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(_result?['booking_release_mode'], 'custom');
      expect(_result?['booking_release_day_of_week'], 1);
      expect(_result?['booking_release_days'], [1]);
      expect(_result?['booking_release_time'], '09:00');
      expect(_result?['booking_release_window_days'], 14);
    });

    testWidgets('custom release window below 7 days disables save', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, court: _court(), choices: {'s1': 'Badminton'});
      await tester.ensureVisible(_releaseSegment('กำหนดเอง'));
      await tester.tap(_releaseSegment('กำหนดเอง'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'แต่ละรอบเปิดสล็อตล่วงหน้า (วัน)'),
        '3',
      );
      await tester.pump();
      // Helper text and error text both carry the hint.
      expect(find.text('อย่างน้อย 7 วัน'), findsWidgets);
      await tester.ensureVisible(_saveButton);
      expect(_save(tester).onTap, isNull);
    });

    testWidgets('multi-day window covers the longest gap between releases', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, court: _court(), choices: {'s1': 'Badminton'});
      await tester.ensureVisible(_releaseSegment('กำหนดเอง'));
      await tester.tap(_releaseSegment('กำหนดเอง'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('court-release-day-3')),
      );
      await tester.tap(find.byKey(const ValueKey('court-release-day-3')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'แต่ละรอบเปิดสล็อตล่วงหน้า (วัน)'),
        '4',
      );
      await tester.pump();
      expect(find.text('อย่างน้อย 5 วัน'), findsWidgets);
      await tester.ensureVisible(_saveButton);
      expect(_save(tester).onTap, isNull);
    });

    testWidgets('existing custom override prefills the release fields', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final court = VenueCourt(
        id: 'c1',
        venueId: 'v1',
        sportId: 's1',
        name: 'Court 1',
        bookingReleaseMode: 'custom',
        bookingReleaseDayOfWeek: 3,
        bookingReleaseTime: '10:30',
        bookingReleaseWindowDays: 21,
      );
      await _open(tester, court: court, choices: {'s1': 'Badminton'});
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'แต่ละรอบเปิดสล็อตล่วงหน้า (วัน)'),
      );
      expect(find.text('เวลาเดียวกันทุกวันที่เลือก · 10:30'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'แต่ละรอบเปิดสล็อตล่วงหน้า (วัน)'),
            )
            .controller
            ?.text,
        '21',
      );
      // Switching back to inherit clears the triple but keeps the mode.
      await tester.ensureVisible(_releaseSegment('ตามสถานที่'));
      await tester.tap(_releaseSegment('ตามสถานที่'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_saveButton);
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(_result?['booking_release_mode'], 'inherit');
      expect(_result?['booking_release_day_of_week'], isNull);
    });
  });

  group('unit label override (21.7.19)', () {
    Finder unitSegment(String label) => find.descendant(
      of: find.byKey(const ValueKey('court-unit-label-mode')),
      matching: find.text(label),
    );

    testWidgets('new court inherits by default and submits mode+null', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, choices: {'s1': 'Badminton'});
      await tester.enterText(
        find.widgetWithText(TextField, 'ชื่อรายการ *'),
        'Court X',
      );
      await tester.pump();
      await tester.ensureVisible(_saveButton);
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(_result?['unit_label_mode'], 'inherit');
      expect(_result?['unit_label'], isNull);
    });

    testWidgets('custom mode submits the typed label', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, choices: {'s1': 'Badminton'});
      await tester.enterText(
        find.widgetWithText(TextField, 'ชื่อรายการ *'),
        'Court X',
      );
      await tester.ensureVisible(unitSegment('กำหนดเอง'));
      await tester.tap(unitSegment('กำหนดเอง'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'ชื่อเรียกเฉพาะรายการนี้ *'),
        'โต๊ะ',
      );
      await tester.pump();
      await tester.ensureVisible(_saveButton);
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(_result?['unit_label_mode'], 'custom');
      expect(_result?['unit_label'], 'โต๊ะ');
    });

    testWidgets('empty custom label disables save', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, court: _court(), choices: {'s1': 'Badminton'});
      await tester.ensureVisible(unitSegment('กำหนดเอง'));
      await tester.tap(unitSegment('กำหนดเอง'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_saveButton);
      expect(_save(tester).onTap, isNull);
    });

    testWidgets('existing override prefills custom; inherit clears it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final court = VenueCourt(
        id: 'c1',
        venueId: 'v1',
        sportId: 's1',
        name: 'Court 1',
        unitLabel: 'โต๊ะ',
        unitLabelOverride: 'โต๊ะ',
      );
      await _open(tester, court: court, choices: {'s1': 'Badminton'});
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'ชื่อเรียกเฉพาะรายการนี้ *'),
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'ชื่อเรียกเฉพาะรายการนี้ *'),
            )
            .controller
            ?.text,
        'โต๊ะ',
      );
      await tester.ensureVisible(unitSegment('ตามกีฬา/สถานที่'));
      await tester.tap(unitSegment('ตามกีฬา/สถานที่'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ตอนนี้แสดงว่า "โต๊ะ"'), findsOneWidget);
      await tester.ensureVisible(_saveButton);
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(_result?['unit_label_mode'], 'inherit');
      expect(_result?['unit_label'], isNull);
    });
  });
}
