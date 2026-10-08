import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/donation/models/donation_models.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/trending_category_filter_sheet.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

const _categories = [
  DonationCategory(
    id: 'cat-accident',
    name: 'อุบัติเหตุ',
    isEmergency: true,
    displayOrder: 1,
  ),
  DonationCategory(
    id: 'cat-flood',
    name: 'น้ำท่วม',
    isEmergency: true,
    displayOrder: 2,
  ),
];

Widget _harness({
  Set<String> initialSelectedIds = const {},
  Future<bool> Function(Set<String>)? onApply,
  void Function(DonationCategory category)? onOpenIncidentMap,
  ValueChanged<Set<String>>? onDraftChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => TrendingCategoryFilterSheet.show(
              context,
              categories: _categories,
              initialSelectedIds: initialSelectedIds,
              suspensionSignal: ValueNotifier<bool>(false),
              onApply: onApply,
              onOpenIncidentMap: onOpenIncidentMap,
              onDraftChanged: onDraftChanged,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester, Widget harness) async {
  await tester.pumpWidget(harness);
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  group(
    'TrendingCategoryFilterSheet — ปุ่ม "แผนที่เกิดเหตุ" (Phase 22 §22.1)',
    () {
      testWidgets('แสดงปุ่มใต้ทุกหมวดเมื่อ gate เปิด (callback ไม่ null)', (
        tester,
      ) async {
        await _openSheet(tester, _harness(onOpenIncidentMap: (_) {}));

        expect(find.text('แผนที่เกิดเหตุ'), findsNWidgets(2));
        expect(find.byIcon(Icons.map_outlined), findsNWidgets(2));
      });

      testWidgets('gate ปิด (callback null) → ไม่มีปุ่ม', (tester) async {
        await _openSheet(tester, _harness());
        expect(find.text('แผนที่เกิดเหตุ'), findsNothing);
      });

      testWidgets('ใช้ตัวอักษรเล็กลงและคืนพื้นที่ให้ชื่อหมวด (§22.15)', (
        tester,
      ) async {
        await _openSheet(tester, _harness(onOpenIncidentMap: (_) {}));

        final pill = tester.widget<NeumorphicPillButton>(
          find
              .ancestor(
                of: find.text('แผนที่เกิดเหตุ'),
                matching: find.byType(NeumorphicPillButton),
              )
              .first,
        );
        expect(pill.fontSize, lessThanOrEqualTo(11));
        expect(pill.iconSize, lessThanOrEqualTo(13));
        expect(pill.minWidth, lessThanOrEqualTo(100));
        expect(pill.padding, const EdgeInsets.symmetric(horizontal: 8));
      });

      testWidgets('390dp: แคปซูลเล็กลงและชื่อหมวดยังมีพื้นที่พออ่าน', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _openSheet(tester, _harness(onOpenIncidentMap: (_) {}));

        expect(tester.takeException(), isNull);
        final pillWidth = tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('แผนที่เกิดเหตุ'),
                    matching: find.byType(NeumorphicPillButton),
                  )
                  .first,
            )
            .width;
        final titleWidth = tester.getSize(find.text('อุบัติเหตุ')).width;
        // หมายเหตุ: ใน widget test ฟอนต์กว้างเท่า fontSize ต่อตัวอักษร จึงเป็น
        // เคสที่แคบกว่าจอจริง (จอจริงThai font ~0.55em); แคปซูลเดิม
        // (fontSize 12/minWidth 132/padding 10) กว้าง ~197 และเหลือชื่อ ~59
        expect(pillWidth, lessThanOrEqualTo(195));
        expect(titleWidth, greaterThanOrEqualTo(60));
      });

      testWidgets('กดปุ่มของหมวดใด → callback ได้รับหมวดนั้นเพียงหมวดเดียว '
          'และ sheet ปิดโดยไม่เรียก onApply', (tester) async {
        final opened = <String>[];
        var applyCalls = 0;
        await _openSheet(
          tester,
          _harness(
            initialSelectedIds: const {'cat-flood'},
            onApply: (_) async {
              applyCalls++;
              return true;
            },
            onOpenIncidentMap: (category) => opened.add(category.id),
          ),
        );

        // ปุ่มใต้หมวด "น้ำท่วม" = ปุ่มลำดับที่ 2
        await tester.tap(find.text('แผนที่เกิดเหตุ').at(1));
        await tester.pumpAndSettle();

        expect(opened, ['cat-flood']);
        expect(applyCalls, 0);
        expect(find.byType(TrendingCategoryFilterSheet), findsNothing);
      });

      testWidgets('ขณะ _applying ปุ่มแผนที่ถูก disable พร้อม footer', (
        tester,
      ) async {
        // onApply ค้าง → _applying ค้าง true
        await _openSheet(
          tester,
          _harness(
            onApply: (_) => Completer<bool>().future,
            onOpenIncidentMap: (_) {},
          ),
        );

        await tester.tap(find.text('แสดงผล'));
        await tester.pump();

        final mapPill = tester.widget<NeumorphicPillButton>(
          find
              .ancestor(
                of: find.text('แผนที่เกิดเหตุ'),
                matching: find.byType(NeumorphicPillButton),
              )
              .first,
        );
        expect(mapPill.onPressed, isNull); // disabled ขณะ _applying
      });
    },
  );

  group('TrendingCategoryFilterSheet — onDraftChanged (Phase 22 §22.13)', () {
    testWidgets(
      'แจ้ง draft เริ่มต้นตอนเปิด แล้วแจ้งใหม่ทุกครั้งที่สลับ toggle',
      (tester) async {
        final drafts = <Set<String>>[];
        await _openSheet(
          tester,
          _harness(
            initialSelectedIds: const {'cat-flood'},
            onDraftChanged: drafts.add,
          ),
        );

        expect(drafts, isNotEmpty);
        expect(drafts.first, {'cat-flood'});

        // แตะแถวหมวดแรก = toggle (InkWell ครอบทั้งแถว)
        await tester.tap(find.text('อุบัติเหตุ'));
        await tester.pump();

        expect(drafts.last, {'cat-flood', 'cat-accident'});
      },
    );

    testWidgets(
      'เปิด sheet ด้วย draft ที่ค้างไว้ → draft เริ่มต้นตรงกับที่ส่งมา',
      (tester) async {
        final drafts = <Set<String>>[];
        await _openSheet(
          tester,
          _harness(
            initialSelectedIds: const {'cat-accident', 'cat-flood'},
            onDraftChanged: drafts.add,
          ),
        );

        expect(drafts.first, {'cat-accident', 'cat-flood'});
      },
    );
  });
}
