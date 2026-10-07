import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/emergency_top_bar.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/floating_back_button.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/trending_category_filter_button.dart';

Widget _harness({
  bool showCategoryFilter = true,
  String? trailingLabel,
  IconData? trailingIcon,
  VoidCallback? onTrailingTap,
  VoidCallback? onFilterTap,
  String? categoryLabel,
  VoidCallback? onCategoryLabelTap,
  Widget? videoControls,
  VoidCallback? onBackTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EmergencyTopBar(
        onBackTap: onBackTap ?? () {},
        videoControls: videoControls,
        showCategoryFilter: showCategoryFilter,
        selectedCategoryCount: 1,
        onCategoryFilterTap: onFilterTap ?? () {},
        trailingLabel: trailingLabel,
        trailingIcon: trailingIcon,
        onTrailingTap: onTrailingTap,
        categoryLabel: categoryLabel,
        onCategoryLabelTap: onCategoryLabelTap,
      ),
    ),
  );
}

void main() {
  group('EmergencyTopBar — map playback actions (Phase 22 §22.14)', () {
    testWidgets('ซ่อนตัวกรอง; back คืนแผนที่ และปิดกลับ Emergency ปกติ', (
      tester,
    ) async {
      var backTaps = 0;
      var closeTaps = 0;
      await tester.pumpWidget(
        _harness(
          showCategoryFilter: false,
          trailingLabel: 'ปิด',
          trailingIcon: Icons.close_rounded,
          onBackTap: () => backTaps++,
          onTrailingTap: () => closeTaps++,
        ),
      );

      expect(find.byType(TrendingCategoryFilterButton), findsNothing);
      expect(find.text('ปิด'), findsNothing);
      expect(find.bySemanticsLabel('ปิด'), findsOneWidget);
      final closeButton = find.ancestor(
        of: find.byIcon(Icons.close_rounded),
        matching: find.byType(FloatingBackButton),
      );
      expect(tester.getSize(closeButton), const Size(42, 42));
      final closeContainer = find.descendant(
        of: closeButton,
        matching: find.byType(Container),
      );
      final decoration =
          tester.widget<Container>(closeContainer.first).decoration!
              as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pump();
      expect(backTaps, 1);
      expect(closeTaps, 0);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(backTaps, 1);
      expect(closeTaps, 1);
    });

    testWidgets('ไม่มี trailing → เหลือปุ่มตัวกรองตามเดิม', (tester) async {
      await tester.pumpWidget(_harness());
      expect(find.byType(TrendingCategoryFilterButton), findsOneWidget);
      expect(find.text('เลือกเหตุการณ์อื่น'), findsNothing);
    });

    testWidgets('ปุ่มสถานการณ์เปิด category picker แทนปุ่ม "เปลี่ยน" แยก', (
      tester,
    ) async {
      var pickerTaps = 0;
      await tester.pumpWidget(
        _harness(
          showCategoryFilter: false,
          categoryLabel: 'สถานการณ์: น้ำท่วม',
          onCategoryLabelTap: () => pickerTaps++,
        ),
      );

      expect(find.byType(TrendingCategoryFilterButton), findsNothing);
      expect(find.text('สถานการณ์: น้ำท่วม'), findsOneWidget);
      expect(find.text('เปลี่ยน'), findsNothing);
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
      expect(
        find.bySemanticsLabel('เปลี่ยนประเภทเหตุ: สถานการณ์: น้ำท่วม'),
        findsOneWidget,
      );

      await tester.tap(find.text('สถานการณ์: น้ำท่วม'));
      await tester.pump();
      expect(pickerTaps, 1);
    });

    testWidgets('ป้ายยาวไม่ล้นที่ 320dp (ย่อด้วย ellipsis)', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _harness(trailingLabel: 'เปลี่ยนประเภทเหตุ', onTrailingTap: () {}),
      );

      expect(tester.takeException(), isNull);
      final pillRect = tester.getRect(find.text('เปลี่ยนประเภทเหตุ'));
      expect(pillRect.right, lessThanOrEqualTo(320));
    });

    testWidgets(
      '320dp: เครื่องมือวิดีโอ + ปุ่มปิด map-return ไม่ล้นหรือทับกัน',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _harness(
            showCategoryFilter: false,
            videoControls: const SizedBox(
              width: 160,
              height: 42,
              child: Text('controls'),
            ),
            trailingLabel: 'ปิด',
            trailingIcon: Icons.close_rounded,
            onTrailingTap: () {},
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(TrendingCategoryFilterButton), findsNothing);
        final controlsRect = tester.getRect(find.text('controls'));
        final closeButton = find.ancestor(
          of: find.byIcon(Icons.close_rounded),
          matching: find.byType(FloatingBackButton),
        );
        final closeRect = tester.getRect(closeButton);
        expect(controlsRect.right, lessThanOrEqualTo(closeRect.left));
        expect(closeRect.right, lessThanOrEqualTo(320));
      },
    );
  });

  group('EmergencyTopBar — ป้ายกำกับหมวดของแผนที่ (Phase 22 §22.3.4)', () {
    testWidgets('categoryLabel เป็นปุ่มเรียก dialog และแทนปุ่มเปลี่ยนแยก', (
      tester,
    ) async {
      var pickerTaps = 0;
      await tester.pumpWidget(
        _harness(
          showCategoryFilter: false,
          categoryLabel: 'สถานการณ์: ฝุ่นละออง หมอกควัน',
          onCategoryLabelTap: () => pickerTaps++,
        ),
      );

      expect(find.text('สถานการณ์: ฝุ่นละออง หมอกควัน'), findsOneWidget);
      expect(find.text('เปลี่ยน'), findsNothing);
      expect(find.byType(TrendingCategoryFilterButton), findsNothing);
      expect(find.byIcon(Icons.map_outlined), findsOneWidget);
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);

      await tester.tap(find.text('สถานการณ์: ฝุ่นละออง หมอกควัน'));
      await tester.pump();
      expect(pickerTaps, 1);
    });

    testWidgets('ไม่มี categoryLabel → ไม่มีป้ายหมวด', (tester) async {
      await tester.pumpWidget(
        _harness(
          showCategoryFilter: false,
          trailingLabel: 'ปิด',
          onTrailingTap: () {},
        ),
      );

      expect(find.textContaining('สถานการณ์:'), findsNothing);
      expect(find.byIcon(Icons.map_outlined), findsNothing);
    });

    testWidgets('ปุ่มหมวดยาวไม่ล้นที่ 320dp และไม่มีปุ่มเปลี่ยนแยก', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _harness(
          showCategoryFilter: false,
          categoryLabel: 'สถานการณ์: อุบัติเหตุจราจรและภัยพิบัติทางธรรมชาติ',
          onCategoryLabelTap: () {},
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('เปลี่ยน'), findsNothing);
      final categoryRect = tester.getRect(
        find.text('สถานการณ์: อุบัติเหตุจราจรและภัยพิบัติทางธรรมชาติ'),
      );
      expect(categoryRect.right, lessThanOrEqualTo(320));
    });
  });
}
