import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/shared/presentation/widgets/sports_hub_page_indicator.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic_inset.dart';

/// Host ที่เลียนแบบ `SportsHubPager`: `page` เป็นค่าต่อเนื่อง และแยก callback
/// ระหว่างแตะ (selected) กับลาก ruler (scrubbed) เพื่อทดสอบ snap ระหว่างลาก
class _IndicatorHost extends StatefulWidget {
  const _IndicatorHost({super.key, required this.initialPage});

  final int initialPage;

  @override
  State<_IndicatorHost> createState() => _IndicatorHostState();
}

class _IndicatorHostState extends State<_IndicatorHost> {
  late double _page = widget.initialPage.toDouble();
  final List<int> selected = [];
  final List<int> scrubbed = [];

  @override
  Widget build(BuildContext context) {
    return SportsHubPageIndicator(
      page: _page,
      onPageSelected: (page) {
        selected.add(page);
        setState(() => _page = page.toDouble());
      },
      onPageScrubbed: (page) {
        scrubbed.add(page);
        setState(() => _page = page.toDouble());
      },
    );
  }
}

Color _labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!.color!;

/// หัวหมุดแก้วขาว (Container 32×12) — ใช้ดูว่าหัวหมุดวิ่งตาม `page`
Finder _thumbFinder() => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.constraints == BoxConstraints.tightFor(width: 32, height: 12),
);

/// รางจม — CustomPaint ที่ใช้ [NeumorphicInsetPainter] ตัวเดียวกับ slider
Finder _grooveFinder() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is NeumorphicInsetPainter,
);

Finder _rulerFinder() => find.bySemanticsLabel('แถบเลื่อนเปลี่ยนหน้า');

Finder _shakeFinder() => find.byKey(SportsHubPageIndicator.shakeKey);

/// มุมเอียง (เรเดียน) ของอนิเมชันเขย่า (0 = ไม่ได้เขย่า)
double _shakeAngle(WidgetTester tester) {
  final finder = _shakeFinder();
  if (finder.evaluate().isEmpty) return 0;
  final matrix = tester.widget<Transform>(finder).transform;
  return math.atan2(matrix.storage[1], matrix.storage[0]);
}

Future<void> _pumpIndicator(
  WidgetTester tester, {
  required int currentPage,
  GlobalKey<_IndicatorHostState>? hostKey,
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
          child: _IndicatorHost(key: hostKey, initialPage: currentPage),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// เหมือน [_pumpPage] แต่ pump เฟรมเดียว ไม่ settle — ใช้คุมจังหวะอนิเมชัน
Future<void> _pumpPageOnce(WidgetTester tester, double page) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Align(
          alignment: Alignment.topCenter,
          child: SportsHubPageIndicator(page: page, onPageSelected: (_) {}),
        ),
      ),
    ),
  );
}

