import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/emergency_top_bar.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/trending_category_filter_button.dart';

Widget _harness({
  bool showCategoryFilter = true,
  String? trailingLabel,
  VoidCallback? onTrailingTap,
  VoidCallback? onFilterTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EmergencyTopBar(
        onBackTap: () {},
        showCategoryFilter: showCategoryFilter,
        selectedCategoryCount: 1,
        onCategoryFilterTap: onFilterTap ?? () {},
        trailingLabel: trailingLabel,
        onTrailingTap: onTrailingTap,
      ),
    ),
  );
}

void main() {
  group('EmergencyTopBar — trailing action (Phase 22 §22.1)', () {
    testWidgets('trailingLabel แทนที่ปุ่มตัวกรองในตำแหน่งเดียวกัน', (
      tester,
    ) async {
      var taps = 0;
      var filterTaps = 0;
      await tester.pumpWidget(
        _harness(
          trailingLabel: 'เลือกเหตุการณ์อื่น',
          onTrailingTap: () => taps++,
          onFilterTap: () => filterTaps++,
        ),
      );

      expect(find.text('เลือกเหตุการณ์อื่น'), findsOneWidget);
      expect(find.byType(TrendingCategoryFilterButton), findsNothing);

      await tester.tap(find.text('เลือกเหตุการณ์อื่น'));
      await tester.pump();
      expect(taps, 1);
      expect(filterTaps, 0);
    });

    testWidgets('ไม่มี trailing → กลับไปแสดงปุ่มตัวกรองตามเดิม', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      expect(find.byType(TrendingCategoryFilterButton), findsOneWidget);
      expect(find.text('เลือกเหตุการณ์อื่น'), findsNothing);
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
  });
}
