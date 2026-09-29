import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/find_coach/data/coach_models.dart';
import 'package:sheserved/features/sport_club/find_coach/data/find_coach_repository.dart';
import 'package:sheserved/features/sport_club/find_coach/presentation/widgets/coach_detail_sheet.dart';
import 'package:sheserved/features/sport_club/find_coach/presentation/widgets/coach_request_sheet.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

/// Repo ที่ไม่แตะ Supabase — คืนข้อมูลว่างให้ทุก query ที่ sheet เรียกตอนเปิด.
class _EmptyRepo implements FindCoachRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return switch (invocation.memberName) {
      #getOfferingBoard => Future<List<CoachOffering>>.value(const []),
      #listPublicSlots => Future<List<CoachSlot>>.value(const []),
      #listCoachAvailability => Future<List<CoachAvailabilityWindow>>.value(
        const [],
      ),
      #listPublicLocations => Future<List<CoachTeachingLocation>>.value(
        const [],
      ),
      #getReviewSummaryV2 => Future<CoachReviewSummaryV2>.value(
        const CoachReviewSummaryV2(),
      ),
      #listReviewsV2 => Future<(List<CoachReview>, int)>.value((
        const <CoachReview>[],
        0,
      )),
      #listMyFavoriteCoachIds => Future<Set<String>>.value(const <String>{}),
      _ => super.noSuchMethod(invocation),
    };
  }
}

const _coach = CoachSummary(
  id: 'c1',
  userId: 'u1',
  displayName: 'โค้ชทดสอบ',
  bio: 'ประวัติย่อของโค้ช',
  experience: 'ประสบการณ์ 5 ปี',
  hourlyRate: 500,
  teachingMode: TeachingMode.both,
  isVerified: true,
  sportIds: {'s1'},
  skillLevels: {'beginner'},
  specialties: ['วิ่ง', 'สมาธิ'],
  averageRating10: 8.5,
  reviewCount: 4,
);

Widget _host(void Function(BuildContext ctx) onOpen) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (ctx) => Center(
        child: TextButton(
          onPressed: () => onOpen(ctx),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('coach request sheet uses the neumorphic sheet controls', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _host(
        (ctx) => CoachRequestSheet.show(
          ctx,
          coach: _coach,
          sports: const [
            {'id': 's1', 'name_th': 'วิ่ง'},
            {'id': 's2', 'name_th': 'ว่ายน้ำ'},
          ],
          preferredSportId: 's2',
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('ขอนัดกับ โค้ชทดสอบ'), findsOneWidget);
    expect(find.text('500 บาท/ชั่วโมง'), findsOneWidget);
    expect(find.byType(NeumorphicVerifyButton), findsOneWidget);
    expect(find.text('ส่งคำขอ'), findsOneWidget);
    expect(find.byType(NeumorphicPillButton), findsNWidgets(2));
    // ชิปที่เลือกใช้รางจม 2 ตัว (รูปแบบการสอน + ระยะเวลา) และช่องข้อความอีก 1
    expect(find.byType(NeumorphicInsetBox), findsNWidgets(3));
  });

  testWidgets('coach detail sheet renders and scrolls without overflow', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _host(
        (ctx) => CoachDetailSheet.show(
          ctx,
          coach: _coach,
          repo: _EmptyRepo(),
          onRequest: () async {},
          onOpenMyEnrollments: () {},
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('โค้ชทดสอบ'), findsOneWidget);
    expect(find.byType(NeumorphicSheetDragHandle), findsOneWidget);
    expect(find.byType(NeumorphicSheetCloseButton), findsOneWidget);
    expect(find.byType(NeumorphicTagChip), findsNWidgets(2));
    expect(find.text('ขอนัดกับโค้ช'), findsOneWidget);
    expect(find.text('ดูการสมัครและคำขอของฉัน'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
