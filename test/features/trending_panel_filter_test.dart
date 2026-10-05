import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/donation/models/donation_models.dart';
import 'package:sheserved/features/video/models/video_models.dart';
import 'package:sheserved/features/video/presentation/pages/trending_category_filter_policy.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/trending_panel_widget.dart';

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

Video _video(String id, {String? categoryId}) => Video(
  id: id,
  userId: 'u1',
  type: VideoType.emergency,
  title: 'Emergency Incident',
  status: VideoStatus.ready,
  categoryId: categoryId,
  createdAt: DateTime(2026, 10, 5, 8),
);

Widget _panel({
  List<Video>? videos,
  bool canShowCategoryFilter = false,
  Set<String> selectedCategoryIds = const {},
  Future<bool> Function(Set<String>)? onApplyCategoryFilter,
  ValueListenable<bool>? missionSuspendSignal,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 180,
          height: 400,
          child: TrendingPanelWidget(
            trendingVideos: videos ?? [_video('v1', categoryId: 'cat-flood')],
            isLoadingTrending: false,
            currentVideoId: null,
            onSwitchVideo: (_) {},
            filterCategories: _categories,
            selectedCategoryIds: selectedCategoryIds,
            canShowCategoryFilter: canShowCategoryFilter,
            onApplyCategoryFilter: onApplyCategoryFilter,
            missionSuspendSignal:
                missionSuspendSignal ?? ValueNotifier<bool>(false),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Trending category filter playback policy', () {
    test('switches to the first visible video in the selected categories', () {
      expect(
        trendingCategoryFilterAutoSwitchTarget(
          currentVideoId: 'current',
          currentVideoIdAtApply: 'current',
          currentCategoryId: 'cat-fire',
          selectedCategoryIds: const {'cat-flood', 'cat-accident'},
          visibleVideos: [
            _video('missing-category'),
            _video('not-selected', categoryId: 'cat-fire'),
            _video('first-match', categoryId: 'cat-flood'),
            _video('second-match', categoryId: 'cat-accident'),
          ],
          missionFilterSuspended: false,
        ),
        'first-match',
      );
    });

    test(
      'does not switch when current video matches the selected categories',
      () {
        expect(
          trendingCategoryFilterAutoSwitchTarget(
            currentVideoId: 'current',
            currentVideoIdAtApply: 'current',
            currentCategoryId: 'cat-flood',
            selectedCategoryIds: const {'cat-flood'},
            visibleVideos: [_video('other', categoryId: 'cat-flood')],
            missionFilterSuspended: false,
          ),
          isNull,
        );
        expect(
          trendingCategoryFilterAutoSwitchTarget(
            currentVideoId: 'current',
            currentVideoIdAtApply: 'current',
            currentCategoryId: null,
            selectedCategoryIds: const {'cat-flood'},
            visibleVideos: [
              _video('current', categoryId: 'cat-flood'),
              _video('other', categoryId: 'cat-flood'),
            ],
            missionFilterSuspended: false,
          ),
          isNull,
        );
      },
    );

    test(
      'does not switch for an empty filter, empty results, or mission lock',
      () {
        String? target({
          String? currentVideoId = 'current',
          String? currentVideoIdAtApply = 'current',
          Set<String> selected = const {'cat-flood'},
          List<Video> visible = const [],
          bool suspended = false,
        }) => trendingCategoryFilterAutoSwitchTarget(
          currentVideoId: currentVideoId,
          currentVideoIdAtApply: currentVideoIdAtApply,
          currentCategoryId: 'cat-fire',
          selectedCategoryIds: selected,
          visibleVideos: visible,
          missionFilterSuspended: suspended,
        );

        expect(
          target(
            selected: const {},
            visible: [_video('flood', categoryId: 'cat-flood')],
          ),
          isNull,
        );
        expect(target(), isNull);
        expect(target(currentVideoId: 'changed-current'), isNull);
        expect(
          target(
            visible: [_video('flood', categoryId: 'cat-flood')],
            suspended: true,
          ),
          isNull,
        );
      },
    );
  });

  group('TrendingPanelWidget — Phase 20 category filter', () {
    testWidgets('hides the filter icon when canShowCategoryFilter is false', (
      tester,
    ) async {
      await tester.pumpWidget(_panel());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byIcon(Icons.tune), findsNothing);
      expect(find.text('ยอดนิยม'), findsOneWidget);
    });

    testWidgets(
      'shows the filter icon right of the label and the selection badge count',
      (tester) async {
        await tester.pumpWidget(
          _panel(
            canShowCategoryFilter: true,
            selectedCategoryIds: const {'cat-flood', 'cat-fire'},
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.byIcon(Icons.tune), findsOneWidget);
        expect(find.text('2'), findsOneWidget);

        // ไอคอนอยู่ทางขวาของป้าย "ยอดนิยม"
        final labelX = tester.getCenter(find.text('ยอดนิยม')).dx;
        final iconX = tester.getCenter(find.byIcon(Icons.tune)).dx;
        expect(iconX, greaterThan(labelX));
      },
    );

    testWidgets('filtered empty state offers a clear action', (tester) async {
      Set<String>? applied;
      await tester.pumpWidget(
        _panel(
          videos: const [],
          canShowCategoryFilter: true,
          selectedCategoryIds: const {'cat-flood'},
          onApplyCategoryFilter: (ids) async {
            applied = ids;
            return true;
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('ไม่พบเหตุในประเภทที่เลือก'), findsOneWidget);
      await tester.tap(find.text('ล้างตัวกรอง'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(applied, isNotNull);
      expect(applied, isEmpty);
    });

    testWidgets(
      'sheet opens with draft multi-select and applies committed ids',
      (tester) async {
        Set<String>? applied;
        await tester.pumpWidget(
          _panel(
            canShowCategoryFilter: true,
            selectedCategoryIds: const {'cat-flood'},
            onApplyCategoryFilter: (ids) async {
              applied = ids;
              return true;
            },
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));

        await tester.tap(find.byIcon(Icons.tune));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text('กรองประเภทเหตุ'), findsOneWidget);
        // หมวดเรียงตามลำดับที่ส่งมา (display_order จากหน้า)
        expect(find.text('อุบัติเหตุ'), findsOneWidget);
        expect(find.text('น้ำท่วม'), findsOneWidget);
        expect(find.text('ไฟไหม้'), findsOneWidget);

        // เลือกเพิ่ม "ไฟไหม้" (น้ำท่วมถูกเลือกไว้แล้วใน draft) แล้วกดแสดงผล
        await tester.tap(find.text('ไฟไหม้'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await tester.tap(find.text('แสดงผล'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(applied, {'cat-flood', 'cat-fire'});
        // apply สำเร็จ → sheet ปิด
        expect(find.text('กรองประเภทเหตุ'), findsNothing);
      },
    );

    testWidgets('failed apply keeps the sheet open with a retry error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(
          canShowCategoryFilter: true,
          onApplyCategoryFilter: (_) async => false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      await tester.tap(find.text('น้ำท่วม'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('แสดงผล'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('กรองประเภทเหตุ'), findsOneWidget);
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
      await tester.pumpWidget(
        _panel(
          canShowCategoryFilter: true,
          missionSuspendSignal: signal,
          onApplyCategoryFilter: (_) async {
            applyCalls++;
            return true;
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('กรองประเภทเหตุ'), findsOneWidget);

      // เข้าสู่ mission lock ระหว่างเปิด sheet → ปิดโดยไม่ commit draft
      await tester.tap(find.text('ไฟไหม้'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      signal.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('กรองประเภทเหตุ'), findsNothing);
      expect(applyCalls, 0);
    });
  });
}
