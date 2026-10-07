import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/donation/models/donation_models.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/incident_map/incident_category_picker_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

/// หมวดฉุกเฉินจากตารางจริง (`donation_categories` is_emergency = true,
/// display_order asc) — เรียงแบบเดียวกับ `TrendingCategoryFilterSheet`
const _categories = [
  DonationCategory(
    id: 'cat-dust',
    name: 'ฝุ่นละออง หมอกควัน',
    isEmergency: true,
    displayOrder: 1,
  ),
  DonationCategory(
    id: 'cat-accident',
    name: 'อุบัติเหตุ',
    isEmergency: true,
    displayOrder: 2,
  ),
  DonationCategory(
    id: 'cat-flood',
    name: 'น้ำท่วม',
    isEmergency: true,
    displayOrder: 3,
  ),
];

Widget _harness({
  List<DonationCategory> categories = _categories,
  String? currentCategoryId,
  void Function(DonationCategory? picked)? onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              final picked = await IncidentCategoryPickerDialog.show(
                context,
                categories: categories,
                currentCategoryId: currentCategoryId,
              );
              onResult?.call(picked);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester, Widget harness) async {
  await tester.pumpWidget(harness);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('IncidentCategoryPickerDialog (Phase 22 §22.13)', () {
    testWidgets('แสดงปุ่มทุกหมวดตามลำดับที่ส่งมา (ลำดับเดียวกับ sheet)', (
      tester,
    ) async {
      await _openDialog(tester, _harness());

      expect(find.text('เปลี่ยนประเภทเหตุ'), findsOneWidget);
      expect(find.byType(GlassActionButton), findsNWidgets(3));

      final buttons = tester
          .widgetList<GlassActionButton>(find.byType(GlassActionButton))
          .toList();
      expect(buttons.map((b) => b.label).toList(), [
        'ฝุ่นละออง หมอกควัน',
        'อุบัติเหตุ',
        'น้ำท่วม',
      ]);
    });

    testWidgets('แตะหมวด → คืนหมวดนั้นและปิด dialog', (tester) async {
      DonationCategory? picked;
      await _openDialog(tester, _harness(onResult: (c) => picked = c));

      await tester.tap(find.text('น้ำท่วม'));
      await tester.pumpAndSettle();

      expect(picked?.id, 'cat-flood');
      expect(find.byType(GlassActionButton), findsNothing);
    });

    testWidgets('หมวดที่กำลังแสดงถูกทำเครื่องหมาย filled + ไอคอนแผนที่', (
      tester,
    ) async {
      await _openDialog(tester, _harness(currentCategoryId: 'cat-accident'));

      final buttons = tester
          .widgetList<GlassActionButton>(find.byType(GlassActionButton))
          .toList();
      expect(buttons.where((b) => b.isFilled).length, 1);
      expect(find.byIcon(Icons.map_outlined), findsOneWidget);

      // ไอคอนอยู่ในปุ่มของหมวดปัจจุบันเท่านั้น
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('อุบัติเหตุ'),
            matching: find.byType(GlassActionButton),
          ),
          matching: find.byIcon(Icons.map_outlined),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ไม่ส่ง currentCategoryId → ไม่มีปุ่ม filled', (tester) async {
      await _openDialog(tester, _harness());

      final buttons = tester
          .widgetList<GlassActionButton>(find.byType(GlassActionButton))
          .toList();
      expect(buttons.any((b) => b.isFilled), isFalse);
      expect(find.byIcon(Icons.map_outlined), findsNothing);
    });

    testWidgets('ไม่มีหมวด (โหลดไม่สำเร็จ) → แจ้งข้อความ ไม่มีปุ่ม', (
      tester,
    ) async {
      await _openDialog(tester, _harness(categories: const []));

      expect(
        find.textContaining('ยังโหลดรายการประเภทเหตุไม่ได้'),
        findsOneWidget,
      );
      expect(find.byType(GlassActionButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ชื่อหมวดยาวไม่ล้นจอที่ 320dp', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _openDialog(
        tester,
        _harness(
          categories: const [
            DonationCategory(
              id: 'cat-long',
              name: 'อุบัติเหตุจราจรและภัยพิบัติทางธรรมชาติ',
              isEmergency: true,
            ),
          ],
          currentCategoryId: 'cat-long',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester
            .getRect(find.text('อุบัติเหตุจราจรและภัยพิบัติทางธรรมชาติ'))
            .right,
        lessThanOrEqualTo(320),
      );
    });
  });
}
