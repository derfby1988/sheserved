import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/shared/presentation/widgets/sports_hub_page_indicator.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

/// Host ที่เปลี่ยนหน้าได้จริง เพื่อทดสอบว่าผิวปุ่มย้ายตามหน้าที่ถูกเลือก
class _IndicatorHost extends StatefulWidget {
  const _IndicatorHost({required this.initialPage});

  final int initialPage;

  @override
  State<_IndicatorHost> createState() => _IndicatorHostState();
}

class _IndicatorHostState extends State<_IndicatorHost> {
  late int _page = widget.initialPage;

  @override
  Widget build(BuildContext context) {
    return SportsHubPageIndicator(
      currentPage: _page,
      onPageSelected: (page) => setState(() => _page = page),
    );
  }
}

Color _labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!.color!;

Future<void> _pumpIndicator(
  WidgetTester tester, {
  required int currentPage,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Align(
          alignment: Alignment.topCenter,
          child: _IndicatorHost(initialPage: currentPage),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _pillOpacity() => find.ancestor(
  of: find.byType(LitGlassSurface),
  matching: find.byType(Opacity),
);

void main() {
  group('SportsHubPageIndicator selected button', () {
    testWidgets('uses the drawer section-header glass only when selected', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 1);

      expect(find.byType(LitGlassSurface), findsOneWidget);
      final surface = tester.widget<LitGlassSurface>(
        find.byType(LitGlassSurface),
      );
      // ค่าเดียวกับ _buildGroupHeader (section ที่กางอยู่) ใน tlz_drawer.dart
      expect(surface.selected, isTrue);
      expect(surface.borderRadius, 16);
      expect(surface.surfaceColor, Colors.white);
      expect(surface.fillOpacity, 0.12);
      expect(surface.accentColor, AppColors.primary);
      expect(surface.accentStrength, 0.16);
      expect(surface.glowOpacity, 0.08);
      expect(surface.rimWidth, 1);
      // ดันแสงขอบให้เห็นชัดบนผิวเล็ก (ปุ่มสูง 40px vs tile drawer 48px)
      expect(surface.rimBoost, 1.4);
      // rim ขาวกว่าสูตร drawer เพื่อให้ขอบสว่างกว่าพื้นแถบจริง ๆ
      expect(
        surface.rimColor,
        Color.lerp(Colors.white, AppColors.primary, 0.12),
      );
      expect(surface.shadowOpacity, 0.10);
      expect(surface.blurSigma, 0);

      // ตัวอักษรของปุ่มที่เลือกเป็นสีเข้มบนแก้วขาวใส อีกสองปุ่มคงสีรองเดิม
      expect(_labelColor(tester, 'ก๊วน'), AppColors.textPrimary);
      expect(_labelColor(tester, 'สนาม'), AppColors.textSecondary);
      expect(_labelColor(tester, 'โค้ช'), AppColors.textSecondary);
    });

    testWidgets('sits the glass on the drawer panel tone like the drawer', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 0);

      // ใต้กระจกคือโทนแผง drawer (หน้าขาว + scrim black54 + แผงกระจก)
      // เพื่อให้แสงขาวตามขอบปุ่มเห็นได้เหมือนใน drawer
      final backing = tester.widget<DecoratedBox>(
        find.descendant(
          of: find
              .ancestor(
                of: find.byType(LitGlassSurface),
                matching: find.byType(Stack),
              )
              .first,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color ==
                    const Color(0xFF6C7073).withValues(alpha: 0.17),
          ),
        ),
      );
      final decoration = backing.decoration as BoxDecoration;
      expect(
        decoration.borderRadius,
        const BorderRadius.all(Radius.circular(16)),
      );
    });

    testWidgets('moves the glass surface to the newly selected page', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 1);

      await tester.tap(find.text('โค้ช'));
      await tester.pumpAndSettle();

      expect(find.byType(LitGlassSurface), findsOneWidget);
      expect(_labelColor(tester, 'โค้ช'), AppColors.textPrimary);
      expect(_labelColor(tester, 'ก๊วน'), AppColors.textSecondary);

      await tester.tap(find.text('สนาม'));
      await tester.pumpAndSettle();
      expect(_labelColor(tester, 'สนาม'), AppColors.textPrimary);
      expect(_labelColor(tester, 'โค้ช'), AppColors.textSecondary);
    });

    testWidgets('fades the glass surface in over the 200ms transition', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 1);
      expect(tester.widget<Opacity>(_pillOpacity()).opacity, 1);

      await tester.tap(find.text('โค้ช'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // ระหว่างสลับหน้ามีสองผิวพร้อมกัน: ผิวเดิมจางออก + ผิวใหม่จางเข้า
      final midOpacities = tester
          .widgetList<Opacity>(_pillOpacity())
          .map((widget) => widget.opacity)
          .toList();
      expect(midOpacities, isNotEmpty);
      expect(midOpacities.any((value) => value > 0 && value < 1), isTrue);
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(_pillOpacity()).opacity, 1);
    });

    testWidgets('fits the pill inside the button slot on a phone width', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 2);

      final size = tester.getSize(find.byType(LitGlassSurface));
      // 44 สูง หัก margin แนวตั้ง 2+2
      expect(size.height, 40);
      expect(size.width, greaterThan(80));
      expect(tester.takeException(), isNull);
    });
  });
}