Future<void> _pumpPage(WidgetTester tester, double page) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Align(
          alignment: Alignment.topCenter,
          child: SportsHubPageIndicator(page: page, onPageSelected: (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SportsHubPageIndicator selected button', () {
    testWidgets('uses the drawer section-header glass only when selected', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 1);

      expect(find.byType(LitGlassSurface), findsOneWidget);
      expect(find.byType(LitGlassTile), findsOneWidget);
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

  group('SportsHubPageIndicator ruler', () {
    testWidgets('renders a neumorphic groove with the white glass thumb', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 0);

      expect(_grooveFinder(), findsOneWidget);
      expect(_thumbFinder(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('moves the thumb continuously with the page value', (
      tester,
    ) async {
      await _pumpPage(tester, 0);
      final atZero = tester.getCenter(_thumbFinder()).dx;
      await _pumpPage(tester, 1);
      final atOne = tester.getCenter(_thumbFinder()).dx;
      await _pumpPage(tester, 2);
      final atTwo = tester.getCenter(_thumbFinder()).dx;

      expect(atZero, lessThan(atOne));
      expect(atOne, lessThan(atTwo));

      // ค่ากลาง ๆ (เช่นตอนปัดค้าง) หัวหมุดต้องอยู่ระหว่างหน้า ไม่กระโดด
      await _pumpPage(tester, 0.5);
      final atHalf = tester.getCenter(_thumbFinder()).dx;
      expect(atHalf, closeTo((atZero + atOne) / 2, 1));
    });

    testWidgets('puts the arrows on the same line as the ruler', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 1);

      final rulerRect = tester.getRect(_rulerFinder());
      final leftArrow = tester.getRect(
        find.byTooltip('ไปหน้าสนาม: จองสนามเล่นกีฬา'),
      );
      final rightArrow = tester.getRect(
        find.byTooltip('ไปหน้าโค้ช: หาโค้ช/เทรนเนอร์'),
      );

      // ลูกศรอยู่บรรทัดเดียวกับ ruler (กึ่งกลางแนวตั้งตรงกัน)
      expect(leftArrow.center.dy, closeTo(rulerRect.center.dy, 0.5));
      expect(rightArrow.center.dy, closeTo(rulerRect.center.dy, 0.5));
      // และอยู่คนละข้างของ ruler
      expect(leftArrow.right, lessThanOrEqualTo(rulerRect.left + 0.5));
      expect(rightArrow.left, greaterThanOrEqualTo(rulerRect.right - 0.5));
    });

    testWidgets('snaps page by page while dragging the ruler', (tester) async {
      final hostKey = GlobalKey<_IndicatorHostState>();
      await _pumpIndicator(tester, currentPage: 0, hostKey: hostKey);

      final rulerRect = tester.getRect(_rulerFinder());
      // เริ่มจากฝั่งซ้าย (หน้า 0) แล้วลากผ่านกึ่งกลาง (หน้า 1) ไปสุดขวา (หน้า 2)
      // เป็นขั้น ๆ ให้ snap ทีละหน้า ไม่ใช่ครั้งเดียวตอนปล่อยนิ้ว
      final gesture = await tester.startGesture(
        Offset(rulerRect.left + 12, rulerRect.center.dy),
      );
      await gesture.moveTo(Offset(rulerRect.center.dx - 40, rulerRect.center.dy));
      await tester.pump();
      await gesture.moveTo(Offset(rulerRect.center.dx, rulerRect.center.dy));
      await tester.pump();
      await gesture.moveTo(Offset(rulerRect.right - 12, rulerRect.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(hostKey.currentState!.scrubbed, containsAllInOrder([1, 2]));
      // ใช้ scrub สด ๆ ระหว่างลาก จึงไม่ commit ซ้ำตอนปล่อยนิ้ว
      expect(hostKey.currentState!.selected, isEmpty);
      expect(find.text('หาโค้ช/เทรนเนอร์'), findsOneWidget);
    });

    testWidgets('selects the nearest page when tapping the ruler', (
      tester,
    ) async {
      final hostKey = GlobalKey<_IndicatorHostState>();
      await _pumpIndicator(tester, currentPage: 0, hostKey: hostKey);

      final rulerRect = tester.getRect(_rulerFinder());
      await tester.tapAt(Offset(rulerRect.right - 6, rulerRect.center.dy));
      await tester.pumpAndSettle();

      expect(hostKey.currentState!.selected, [2]);
      expect(find.text('หาโค้ช/เทรนเนอร์'), findsOneWidget);
    });
  });

  group('SportsHubPageIndicator button shake', () {
    testWidgets('shakes the newly selected button and then settles', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 0);
      expect(_shakeFinder(), findsNothing);

      await tester.tap(find.text('โค้ช'));
      await tester.pump();
      // เขย่าปุ่มที่เพิ่งถูกเลือก และเริ่มจากนิ่ง (มุม 0) ก่อน
      expect(
        find.ancestor(of: find.text('โค้ช'), matching: _shakeFinder()),
        findsOneWidget,
      );
      expect(_shakeAngle(tester).abs(), lessThan(0.001));

      await tester.pump(const Duration(milliseconds: 60));
      expect(_shakeAngle(tester).abs(), greaterThan(0.01));

      await tester.pumpAndSettle();
      expect(_shakeAngle(tester).abs(), lessThan(0.001));
    });

    testWidgets('does not shake until the page settles on an integer', (
      tester,
    ) async {
      await _pumpPageOnce(tester, 0);
      // ค้างอยู่ระหว่างทาง (ปัดค้าง) — ยังไม่เข้าที่จึงยังไม่เขย่า
      await _pumpPageOnce(tester, 1.4);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_shakeFinder(), findsNothing);

      // เข้าที่หน้า 2 แล้ว — เริ่มเขย่า
      await _pumpPageOnce(tester, 2);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_shakeAngle(tester).abs(), greaterThan(0.01));

      await tester.pumpAndSettle();
    });

    testWidgets('does not shake when the page does not change', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 1);
      await tester.tap(find.text('ก๊วน'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_shakeFinder(), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('does not shake mid-drag, only after the ruler is released', (
      tester,
    ) async {
      await _pumpIndicator(tester, currentPage: 0);

      final rulerRect = tester.getRect(_rulerFinder());
      final gesture = await tester.startGesture(rulerRect.center);
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      // ระหว่างลาก (snap ไปหน้า 2 แล้ว) ต้องยังไม่เขย่า
      expect(_shakeFinder(), findsNothing);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_shakeAngle(tester).abs(), greaterThan(0.01));

      await tester.pumpAndSettle();
    });
  });
}

Finder _pillOpacity() => find.ancestor(
  of: find.byType(LitGlassSurface),
  matching: find.byType(Opacity),
);
