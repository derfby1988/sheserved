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
}
