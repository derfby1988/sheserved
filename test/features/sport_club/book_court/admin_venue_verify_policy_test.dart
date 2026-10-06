import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/auth/data/models/user_model.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_repository.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/pages/admin_court_owner_review_page.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/services/presence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeBookCourtRepository extends BookCourtRepository {
  _FakeBookCourtRepository()
    : super(
        SupabaseClient(
          'https://example.com',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  List<AdminVenueVerifyPolicy> policies = const [];
  List<SlipVerificationProvider> providers = const [];

  String? savedVenueId;
  String? savedScope;
  String? savedBearer;
  int? savedQuota;
  int? savedTimeout;
  bool? savedClearQuota;
  bool? savedClearTimeout;

  @override
  Future<List<VenueOwnerProfile>> listOwnerApplications(
    String adminId, {
    String status = 'pending',
  }) async => const [];

  @override
  Future<List<VenueSummary>> listVenuesForReview(
    String adminId, {
    String status = 'pending',
  }) async => const [];

  @override
  Future<List<SlipVerificationProvider>> adminListSlipProviders(
    String adminId,
  ) async => providers;

  @override
  Future<List<AdminVenueVerifyPolicy>> adminListVenueVerifyPolicies(
    String adminId,
  ) async => policies;

  @override
  Future<void> adminSetVenueVerifyPolicy({
    required String adminId,
    required String venueId,
    String? verifyScope,
    String? costBearer,
    int? monthlyQuota,
    int? verifyTimeoutMinutes,
    bool clearQuota = false,
    bool clearTimeout = false,
  }) async {
    savedVenueId = venueId;
    savedScope = verifyScope;
    savedBearer = costBearer;
    savedQuota = monthlyQuota;
    savedTimeout = verifyTimeoutMinutes;
    savedClearQuota = clearQuota;
    savedClearTimeout = clearTimeout;
  }
}

UserModel _adminUser() => UserModel(
  id: 'admin-1',
  userType: UserType.consumer,
  firstName: 'Test',
  lastName: 'Admin',
  username: 'test-admin',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<void> _pumpPanel(
  WidgetTester tester,
  _FakeBookCourtRepository repo,
) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await AuthService.instance.login(_adminUser());
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AdminCourtOwnerReviewPanel(repo: repo)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await AuthService.instance.logout();
  });

  tearDown(() async {
    await PresenceService.instance.stop();
    await AuthService.instance.logout();
  });

  testWidgets('lists venues with scope and warns when no provider is on', (
    tester,
  ) async {
    final repo = _FakeBookCourtRepository()
      ..policies = const [
        AdminVenueVerifyPolicy(
          venueId: 'v1',
          name: 'สนาม ก',
          status: 'approved',
          verifyScope: 'whitelist',
          costBearer: 'platform',
          hasEvidencePolicy: true,
          enabledProviderCount: 0,
        ),
        AdminVenueVerifyPolicy(
          venueId: 'v2',
          name: 'สนาม ข',
          status: 'approved',
          verifyScope: 'disabled',
          costBearer: 'owner',
          monthlyQuota: 500,
          verifyTimeoutMinutes: 30,
          hasEvidencePolicy: true,
          enabledProviderCount: 1,
          usedThisMonth: 10,
        ),
      ];
    await _pumpPanel(tester, repo);

    expect(find.text('สนาม ก'), findsOneWidget);
    expect(find.text('สนาม ข'), findsOneWidget);
    expect(find.text('เปิดเฉพาะสถานที่นี้'), findsOneWidget);
    expect(find.text('ปิดการตรวจอัตโนมัติ'), findsOneWidget);
    expect(
      find.text('ยังไม่มีผู้ให้บริการที่เปิดใช้งาน — สลิปจะตกไปให้เจ้าของตรวจแทน'),
      findsOneWidget,
    );
    expect(find.textContaining('ใช้ 10/500 ครั้งเดือนนี้'), findsOneWidget);
    // The heartbeat timer is created inside the test's async zone; stop it
    // here or the binding reports a pending timer.
    await PresenceService.instance.stop();
  });

  testWidgets('saving the dialog forwards scope, bearer, quota and timeout', (
    tester,
  ) async {
    final repo = _FakeBookCourtRepository()
      ..policies = const [
        AdminVenueVerifyPolicy(
          venueId: 'v3',
          name: 'สนาม ค',
          status: 'approved',
        ),
      ];
    await _pumpPanel(tester, repo);

    await tester.tap(find.text('ตั้งค่า'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('admin-verify-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เปิดเฉพาะสถานที่นี้').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('admin-verify-bearer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เจ้าของรับภาระ').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('admin-verify-quota')),
      '300',
    );
    await tester.enterText(
      find.byKey(const ValueKey('admin-verify-timeout')),
      '45',
    );
    await tester.tap(find.byKey(const ValueKey('admin-verify-save')));
    await tester.pumpAndSettle();

    expect(repo.savedVenueId, 'v3');
    expect(repo.savedScope, 'whitelist');
    expect(repo.savedBearer, 'owner');
    expect(repo.savedQuota, 300);
    expect(repo.savedTimeout, 45);
    expect(repo.savedClearQuota, isFalse);
    expect(repo.savedClearTimeout, isFalse);
    await PresenceService.instance.stop();
  });

  testWidgets('empty quota and timeout clear the stored values', (
    tester,
  ) async {
    final repo = _FakeBookCourtRepository()
      ..policies = const [
        AdminVenueVerifyPolicy(
          venueId: 'v4',
          name: 'สนาม ง',
          status: 'approved',
          verifyScope: 'whitelist',
          monthlyQuota: 500,
          verifyTimeoutMinutes: 30,
          enabledProviderCount: 1,
        ),
      ];
    await _pumpPanel(tester, repo);

    await tester.tap(find.text('ตั้งค่า'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('admin-verify-quota')), '');
    await tester.enterText(
      find.byKey(const ValueKey('admin-verify-timeout')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('admin-verify-save')));
    await tester.pumpAndSettle();

    expect(repo.savedQuota, isNull);
    expect(repo.savedTimeout, isNull);
    expect(repo.savedClearQuota, isTrue);
    expect(repo.savedClearTimeout, isTrue);
    await PresenceService.instance.stop();
  });
}
