import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/sport_club_error_mapper.dart';

void main() {
  group('mapManagementError session overlap', () {
    test('maps the new database guard to a session-specific message', () {
      expect(
        mapManagementError(
          StateError('GROUP_SESSION_OVERLAP'),
          sessionContext: true,
        ),
        'รอบนัดนี้มีเวลาทับซ้อนกับรอบอื่นในก๊วน กรุณาเลือกเวลาใหม่',
      );
    });

    test('maps the legacy owner guard for session create/update', () {
      expect(
        mapManagementError(
          StateError('OWNER_AUTO_JOIN_OVERLAP'),
          sessionContext: true,
        ),
        'รอบนัดนี้มีเวลาทับซ้อนกับรอบอื่นในก๊วน กรุณาเลือกเวลาใหม่',
      );
    });

    test(
      'preserves the existing owner auto-join message outside session flows',
      () {
        expect(
          mapManagementError(StateError('OWNER_AUTO_JOIN_OVERLAP')),
          'ไม่สามารถเปิดเข้าร่วมทุกรอบได้ เพราะมีรอบเวลาทับซ้อนกัน',
        );
      },
    );
  });

  testWidgets('shows above a modal bottom sheet and fades out', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (sheetContext) => SizedBox(
                    height: 200,
                    child: ElevatedButton(
                      onPressed: () => showFloatingManagementError(
                        sheetContext,
                        'เกิดข้อผิดพลาด',
                      ),
                      child: const Text('แสดงข้อผิดพลาด'),
                    ),
                  ),
                );
              },
              child: const Text('เปิด sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิด sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('แสดงข้อผิดพลาด'));
    await tester.pump();

    expect(find.text('เกิดข้อผิดพลาด'), findsOneWidget);
    expect(find.text('แสดงข้อผิดพลาด'), findsOneWidget);
    expect(tester.getTopLeft(find.text('เกิดข้อผิดพลาด')).dy, greaterThan(300));

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('เกิดข้อผิดพลาด'), findsNothing);
  });
}
