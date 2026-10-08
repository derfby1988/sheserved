import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/incident_map/incident_map_surface.dart';
import 'package:sheserved/shared/widgets/gradient_progress_bar.dart';

Widget _harness({Size cardSize = const Size(64, 64)}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: cardSize.width,
          height: cardSize.height,
          child: const IncidentPhotoLoadingPlaceholder(),
        ),
      ),
    ),
  );
}

void main() {
  group('IncidentPhotoLoadingPlaceholder (§22.16 per-image indicator)', () {
    testWidgets('แสดง gradient bar ต่อ thumbnail ระหว่างรอภาพ', (tester) async {
      await tester.pumpWidget(_harness());
      expect(find.byType(GradientProgressBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('มีรางจาง ๆ ให้เห็นตำแหน่งแถบตั้งแต่ยังไม่โหลดเสร็จ', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      final bar = tester.widget<GradientProgressBar>(
        find.byType(GradientProgressBar),
      );
      expect(bar.trackColor, Colors.white24);
    });

    testWidgets('segment เคลื่อนไหว (ไม่ใช่กล่องนิ่ง)', (tester) async {
      await tester.pumpWidget(_harness());
      double slide() =>
          (tester
                      .widget<Align>(
                        find.descendant(
                          of: find.byType(GradientProgressBar),
                          matching: find.byType(Align),
                        ),
                      )
                      .alignment
                  as Alignment)
              .x;

      final first = slide();
      await tester.pump(const Duration(milliseconds: 300));
      expect(slide(), isNot(first));
    });

    testWidgets('ไม่ล้นการ์ดขนาด 64dp และอยู่กึ่งกลางการ์ด', (tester) async {
      await tester.pumpWidget(_harness());
      expect(tester.takeException(), isNull);
      final barRect = tester.getRect(find.byType(GradientProgressBar));
      final cardRect = tester.getRect(
        find.byType(IncidentPhotoLoadingPlaceholder),
      );
      expect(cardRect.contains(barRect.topLeft), isTrue);
      expect(cardRect.contains(barRect.bottomRight), isTrue);
      expect(barRect.width, 44);
      expect(barRect.center.dx, closeTo(cardRect.center.dx, 0.5));
      expect(barRect.center.dy, closeTo(cardRect.center.dy, 0.5));
    });
  });
}
