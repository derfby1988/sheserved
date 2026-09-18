import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/sport_club/application/sport_club_card_hydrator.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/feed/group_card.dart';

class MockRepo extends Mock implements FitnessBuddiesRepository {}

class MockClient extends Mock implements SupabaseClient {}

Map<String, dynamic> mkGroup() => {
  'id': 'g1',
  'name': 'Test Group',
  'sport_name': 'ฟุตบอล',
};

Map<String, dynamic> mkSession(String id, String startsAt) => {
  'id': id,
  'group_id': 'g1',
  'starts_at': startsAt,
  'ends_at': '2026-01-01T12:00:00Z',
  'capacity': 10,
  'confirmed_count': 3,
};

Widget buildCard({required SportClubGroupCardData cardData}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: GroupCard(
          group: mkGroup(),
          cardData: cardData,
          repo: MockRepo(),
          client: MockClient(),
          myAdminGroups: const {},
          myJoinedGroupIds: const {},
          myPendingGroupIds: const {},
          myBlockedGroupIds: const {},
          onTap: () {},
          onBook:
              (
                sessionId, {
                required requiresOwnerApproval,
                groupId,
                positionId,
              }) async {},
          onSessionCreated: () {},
        ),
      ),
    ),
  );
}

void main() {
  group('GroupCard (hydrated)', () {
    testWidgets('renders "ยังไม่มีรอบนัด" without any loading indicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildCard(cardData: SportClubGroupCardData.empty),
      );
      await tester.pump();
      expect(find.text('ยังไม่มีรอบนัด'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(FutureBuilder<List<dynamic>>), findsNothing);
    });

    testWidgets('renders "รอบนัดล่าสุดสิ้นสุดแล้ว" when only ended sessions', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildCard(
          cardData: const SportClubGroupCardData(hasAnySessions: true),
        ),
      );
      await tester.pump();
      expect(find.text('รอบนัดล่าสุดสิ้นสุดแล้ว'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('renders session row and join button from hydrated data', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildCard(
          cardData: SportClubGroupCardData(
            upcomingSessions: [mkSession('s1', '2026-01-01T10:00:00Z')],
            hasAnySessions: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('รอบ: '), findsWidgets);
      expect(find.text('เข้าร่วมก๊วน'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('shows at most 3 sessions plus "more" hint', (tester) async {
      await tester.pumpWidget(
        buildCard(
          cardData: SportClubGroupCardData(
            upcomingSessions: [
              mkSession('s1', '2026-01-01T10:00:00Z'),
              mkSession('s2', '2026-01-02T10:00:00Z'),
              mkSession('s3', '2026-01-03T10:00:00Z'),
              mkSession('s4', '2026-01-04T10:00:00Z'),
            ],
            hasAnySessions: true,
          ),
        ),
      );
      await tester.pump();
      // 3 session blocks each render one centered "รอบ: <range>" pill.
      expect(find.textContaining('รอบ: '), findsNWidgets(3));
      expect(find.text('กดเพื่อแสดงรอบอื่น ๆ'), findsOneWidget);
    });

    testWidgets('renders explicit error text when sessionError is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildCard(
          cardData: const SportClubGroupCardData(sessionError: 'network down'),
        ),
      );
      await tester.pump();
      expect(
        find.text('โหลดรอบนัดไม่สำเร็จ: network down'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
