import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/auth/data/models/user_model.dart';
import 'package:sheserved/features/auth/data/repositories/user_repository.dart';
import 'package:sheserved/features/auth/presentation/pages/login_page.dart';

import '../../../chat/data/repositories/chat_repository_test.mocks.dart';

class _FakeLoginRepository extends UserRepository {
  _FakeLoginRepository() : super(MockSupabaseClient());

  int loginCalls = 0;
  UserModel? nextUser;
  bool throwOnLogin = false;

  @override
  Future<UserModel?> login(String identifier, String password) async {
    loginCalls++;
    if (throwOnLogin) {
      throw StateError('simulated network failure');
    }
    return nextUser;
  }
}

void main() {
  group('LoginPage client-side lockout', () {
    testWidgets('locks login after three failed attempts and counts down', (
      tester,
    ) async {
      final repository = _FakeLoginRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(userRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.enterText(find.byType(TextField).at(0), 'sister');
        await tester.enterText(find.byType(TextField).at(1), 'wrong-password');
        await tester.tap(find.byKey(const Key('login_submit')));
        await tester.pump();
      }

      expect(repository.loginCalls, 3);
      expect(find.text('ลองผิดหลายครั้ง กรุณารอสักครู่'), findsNothing);
      expect(find.textContaining('เหลือเวลา'), findsNothing);
      expect(find.text('รอ 30 วิ'), findsOneWidget);

      final lockedButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('login_submit')),
      );
      expect(lockedButton.onPressed, isNull);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('รอ 29 วิ'), findsOneWidget);

      await tester.pump(const Duration(seconds: 29));
      expect(find.text('ลองผิดหลายครั้ง กรุณารอสักครู่'), findsNothing);
      expect(find.textContaining('เหลือเวลา'), findsNothing);
      expect(find.text('เข้าสู่ระบบ'), findsOneWidget);

      final unlockedButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('login_submit')),
      );
      expect(unlockedButton.onPressed, isNotNull);
    });

    testWidgets('does not count request errors as failed credentials', (
      tester,
    ) async {
      final repository = _FakeLoginRepository()..throwOnLogin = true;

      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(userRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.enterText(find.byType(TextField).at(0), 'sister');
        await tester.enterText(find.byType(TextField).at(1), 'any-password');
        await tester.tap(find.byKey(const Key('login_submit')));
        await tester.pump();
      }

      expect(repository.loginCalls, 3);
      expect(find.text('ลองผิดหลายครั้ง กรุณารอสักครู่'), findsNothing);
      expect(find.textContaining('เหลือเวลา'), findsNothing);
    });
  });
}
