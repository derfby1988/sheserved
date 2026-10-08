import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/shared/widgets/gradient_progress_bar.dart';

Widget _harness({
  double height = 3,
  List<Color>? colors,
  Color? trackColor,
  double width = 320,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: GradientProgressBar(
            height: height,
            colors: colors ?? const [Color(0xFFFF6B35), Color(0xFFFFC24B)],
            trackColor: trackColor,
          ),
        ),
      ),
    ),
  );
}

Align _segment(WidgetTester tester) => tester.widget<Align>(
  find.descendant(
    of: find.byType(GradientProgressBar),
    matching: find.byType(Align),
  ),
);

void main() {
  group('GradientProgressBar (§22.3.3 map loading indicator)', () {
    testWidgets('แสดงตามความสูงที่กำหนด', (tester) async {
      await tester.pumpWidget(_harness(height: 4));
      expect(tester.getSize(find.byType(GradientProgressBar)).height, 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('segment เคลื่อนจากซ้ายไปขวาแบบวนซ้ำ', (tester) async {
      await tester.pumpWidget(_harness());
      final first = (_segment(tester).alignment as Alignment).x;
      await tester.pump(const Duration(milliseconds: 320));
      final second = (_segment(tester).alignment as Alignment).x;
      expect(second, greaterThan(first));

      // วนครบรอบแล้วเริ่มใหม่จากฝั่งซ้าย (ไม่ค้างที่ขวา)
      await tester.pump(const Duration(milliseconds: 1200));
      final afterFullPeriod = (_segment(tester).alignment as Alignment).x;
      expect(afterFullPeriod, lessThan(second));
    });

    testWidgets('เริ่มต้นนอกจอซ้ายและจบเลยขอบขวา (ไม่กระตุกตอนวนรอบ)', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      expect((_segment(tester).alignment as Alignment).x, lessThan(-1.5));

      await tester.pump(const Duration(milliseconds: 1200));
      expect((_segment(tester).alignment as Alignment).x, greaterThan(1.5));
    });

    testWidgets('ใช้สีที่ส่งมาและจางหัวท้ายด้วย alpha 0', (tester) async {
      const colors = [Color(0xFF00FF00), Color(0xFF0000FF)];
      await tester.pumpWidget(_harness(colors: colors));

      final decorated = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(GradientProgressBar),
          matching: find.byType(DecoratedBox),
        ),
      );
      final gradient =
          (decorated.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.length, 4);
      expect(gradient.colors.first.a, 0);
      expect(gradient.colors.last.a, 0);
      expect(gradient.colors[1], colors.first);
      expect(gradient.colors[2], colors.last);
    });

    testWidgets('trackColor เป็นรางด้านหลัง', (tester) async {
      await tester.pumpWidget(_harness(trackColor: const Color(0x33FFFFFF)));
      final track = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(GradientProgressBar),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(track.color, const Color(0x33FFFFFF));
    });

    testWidgets('ไม่ล้นที่ความกว้าง 320dp', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_harness(width: 288));
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.byType(GradientProgressBar));
      expect(rect.width, 288);
      expect(rect.right, lessThanOrEqualTo(320));
    });
  });
}
