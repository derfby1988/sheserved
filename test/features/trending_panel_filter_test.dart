import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/models/video_models.dart';
import 'package:sheserved/features/video/presentation/pages/trending_category_filter_policy.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/trending_panel_widget.dart';

Video _video(String id, {String? categoryId}) => Video(
  id: id,
  userId: 'u1',
  type: VideoType.emergency,
  title: 'Emergency Incident',
  status: VideoStatus.ready,
  categoryId: categoryId,
  createdAt: DateTime(2026, 10, 5, 8),
);

/// หมายเหตุ: ปุ่มเปิด sheet ตัวกรองย้ายไปอยู่แถวบนสุด (`EmergencyTopBar`) แล้ว —
/// เทสต์ของปุ่ม/sheet อยู่ใน `emergency_top_bar_test.dart`; panel เหลือหน้าที่
/// แสดงผล empty state ของ filter ที่ commit ไว้
Widget _panel({
  List<Video>? videos,
  Set<String> selectedCategoryIds = const {},
  Future<bool> Function(Set<String>)? onApplyCategoryFilter,
  bool isSharedFocusMode = false,
  VoidCallback? onExitSharedFocus,
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
            selectedCategoryIds: selectedCategoryIds,
            onApplyCategoryFilter: onApplyCategoryFilter,
            isSharedFocusMode: isSharedFocusMode,
            onExitSharedFocus: onExitSharedFocus,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Trending category filter playback policy', () {
    test('map playback temporarily scopes all cards to the map category', () {
      final committed = {'cat-accident'};
      final activeScope = trendingCategoryIdsForActiveScope(
        committedCategoryIds: committed,
        incidentMapCategoryId: 'cat-flood',
        isIncidentMapPlaybackContext: true,
        missionFilterSuspended: false,
      );

      expect(activeScope, {'cat-flood'});
      expect(committed, {'cat-accident'});
      expect(
        filterTrendingVideosByCategoryIds([
          _video('flood-1', categoryId: 'cat-flood'),
          _video('accident', categoryId: 'cat-accident'),
          _video('flood-2', categoryId: 'cat-flood'),
          _video('missing-category'),
        ], activeScope).map((video) => video.id).toList(),
        ['flood-1', 'flood-2'],
      );
    });

    test(
      'normal emergency restores committed scope; mission lock suspends it',
      () {
        expect(
          trendingCategoryIdsForActiveScope(
            committedCategoryIds: const {'cat-accident', 'cat-flood'},
            incidentMapCategoryId: 'cat-dust',
            isIncidentMapPlaybackContext: false,
            missionFilterSuspended: false,
          ),
          {'cat-accident', 'cat-flood'},
        );
        expect(
          trendingCategoryIdsForActiveScope(
            committedCategoryIds: const {'cat-accident'},
            incidentMapCategoryId: 'cat-dust',
            isIncidentMapPlaybackContext: true,
            missionFilterSuspended: true,
          ),
          isEmpty,
        );
      },
    );

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

    test(
      'map playback context deactivates during mission lock but is kept',
      () {
        bool active({
          bool inMapMode = false,
          String? pinned = 'v1',
          bool suspended = false,
        }) => isIncidentMapPlaybackContextActive(
          isIncidentMapMode: inMapMode,
          pinnedVideoId: pinned,
          missionFilterSuspended: suspended,
        );

        expect(active(), isTrue);
        expect(active(inMapMode: true), isFalse);
        expect(active(pinned: null), isFalse);
        // §22.3 ข้อ 7 — suspension ปิด context ชั่วคราวโดยไม่ลบ pin/session
        expect(active(suspended: true), isFalse);
        expect(active(suspended: true, pinned: null), isFalse);
      },
    );
  });

  group('TrendingPanelWidget — Phase 20 category filter', () {
    testWidgets('header keeps the label without a filter icon', (tester) async {
      await tester.pumpWidget(_panel());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('ยอดนิยม'), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsNothing);
    });

    testWidgets('filtered empty state offers a clear action', (tester) async {
      Set<String>? applied;
      await tester.pumpWidget(
        _panel(
          videos: const [],
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

    testWidgets('no empty-filter message while the filter is empty', (
      tester,
    ) async {
      await tester.pumpWidget(_panel(videos: const []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('ไม่พบเหตุในประเภทที่เลือก'), findsNothing);
      expect(find.text('ล้างตัวกรอง'), findsNothing);
      expect(find.text('ไม่มีข้อมูล'), findsOneWidget);
    });
  });

  group('Phase 23 shared-incident focus mode', () {
    test('focus list contains only the shared incident', () {
      final shared = _video('shared', categoryId: 'cat-flood');
      final other = _video('other', categoryId: 'cat-accident');

      // เหตุการณ์ที่แชร์โหลดเป็น _currentVideo → inject เป็นการ์ดเดียวเสมอ
      expect(
        sharedFocusTrendingVideos(
          focusVideoId: 'shared',
          currentVideo: shared,
          trendingVideos: [other, shared],
        ).map((video) => video.id).toList(),
        ['shared'],
      );

      // ยังโหลดไม่เสร็จ → fallback หาใน trending list
      expect(
        sharedFocusTrendingVideos(
          focusVideoId: 'shared',
          currentVideo: null,
          trendingVideos: [other, shared],
        ).map((video) => video.id).toList(),
        ['shared'],
      );

      // การ์ดที่แชร์ไม่อยู่ใน trending page ปัจจุบัน → ลิสต์ว่างจนกว่าจะโหลด
      expect(
        sharedFocusTrendingVideos(
          focusVideoId: 'missing',
          currentVideo: null,
          trendingVideos: [other],
        ),
        isEmpty,
      );
    });

    testWidgets('"ดูเหตุการณ์ทั้งหมด" appears only in focus mode and exits', (
      tester,
    ) async {
      var exited = false;
      await tester.pumpWidget(
        _panel(isSharedFocusMode: true, onExitSharedFocus: () => exited = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('ยอดนิยม'), findsOneWidget);
      expect(find.text('ดูเหตุการณ์ทั้งหมด'), findsOneWidget);

      await tester.tap(find.text('ดูเหตุการณ์ทั้งหมด'));
      await tester.pump();
      expect(exited, isTrue);
    });

    testWidgets('"ดูเหตุการณ์ทั้งหมด" hidden in normal mode', (tester) async {
      await tester.pumpWidget(_panel());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('ยอดนิยม'), findsOneWidget);
      expect(find.text('ดูเหตุการณ์ทั้งหมด'), findsNothing);
    });
  });
}
