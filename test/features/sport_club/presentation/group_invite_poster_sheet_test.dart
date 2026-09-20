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
    expect(find.text('แบดมินตัน'), findsOneWidget);
    expect(find.text('เปิดรับทุกเพศ'), findsOneWidget);
    expect(find.text('เข้าได้ทันที'), findsOneWidget);
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

  testWidgets('GroupInvitePosterSheet does not produce overflow errors on narrow screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    FlutterErrorDetails? errorDetails;
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      errorDetails = details;
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    await tester.pumpWidget(
      createTestableWidget(
        GroupInvitePosterSheet(
          groupData: {
            'id': 'group-uuid-999',
            'name': 'ก๊วนกีฬาเมืองตากสุดยอดฟิตเนสและแบดมินตัน',
            'sport_type': 'กีฬา',
            'gender_preference': 'any',
            'requires_owner_approval': false,
          },
        ),
      ),
    );

    if (errorDetails != null) {
      // ignore: avoid_print
      print('SUMMARY: ${errorDetails?.summary}');
      // ignore: avoid_print
      print('CONTEXT: ${errorDetails?.context}');
      if (errorDetails?.informationCollector != null) {
        for (final item in errorDetails!.informationCollector!()) {
          // ignore: avoid_print
          print('COLLECTOR ITEM: ${item.toStringDeep()}');
        }
      }
    }
    expect(errorDetails, isNull);
    expect(find.text('บัตรผ่านก๊วนกีฬา'), findsOneWidget);
    expect(find.text('เปิดรับทุกเพศ'), findsOneWidget);
    expect(find.text('เข้าได้ทันที'), findsOneWidget);
  });
}
