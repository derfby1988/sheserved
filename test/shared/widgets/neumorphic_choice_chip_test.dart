import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

Future<void> _pumpChip(
  WidgetTester tester, {
  required bool selected,
  IconData? icon,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: NeumorphicTheme.baseColor,
        body: Center(
          child: NeumorphicChoiceChip(
            label: 'เริ่มต้น',
            icon: icon,
            selected: selected,
            onSelected: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('keeps the same size when the selection changes', (
    tester,
  ) async {
    await _pumpChip(tester, selected: false);
    final unselected = tester.getSize(find.byType(NeumorphicChoiceChip));

    await _pumpChip(tester, selected: true);
    final selected = tester.getSize(find.byType(NeumorphicChoiceChip));

    expect(selected, unselected);
  });

  testWidgets('keeps the same size when selected with a leading icon', (
    tester,
  ) async {
    await _pumpChip(tester, selected: false, icon: Icons.star_rounded);
    final unselected = tester.getSize(find.byType(NeumorphicChoiceChip));

    await _pumpChip(tester, selected: true, icon: Icons.star_rounded);
    final selected = tester.getSize(find.byType(NeumorphicChoiceChip));

    expect(selected, unselected);
  });

  testWidgets('selected chip renders an inset track without a check mark', (
    tester,
  ) async {
    await _pumpChip(tester, selected: true);

    expect(find.byType(NeumorphicInsetBox), findsOneWidget);
    expect(find.byType(NeumorphicContainer), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('selected chip keeps the blue label colour', (tester) async {
    await _pumpChip(tester, selected: true);

    final label = tester.widget<Text>(find.text('เริ่มต้น'));
    expect(label.style?.color, NeumorphicTheme.primaryBlue);
  });

  testWidgets('unselected chip stays raised with a dark label', (tester) async {
    await _pumpChip(tester, selected: false);

    expect(find.byType(NeumorphicContainer), findsOneWidget);
    expect(find.byType(NeumorphicInsetBox), findsNothing);

    final label = tester.widget<Text>(find.text('เริ่มต้น'));
    expect(label.style?.color, NeumorphicTheme.textPrimary);
  });

  testWidgets('tap reports the inverted selection', (tester) async {
    bool? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: NeumorphicChoiceChip(
              label: 'เริ่มต้น',
              selected: false,
              onSelected: (value) => reported = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เริ่มต้น'));
    await tester.pump();

    expect(reported, isTrue);
  });
}
