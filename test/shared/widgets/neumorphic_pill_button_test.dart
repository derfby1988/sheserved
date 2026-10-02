import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

/// Wide enough that the natural label exceeds the 800px test surface.
const _longLabel =
    'แก้ไขและส่งคำขอเป็นเจ้าของสนามกีฬาแห่งใหม่พร้อมเอกสารประกอบการพิจารณา'
    'ของทีมงาน Sheserved และรายละเอียดเพิ่มเติมทั้งหมด';

const _labelStyle = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600);

/// A [Row] hands its non-flexible children unbounded width — the classic
/// trap where a shrink-wrapped pill grows past the screen edge.
Future<void> _pumpInUnboundedRow(
  WidgetTester tester,
  String text, {
  double? maxWidth,
  IconData? icon,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: NeumorphicTheme.baseColor,
        body: Row(
          children: [
            NeumorphicPillButton(
              text: text,
              icon: icon,
              maxWidth: maxWidth,
              onPressed: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

/// The label's unscaled rect — laid out with no width limit at all, under the
/// same [Scaffold] text theme the button renders with.
Future<Rect> _naturalRect(WidgetTester tester, String text) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: NeumorphicTheme.baseColor,
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [Text(text, maxLines: 1, style: _labelStyle)]),
        ),
      ),
    ),
  );
  return tester.getRect(find.text(text));
}

void main() {
  testWidgets('long label never overflows an unbounded row', (tester) async {
    await _pumpInUnboundedRow(tester, _longLabel, icon: Icons.refresh_rounded);

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(NeumorphicPillButton)).width,
      lessThanOrEqualTo(800 - 32),
    );
  });

  testWidgets('long label shrinks to fit the capsule', (tester) async {
    final natural = await _naturalRect(tester, _longLabel);
    await _pumpInUnboundedRow(tester, _longLabel);
    final painted = tester.getRect(find.text(_longLabel));

    expect(painted.width, lessThan(natural.width));
    expect(painted.height, lessThan(natural.height));
    expect(painted.width, lessThanOrEqualTo(800 - 32));
  });

  testWidgets('short label keeps its natural size and pill height', (
    tester,
  ) async {
    final natural = await _naturalRect(tester, 'ยกเลิก');
    await _pumpInUnboundedRow(tester, 'ยกเลิก');

    expect(tester.getRect(find.text('ยกเลิก')).size, natural.size);
    expect(tester.getSize(find.byType(NeumorphicPillButton)).height, 48);
    expect(
      tester.getSize(find.byType(NeumorphicPillButton)).width,
      lessThan(200),
    );
  });

  testWidgets('explicit maxWidth caps the capsule tighter than the viewport', (
    tester,
  ) async {
    await _pumpInUnboundedRow(tester, _longLabel, maxWidth: 200);

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(NeumorphicPillButton)).width,
      lessThanOrEqualTo(200),
    );
  });

  testWidgets('color tints a raised pill without sinking it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: NeumorphicTheme.baseColor,
          body: Center(
            child: NeumorphicPillButton(
              text: 'จัดการ',
              icon: Icons.tune_rounded,
              color: NeumorphicTheme.primaryBlue,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    final container = tester.widget<NeumorphicContainer>(
      find.byType(NeumorphicContainer),
    );
    expect(container.isPressed, isFalse);
    expect(
      tester.widget<Text>(find.text('จัดการ')).style?.color,
      NeumorphicTheme.primaryBlue,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.tune_rounded)).color,
      NeumorphicTheme.primaryBlue,
    );
  });

  testWidgets('active still sinks the pill and colours it blue', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: NeumorphicTheme.baseColor,
          body: Center(
            child: NeumorphicPillButton(
              text: 'จัดการ',
              active: true,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<NeumorphicContainer>(find.byType(NeumorphicContainer))
          .isPressed,
      isTrue,
    );
    expect(
      tester.widget<Text>(find.text('จัดการ')).style?.color,
      NeumorphicTheme.primaryBlue,
    );
  });
}
