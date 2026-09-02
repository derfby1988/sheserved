import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/core/constants/password_policy.dart';
import 'package:sheserved/features/auth/data/models/password_change_result.dart';
import 'package:sheserved/features/auth/data/repositories/user_repository.dart';
import 'package:sheserved/features/profile/presentation/widgets/change_password_bottom_sheet.dart';
import 'package:sheserved/shared/widgets/tlz_button.dart';

import '../../../chat/data/repositories/chat_repository_test.mocks.dart';

class _FakeUserRepository extends UserRepository {
  _FakeUserRepository() : super(MockSupabaseClient());

  PasswordChangeResult nextResult = PasswordChangeResult.success;

  @override
  Future<PasswordChangeResult> changeCurrentUserPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return nextResult;
  }
}

void main() {
  group('ChangePasswordBottomSheet', () {
    testWidgets('renders current, new and confirm password fields', (tester) async {
      final fakeRepo = _FakeUserRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangePasswordBottomSheet(userRepository: fakeRepo),
          ),
        ),
      );

      expect(find.byKey(const Key('change_password_title')), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text('รหัสผ่านปัจจุบัน'), findsOneWidget);
      expect(find.text('รหัสผ่านใหม่'), findsOneWidget);
      expect(find.text('ยืนยันรหัสผ่านใหม่'), findsOneWidget);
    });

    testWidgets('toggling new password visibility hides confirm field', (tester) async {
      final fakeRepo = _FakeUserRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangePasswordBottomSheet(userRepository: fakeRepo),
          ),
        ),
      );

      expect(find.text('ยืนยันรหัสผ่านใหม่'), findsOneWidget);

      // Tap the visibility icon next to the new password field (second suffix icon).
      await tester.tap(find.byIcon(Icons.visibility_off).at(1));
      await tester.pumpAndSettle();

      // In visible mode the confirm field is hidden and a hint text is shown.
      expect(find.text('ยืนยันรหัสผ่านใหม่'), findsNothing);
      expect(find.text('เปิดการมองเห็นแล้ว ไม่ต้องกรอกรหัสผ่านซ้ำ'), findsOneWidget);
    });

    testWidgets('shows validation error when password is too short', (tester) async {
      final fakeRepo = _FakeUserRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangePasswordBottomSheet(userRepository: fakeRepo),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'current');
      await tester.enterText(find.byType(TextField).at(1), 'short');
      await tester.enterText(find.byType(TextField).at(2), 'short');
      await tester.tap(find.byKey(const Key('change_password_submit')));
      await tester.pumpAndSettle();

      final errorFinder = find.byKey(const Key('change_password_error'));
      expect(errorFinder, findsOneWidget);
      expect(
        tester.widget<Text>(errorFinder).data,
        PasswordPolicy.minLengthMessage,
      );
    });

    testWidgets('shows error when passwords do not match', (tester) async {
      final fakeRepo = _FakeUserRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangePasswordBottomSheet(userRepository: fakeRepo),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'current123');
      await tester.enterText(find.byType(TextField).at(1), 'newpassword123');
      await tester.enterText(find.byType(TextField).at(2), 'different123');
      await tester.tap(find.byKey(const Key('change_password_submit')));
      await tester.pumpAndSettle();

      final errorFinder = find.byKey(const Key('change_password_error'));
      expect(errorFinder, findsOneWidget);
      expect(
        tester.widget<Text>(errorFinder).data,
        'รหัสผ่านใหม่และการยืนยันไม่ตรงกัน',
      );
    });

    testWidgets('calls repository and pops on success', (tester) async {
      final fakeRepo = _FakeUserRepository();
      fakeRepo.nextResult = PasswordChangeResult.success;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ChangePasswordBottomSheet(userRepository: fakeRepo),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'current123');
      await tester.enterText(find.byType(TextField).at(1), 'newpassword123');
      await tester.enterText(find.byType(TextField).at(2), 'newpassword123');
      await tester.tap(find.byKey(const Key('change_password_submit')));
      await tester.pumpAndSettle();

      // After success the sheet should have popped.
      expect(find.byType(ChangePasswordBottomSheet), findsNothing);
    });

    testWidgets('shows cooldown after three wrong current password attempts', (tester) async {
      final fakeRepo = _FakeUserRepository();
      fakeRepo.nextResult = PasswordChangeResult.currentPasswordIncorrect;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangePasswordBottomSheet(userRepository: fakeRepo),
          ),
        ),
      );

      for (var i = 0; i < 3; i++) {
        await tester.enterText(find.byType(TextField).at(0), 'wrong');
        await tester.enterText(find.byType(TextField).at(1), 'newpassword123');
        await tester.enterText(find.byType(TextField).at(2), 'newpassword123');
        await tester.tap(find.byKey(const Key('change_password_submit')));
        await tester.pump();
      }

      // ครั้งที่ 3 แสดง cooldown เฉพาะในปุ่ม (§6.4)
      expect(find.text('ลองผิดหลายครั้ง กรุณารอสักครู่'), findsNothing);
      expect(find.textContaining('เหลือเวลา'), findsNothing);
      final submitButton = tester.widget<TlzButton>(find.byKey(const Key('change_password_submit')));
      expect(submitButton.text, 'รอ 30 วิ');
      expect(submitButton.onPressed, isNull);

      await tester.pump(const Duration(seconds: 1));
      final countdownButton = tester.widget<TlzButton>(
        find.byKey(const Key('change_password_submit')),
      );
      expect(countdownButton.text, 'รอ 29 วิ');
      expect(find.textContaining('เหลือเวลา'), findsNothing);

      await tester.pump(const Duration(seconds: 29));
      final unlockedButton = tester.widget<TlzButton>(
        find.byKey(const Key('change_password_submit')),
      );
      expect(unlockedButton.text, 'เปลี่ยนรหัสผ่าน');
      expect(unlockedButton.onPressed, isNotNull);
      expect(find.textContaining('เหลือเวลา'), findsNothing);
    });
  });
}
