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
  double minWidth = 0,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
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
              minWidth: minWidth,
              padding: padding,
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

  testWidgets('horizontal padding widens the capsule and keeps the height', (
    tester,
  ) async {
    final natural = await _naturalRect(tester, 'ยกเลิก');
    await _pumpInUnboundedRow(tester, 'ยกเลิก');
    final bare = tester.getSize(find.byType(NeumorphicPillButton));
    await _pumpInUnboundedRow(
      tester,
      'ยกเลิก',
      padding: const EdgeInsets.symmetric(horizontal: 14),
    );
    final padded = tester.getSize(find.byType(NeumorphicPillButton));

    expect(padded.width, bare.width + 28);
    expect(padded.height, bare.height);
    expect(tester.getRect(find.text('ยกเลิก')).size, natural.size);
  });

  testWidgets('minWidth gives a short label the width of a longer one', (
    tester,
  ) async {
    const short = 'ยกเลิก';
    const long = 'ยืนยันการจองสนาม';
    await _pumpInUnboundedRow(tester, long);
    final longWidth = tester.getSize(find.byType(NeumorphicPillButton)).width;
    await _pumpInUnboundedRow(tester, short, minWidth: longWidth);

    expect(longWidth, greaterThan(0));
    expect(tester.getSize(find.byType(NeumorphicPillButton)).width, longWidth);
    expect(tester.getSize(find.byType(NeumorphicPillButton)).height, 48);
    expect(
      tester.getCenter(find.text(short)).dx,
      tester.getCenter(find.byType(NeumorphicPillButton)).dx,
    );
  });

  testWidgets('minWidth wider than maxWidth falls back to the cap', (
    tester,
  ) async {
    await _pumpInUnboundedRow(tester, _longLabel, maxWidth: 200, minWidth: 400);

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
