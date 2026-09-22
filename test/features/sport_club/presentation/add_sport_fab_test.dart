import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/auth/data/models/user_model.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/feed/sport_category_chips.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/services/presence_service.dart';

class _RouteRecorder extends NavigatorObserver {
  final List<RouteSettings> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings);
  }

  List<String?> get pushedNames =>
      pushed.map((settings) => settings.name).toList();

  RouteSettings? get loginSettings =>
      pushed.where((settings) => settings.name == '/login').firstOrNull;
}

UserModel _user() => UserModel(
  id: 'user-1',
  userType: UserType.consumer,
  firstName: 'สมชาย',
  lastName: 'ใจดี',
  username: 'somchai',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Widget _harness(_RouteRecorder recorder) => MaterialApp(
  navigatorObservers: [recorder],
  home: const Scaffold(body: Center(child: AddSportFab())),
  routes: {
    '/login': (context) => const Scaffold(body: Text('login')),
    '/community/sport-club/sport/propose': (context) =>
        const Scaffold(body: Text('propose')),
  },
);

void main() {
  setUp(() async {
    await AuthService.instance.logout();
  });

  tearDown(() async {
    await PresenceService.instance.stop();
    await AuthService.instance.logout();
  });

  testWidgets('guest is sent to login before the propose page opens', (
    tester,
  ) async {
    final recorder = _RouteRecorder();
    await tester.pumpWidget(_harness(recorder));

    await tester.tap(find.byType(AddSportFab));
    await tester.pumpAndSettle();

    expect(recorder.pushedNames, ['/', '/login']);
    expect(recorder.loginSettings?.arguments, {'returnAfterLogin': true});
    expect(find.text('propose'), findsNothing);
  });

  testWidgets('logged-in user opens the propose page directly', (tester) async {
    await AuthService.instance.login(_user());
    final recorder = _RouteRecorder();
    await tester.pumpWidget(_harness(recorder));

    await tester.tap(find.byType(AddSportFab));
    await tester.pumpAndSettle();

    expect(recorder.pushedNames, ['/', '/community/sport-club/sport/propose']);
    expect(find.text('propose'), findsOneWidget);

    // heartbeat timer ของ PresenceService ถูกสร้างในโซน async ของ test
    // ต้องยกเลิกภายใน test ไม่งั้น binding จะฟ้องว่ามี timer ค้าง
    await PresenceService.instance.stop();
  });
}
