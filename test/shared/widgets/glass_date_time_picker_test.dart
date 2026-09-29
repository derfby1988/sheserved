import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/shared/widgets/glass/glass_date_time_picker.dart';

void main() {
  testWidgets('date picker returns the tapped day at midnight', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async => picked = await GlassDatePicker.show(
                  ctx,
                  initialDate: DateTime(2026, 8, 10),
                  firstDate: DateTime(2026, 1, 1),
                  lastDate: DateTime(2026, 12, 31),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Opens on the initial month (Buddhist year 2569).
    expect(find.text('สิงหาคม 2569'), findsOneWidget);
    expect(find.text('10 สิงหาคม พ.ศ. 2569'), findsOneWidget);

    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(find.text('12 สิงหาคม พ.ศ. 2569'), findsOneWidget);

    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 8, 12));
  });

  testWidgets('date picker cancel returns null', (tester) async {
    DateTime? picked;
    bool completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  picked = await GlassDatePicker.show(
                    ctx,
                    initialDate: DateTime(2026, 8, 10),
                    firstDate: DateTime(2026, 1, 1),
                    lastDate: DateTime(2026, 12, 31),
                  );
                  completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(picked, isNull);
  });

  testWidgets('days outside firstDate..lastDate cannot be selected', (
    tester,
  ) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async => picked = await GlassDatePicker.show(
                  ctx,
                  initialDate: DateTime(2026, 8, 20),
                  firstDate: DateTime(2026, 8, 15),
                  lastDate: DateTime(2026, 8, 31),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    expect(find.text('20 สิงหาคม พ.ศ. 2569'), findsOneWidget);

    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 8, 20));
  });

  testWidgets('month navigation is clamped to the allowed range', (
    tester,
  ) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async => picked = await GlassDatePicker.show(
                  ctx,
                  initialDate: DateTime(2026, 8, 10),
                  firstDate: DateTime(2026, 1, 5),
                  lastDate: DateTime(2026, 10, 20),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('เดือนถัดไป'));
    await tester.pumpAndSettle();
    expect(find.text('กันยายน 2569'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('เดือนก่อนหน้า'));
    await tester.pumpAndSettle();
    expect(find.text('สิงหาคม 2569'), findsOneWidget);

    // Walk up to the last allowed month (ตุลาคม 2569) …
    await tester.tap(find.bySemanticsLabel('เดือนถัดไป'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('เดือนถัดไป'));
    await tester.pumpAndSettle();
    expect(find.text('ตุลาคม 2569'), findsOneWidget);

    // … where the "next" arrow stops working.
    await tester.tap(find.bySemanticsLabel('เดือนถัดไป'));
    await tester.pumpAndSettle();
    expect(find.text('ตุลาคม 2569'), findsOneWidget);

    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('year mode selects a Buddhist year', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async => picked = await GlassDatePicker.show(
                  ctx,
                  initialDate: DateTime(2026, 8, 10),
                  firstDate: DateTime(2025, 1, 1),
                  lastDate: DateTime(2027, 12, 31),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('สิงหาคม 2569'));
    await tester.pumpAndSettle();
    expect(find.text('เลือกปี พ.ศ.'), findsOneWidget);

    // 2568 = 2025 CE, the earliest allowed year in the grid.
    await tester.tap(find.text('2568'));
    await tester.pumpAndSettle();
    expect(find.text('สิงหาคม 2568'), findsOneWidget);

    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2025, 8, 10));
  });

  testWidgets('time picker returns the initial value', (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async => picked = await GlassTimePicker.show(
                  ctx,
                  initialTime: const TimeOfDay(hour: 9, minute: 30),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('09:30 น.'), findsOneWidget);
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 9, minute: 30));
  });

  testWidgets('time picker wheel changes the value and cancel returns null', (
    tester,
  ) async {
    TimeOfDay? picked;
    bool completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  picked = await GlassTimePicker.show(
                    ctx,
                    initialTime: const TimeOfDay(hour: 9, minute: 30),
                  );
                  completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Scroll the hour wheel one step down → 08:30.
    await tester.drag(
      find.byType(ListWheelScrollView).first,
      const Offset(0, 40),
    );
    await tester.pumpAndSettle();
    expect(find.text('08:30 น.'), findsOneWidget);

    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(picked, isNull);
  });

  testWidgets('both pickers fit a small phone viewport without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => GlassDatePicker.show(
                  ctx,
                  initialDate: DateTime(2026, 8, 10),
                  firstDate: DateTime(2025, 1, 1),
                  lastDate: DateTime(2027, 12, 31),
                ),
                child: const Text('open date'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open date'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('สิงหาคม 2569'), findsOneWidget);

    // Year grid scrolls and still fits the short viewport.
    await tester.tap(find.text('สิงหาคม 2569'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(GridView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('กลับไปปฏิทิน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => GlassTimePicker.show(
                  ctx,
                  initialTime: const TimeOfDay(hour: 9, minute: 30),
                ),
                child: const Text('open time'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open time'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('09:30 น.'), findsOneWidget);
  });

  testWidgets('time picker reports the scrolled hour', (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async => picked = await GlassTimePicker.show(
                  ctx,
                  initialTime: const TimeOfDay(hour: 9, minute: 0),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(ListWheelScrollView).first,
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    expect(find.text('11:00 น.'), findsOneWidget);

    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 11, minute: 0));
  });
}
