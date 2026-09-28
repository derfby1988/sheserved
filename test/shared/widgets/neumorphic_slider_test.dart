import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

Future<void> _pumpSlider(
  WidgetTester tester, {
  double value = 0,
  ValueChanged<double>? onChanged,
  String? label,
  double trackHeight = 30,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: NeumorphicTheme.baseColor,
        // Column ให้ความสูงแบบ unbounded เหมือนการใช้งานจริงใน bottom sheet
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 300,
              child: NeumorphicSlider(
                value: value,
                min: 0,
                max: 10,
                divisions: 10,
                label: label,
                trackHeight: trackHeight,
                onChanged: onChanged ?? (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders as a slider with the neumorphic track height', (
    tester,
  ) async {
    await _pumpSlider(tester);

    expect(find.byType(Slider), findsOneWidget);
    expect(
      tester.getSize(find.byType(NeumorphicSlider)).height,
      30,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the requested track height', (tester) async {
    await _pumpSlider(tester, trackHeight: 40);

    expect(tester.getSize(find.byType(NeumorphicSlider)).height, 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging along the track reports increasing values', (
    tester,
  ) async {
    double? reported;
    await _pumpSlider(tester, onChanged: (value) => reported = value);

    final rect = tester.getRect(find.byType(NeumorphicSlider));
    await tester.dragFrom(
      Offset(rect.left + 12, rect.center.dy),
      Offset(rect.width / 2, 0),
    );
    await tester.pumpAndSettle();

    expect(reported, isNotNull);
    expect(reported, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag with a value label paints without errors', (tester) async {
    await _pumpSlider(tester, label: '5');

    final rect = tester.getRect(find.byType(NeumorphicSlider));
    await tester.dragFrom(
      Offset(rect.left + 12, rect.center.dy),
      Offset(rect.width / 2, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled slider paints without errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: NeumorphicTheme.baseColor,
          body: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 300,
                child: NeumorphicSlider(value: 5, min: 0, max: 10),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clamps an out-of-range value', (tester) async {
    await _pumpSlider(tester, value: 99);

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the thumb off the track ends', (tester) async {
    double? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: NeumorphicTheme.baseColor,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 300,
                child: NeumorphicSlider(
                  value: 0,
                  min: 0,
                  max: 10,
                  trackHeight: 30,
                  onChanged: (value) => reported = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // ระยะเดินของหัวหมุด = ความกว้างราง - 2 * (trackHeight / 2)
    const edgeInset = 15.0;
    final rect = tester.getRect(find.byType(NeumorphicSlider));
    final travel = rect.width - edgeInset * 2;

    await tester.tapAt(
      Offset(rect.left + edgeInset + travel * 0.25, rect.center.dy),
    );
    await tester.pumpAndSettle();

    expect(reported, closeTo(2.5, 0.2));
    expect(tester.takeException(), isNull);
  });
}
