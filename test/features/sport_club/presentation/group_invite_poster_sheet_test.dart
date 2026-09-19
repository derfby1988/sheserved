import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/group_invite_poster_sheet.dart';

void main() {
  final sampleGroupData = {
    'id': 'group-uuid-101',
    'name': 'ก๊วนแบดมินตันมือใหม่',
    'sport_type': 'Badminton',
  };

  final sampleSessionData = {
    'id': 'session-uuid-202',
    'title': 'รอบนัดกระชับมิตร วันเสาร์',
  };

  Widget createTestableWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  testWidgets('GroupInvitePosterSheet renders group invite details and QR Code',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      createTestableWidget(
        GroupInvitePosterSheet(groupData: sampleGroupData),
      ),
    );

    expect(find.text('เชิญเข้าร่วมก๊วนกีฬา'), findsOneWidget);
    expect(find.text('ก๊วนแบดมินตันมือใหม่'), findsOneWidget);
    expect(find.text('Badminton'), findsOneWidget);
    expect(find.text('คัดลอกลิงก์'), findsOneWidget);
    expect(find.text('บันทึกโปสเตอร์'), findsOneWidget);
  });

  testWidgets('GroupInvitePosterSheet renders session invite details when sessionData is provided',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      createTestableWidget(
        GroupInvitePosterSheet(
          groupData: sampleGroupData,
          sessionData: sampleSessionData,
        ),
      ),
    );

    expect(find.text('แชร์รอบนัดกิจกรรม'), findsOneWidget);
    expect(find.text('ก๊วนแบดมินตันมือใหม่'), findsOneWidget);
    expect(find.text('รอบนัดกระชับมิตร วันเสาร์'), findsOneWidget);
  });
}
