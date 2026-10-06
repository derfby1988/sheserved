import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/donation/models/donation_models.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/emergency_top_bar.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/floating_back_button.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/trending_category_filter_button.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/trending_category_filter_sheet.dart';

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
  DonationCategory(
    id: 'cat-fire',
    name: 'ไฟไหม้',
    isEmergency: true,
    displayOrder: 3,
  ),
];

/// ความกว้างจริงของ `GlassmorphismVideoControls` หลังลด padding เป็น 12
/// (4 ปุ่ม x 48 + 3 divider x 5 + padding 8) — ใช้เป็น stand-in ในเทสต์เพราะ
/// widget จริงต้องมี VideoPlayerController ที่ initialized ก่อนจึงมีขนาด
const double _videoControlsWidth = 215;
const Key _videoControlsKey = ValueKey('test-video-controls');

/// แถวบนสุด + การเปิด sheet แบบเดียวกับ `_openTrendingCategoryFilterSheet`
/// ในหน้า emergency live (categories/selection/suspension/onApply ชุดเดียวกัน)
Widget _harness({
  double width = 390,
  bool withVideoControls = true,
  bool showCategoryFilter = true,
  int selectedCount = 0,
  Set<String> initialSelectedIds = const {},
  Future<bool> Function(Set<String>)? onApply,
  ValueListenable<bool>? suspensionSignal,
  VoidCallback? onBackTap,
  VoidCallback? onFilterTap,
  bool backButtonVisible = true,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: Builder(
          builder: (context) => EmergencyTopBar(
            onBackTap: onBackTap ?? () {},
            backButtonVisible: backButtonVisible,
            videoControls: withVideoControls
                ? const SizedBox(
                    key: _videoControlsKey,
                    width: _videoControlsWidth,
                    height: 44,
                    child: ColoredBox(color: Colors.black45),
                  )
                : null,
            showCategoryFilter: showCategoryFilter,
            selectedCategoryCount: selectedCount,
            onCategoryFilterTap:
                onFilterTap ??
                () => TrendingCategoryFilterSheet.show(
                  context,
                  categories: _categories,
                  initialSelectedIds: initialSelectedIds,
                  suspensionSignal:
                      suspensionSignal ?? ValueNotifier<bool>(false),
                  onApply: onApply,
                ),
          ),
        ),
      ),
    ),
  );
}

