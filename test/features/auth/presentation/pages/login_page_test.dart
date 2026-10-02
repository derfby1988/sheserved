import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/auth/data/models/user_model.dart';
import 'package:sheserved/features/auth/data/repositories/user_repository.dart';
import 'package:sheserved/features/auth/presentation/pages/login_page.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic_button.dart';

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

UserModel _testUser() {
  final now = DateTime.utc(2026);
  return UserModel(
    id: 'login-test-user',
    userType: UserType.consumer,
    firstName: 'Test',
    lastName: 'User',
    username: 'test-user',
    createdAt: now,
    updatedAt: now,
  );
}

Widget _loginNavigationHarness({
  required _FakeLoginRepository repository,
  required Object loginArguments,
}) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Calling page'),
            ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (sheetContext) {
                  var actionResumed = false;
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: StatefulBuilder(
                      builder: (sheetContext, setSheetState) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Calling sheet'),
                          if (actionResumed) const Text('Action resumed'),
                          ElevatedButton(
                            onPressed: () async {
                              await Navigator.of(
                                sheetContext,
                              ).pushNamed('/login', arguments: loginArguments);
                              if (!sheetContext.mounted ||
                                  AuthService.instance.currentUser == null) {
                                return;
                              }
                              setSheetState(() => actionResumed = true);
                            },
                            child: const Text('Require login'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              child: const Text('Open sheet'),
            ),
          ],
        ),
      ),
    ),
  ),
  routes: {
    '/login': (context) => LoginPage(userRepository: repository),
    '/destination': (context) =>
        const Scaffold(body: Center(child: Text('Explicit destination'))),
  },
);

Future<void> _completeLogin(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'test-user');
  await tester.enterText(find.byType(TextField).at(1), 'password');
  final submitLabel = find.text('เข้าสู่ระบบ');
  await tester.ensureVisible(submitLabel);
  await tester.tap(submitLabel);
  await tester.pumpAndSettle();
}

void main() {
  group('LoginPage client-side lockout', () {
    testWidgets('locks login after three failed attempts and counts down', (
      tester,
    ) async {
      final repository = _FakeLoginRepository();

      await tester.pumpWidget(
        MaterialApp(home: LoginPage(userRepository: repository)),
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

      final lockedButton = tester.widget<NeumorphicVerifyButton>(
        find.byKey(const Key('login_submit')),
      );
      expect(lockedButton.isEnabled, isFalse);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('รอ 29 วิ'), findsOneWidget);

      await tester.pump(const Duration(seconds: 29));
      expect(find.text('ลองผิดหลายครั้ง กรุณารอสักครู่'), findsNothing);
      expect(find.textContaining('เหลือเวลา'), findsNothing);
      expect(find.text('เข้าสู่ระบบ'), findsOneWidget);

      final unlockedButton = tester.widget<NeumorphicVerifyButton>(
        find.byKey(const Key('login_submit')),
      );
      expect(unlockedButton.isEnabled, isTrue);
    });

    testWidgets('does not count request errors as failed credentials', (
      tester,
    ) async {
      final repository = _FakeLoginRepository()..throwOnLogin = true;

      await tester.pumpWidget(
        MaterialApp(home: LoginPage(userRepository: repository)),
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

  group('LoginPage return navigation', () {
    testWidgets('returnAfterLogin reveals the original bottom sheet', (
      tester,
    ) async {
      final repository = _FakeLoginRepository()..nextUser = _testUser();
      try {
        await tester.pumpWidget(
          _loginNavigationHarness(
            repository: repository,
            loginArguments: {'returnAfterLogin': true},
          ),
        );

        await tester.tap(find.text('Open sheet'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Require login'));
        await tester.pumpAndSettle();
        await _completeLogin(tester);

        expect(find.text('Calling sheet'), findsOneWidget);
        expect(find.text('Action resumed'), findsOneWidget);
        expect(find.text('Calling page'), findsOneWidget);
        expect(find.byKey(const Key('login_submit')), findsNothing);
      } finally {
        await AuthService.instance.logout();
      }
    });

    testWidgets('explicit redirect still opens its requested route', (
      tester,
    ) async {
      final repository = _FakeLoginRepository()..nextUser = _testUser();
      try {
        await tester.pumpWidget(
          _loginNavigationHarness(
            repository: repository,
            loginArguments: {'redirect': '/destination'},
          ),
        );

        await tester.tap(find.text('Open sheet'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Require login'));
        await tester.pumpAndSettle();
        await _completeLogin(tester);

        expect(find.text('Explicit destination'), findsOneWidget);
        expect(find.byKey(const Key('login_submit')), findsNothing);
      } finally {
        await AuthService.instance.logout();
      }
    });
  });
}