/// ตั้งความกว้างจอให้เท่ากับความกว้างของแถว เพื่อให้พิกัดในเทสต์เป็นพิกัดจริง
/// บนจอ (ปุ่มตัวกรองต้องชิดขวาของจอจริง ไม่ใช่แค่ขวาของ widget)
Future<void> _pumpTopBar(
  WidgetTester tester, {
  double width = 390,
  bool withVideoControls = true,
  bool showCategoryFilter = true,
  int selectedCount = 0,
  Set<String> initialSelectedIds = const {},
  Future<bool> Function(Set<String>)? onApply,
  ValueListenable<bool>? suspensionSignal,
  VoidCallback? onBackTap,
  VoidCallback? onFilterTap,
}) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _harness(
      width: width,
      withVideoControls: withVideoControls,
      showCategoryFilter: showCategoryFilter,
      selectedCount: selectedCount,
      initialSelectedIds: initialSelectedIds,
      onApply: onApply,
      suspensionSignal: suspensionSignal,
      onBackTap: onBackTap,
      onFilterTap: onFilterTap,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  group('EmergencyTopBar layout', () {
    testWidgets(
      'keeps back button, video controls and filter button on one row at 320dp',
      (tester) async {
        await _pumpTopBar(tester, width: 320);

        expect(tester.takeException(), isNull);
        expect(find.byKey(_videoControlsKey), findsOneWidget);
        expect(find.byType(TrendingCategoryFilterButton), findsOneWidget);

        // เครื่องมือวิดีโอยังได้ความกว้างตามเนื้อหา (ไม่ถูกบีบจนต้องเลื่อน)
        expect(
          tester.getSize(find.byKey(_videoControlsKey)).width,
          _videoControlsWidth,
        );
        // ปุ่มย้อนกลับชิดซ้ายของจอ
        expect(
          tester.getRect(find.byType(FloatingBackButton)).left,
          moreOrLessEquals(0, epsilon: 0.5),
        );
      },
    );

    testWidgets(
      'filter button sits flush right of the screen, right of the controls',
      (tester) async {
        await _pumpTopBar(tester, width: 375);

        final filterRect = tester.getRect(
          find.byType(TrendingCategoryFilterButton),
        );
        final controlsRect = tester.getRect(find.byKey(_videoControlsKey));
        expect(filterRect.right, moreOrLessEquals(375, epsilon: 0.5));
        expect(filterRect.left, greaterThan(controlsRect.right));
      },
    );

    testWidgets('stays flush right when no video controls are shown', (
      tester,
    ) async {
      await _pumpTopBar(tester, width: 320, withVideoControls: false);

      expect(tester.takeException(), isNull);
      final filterRect = tester.getRect(
        find.byType(TrendingCategoryFilterButton),
      );
      expect(filterRect.right, moreOrLessEquals(320, epsilon: 0.5));
    });

    testWidgets('hides the filter button when the filter is unavailable', (
      tester,
    ) async {
      await _pumpTopBar(tester, showCategoryFilter: false);

      expect(find.byType(TrendingCategoryFilterButton), findsNothing);
      expect(find.byIcon(Icons.tune), findsNothing);
      expect(find.byKey(_videoControlsKey), findsOneWidget);
    });

    testWidgets('shows the committed selection count on the badge', (
      tester,
    ) async {
      await _pumpTopBar(tester, selectedCount: 2);

      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('wires back and filter taps to their callbacks', (
      tester,
    ) async {
      var backTaps = 0;
      var filterTaps = 0;
      await _pumpTopBar(
        tester,
        onBackTap: () => backTaps++,
        onFilterTap: () => filterTaps++,
      );

      await tester.tap(find.byIcon(Icons.tune));
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pump();

      expect(filterTaps, 1);
      expect(backTaps, 1);
    });
  });

  group('EmergencyTopBar — trending category filter sheet', () {
    testWidgets('opens with draft multi-select and applies committed ids', (
      tester,
    ) async {
      Set<String>? applied;
      await _pumpTopBar(
        tester,
        selectedCount: 1,
        initialSelectedIds: const {'cat-flood'},
        onApply: (ids) async {
          applied = ids;
          return true;
        },
      );

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(TrendingCategoryFilterSheet), findsOneWidget);
      expect(find.text('อุบัติเหตุ'), findsOneWidget);
      expect(find.text('น้ำท่วม'), findsOneWidget);
      expect(find.text('ไฟไหม้'), findsOneWidget);

      await tester.tap(find.text('ไฟไหม้'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('แสดงผล'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(applied, {'cat-flood', 'cat-fire'});
      expect(find.byType(TrendingCategoryFilterSheet), findsNothing);
    });

    testWidgets('footer replaces cancel with an orange clear-all that applies '
        'an empty filter', (tester) async {
      Set<String>? applied;
      await _pumpTopBar(
        tester,
        selectedCount: 1,
        initialSelectedIds: const {'cat-flood'},
        onApply: (ids) async {
          applied = ids;
          return true;
        },
      );

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      // ไม่มีปุ่มยกเลิก และไม่มีปุ่มล้างใน header อีกแล้ว
      expect(find.text('ยกเลิก'), findsNothing);
      expect(find.text('ล้างทั้งหมด'), findsNothing);
      expect(find.text('ล้างค่าทั้งหมด'), findsOneWidget);

      // ข้อความปุ่มเป็นสีส้มเดียวกับป้าย "ยอดนิยม"
      final label = tester.widget<Text>(find.text('ล้างค่าทั้งหมด'));
      expect(label.style?.color, const Color(0xFFFF6B35));

      await tester.tap(find.text('ล้างค่าทั้งหมด'));
      await tester.pumpAndSettle();

      expect(applied, isEmpty);
      expect(find.byType(TrendingCategoryFilterSheet), findsNothing);
    });

    testWidgets(
      'closing the sheet without applying keeps the draft untouched',
      (tester) async {
        var applyCalls = 0;
        await _pumpTopBar(
          tester,
          initialSelectedIds: const {'cat-flood'},
          onApply: (_) async {
            applyCalls++;
            return true;
          },
        );

        await tester.tap(find.byIcon(Icons.tune));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await tester.tap(find.text('ไฟไหม้'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));

        // ปิดด้วยปุ่ม X มุมขวาบน (ไม่มีปุ่มยกเลิกแล้ว)
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        expect(find.byType(TrendingCategoryFilterSheet), findsNothing);
        expect(applyCalls, 0);
      },
    );

    testWidgets('failed apply keeps the sheet open with a retry error', (
      tester,
    ) async {
      await _pumpTopBar(tester, onApply: (_) async => false);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('น้ำท่วม'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('แสดงผล'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byType(TrendingCategoryFilterSheet), findsOneWidget);
      expect(
        find.text('โหลดรายการไม่สำเร็จ — กรุณาลองอีกครั้ง'),
        findsOneWidget,
      );
    });

    testWidgets('suspension signal closes the sheet without applying', (
      tester,
    ) async {
      final signal = ValueNotifier<bool>(false);
      var applyCalls = 0;
      await _pumpTopBar(
        tester,
        suspensionSignal: signal,
        onApply: (_) async {
          applyCalls++;
          return true;
        },
      );

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(TrendingCategoryFilterSheet), findsOneWidget);

      await tester.tap(find.text('ไฟไหม้'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      signal.value = true;
      // route ของ modal sheet ต้องรอ animation ปิดจบก่อนจึงถูกถอดออกจาก tree
      await tester.pumpAndSettle();

      expect(find.byType(TrendingCategoryFilterSheet), findsNothing);
      expect(applyCalls, 0);
    });
  });
}
