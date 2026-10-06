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
  GlobalSlipVerificationPolicy globalPolicy =
      const GlobalSlipVerificationPolicy();

  String? savedVenueId;
  String? savedScope;
  String? savedBearer;
  bool? savedAllowlisted;
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
  Future<GlobalSlipVerificationPolicy> adminGetGlobalVerifyPolicy(
    String adminId,
  ) async => globalPolicy;

  @override
  Future<void> adminSetGlobalVerifyScope({
    required String adminId,
    required String scope,
  }) async {
    savedScope = scope;
    globalPolicy = GlobalSlipVerificationPolicy(
      scope: scope,
      approvedVenueCount: globalPolicy.approvedVenueCount,
      allowlistedVenueCount: globalPolicy.allowlistedVenueCount,
      configuredProviderCount: globalPolicy.configuredProviderCount,
    );
  }

  @override
  Future<List<AdminVenueVerifyPolicy>> adminListVenueVerifyPolicies(
    String adminId,
  ) async => policies;

  @override
  Future<void> adminSetVenueVerifyControls({
    required String adminId,
    required String venueId,
    required bool isAllowlisted,
    String? costBearer,
    int? monthlyQuota,
    int? verifyTimeoutMinutes,
    bool clearQuota = false,
    bool clearTimeout = false,
  }) async {
    savedVenueId = venueId;
    savedAllowlisted = isAllowlisted;
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

  testWidgets('global scope requires confirmation and saves separately', (
    tester,
  ) async {
    final repo = _FakeBookCourtRepository()
      ..globalPolicy = const GlobalSlipVerificationPolicy(
        approvedVenueCount: 4,
        allowlistedVenueCount: 2,
        configuredProviderCount: 1,
      );
    await _pumpPanel(tester, repo);

    await tester.tap(find.byKey(const ValueKey('admin-global-verify-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เฉพาะสถานที่ใน allowlist').last);
    await tester.pumpAndSettle();
    expect(find.text('ยืนยันขอบเขตตรวจสลิป'), findsOneWidget);
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();

    expect(repo.savedScope, 'whitelist');
    expect(repo.globalPolicy.scope, 'whitelist');
    await PresenceService.instance.stop();
  });

  testWidgets('lists venues with scope and warns when no provider is on', (
    tester,
  ) async {
    final repo = _FakeBookCourtRepository()
      ..globalPolicy = const GlobalSlipVerificationPolicy(
        scope: 'whitelist',
        approvedVenueCount: 2,
        allowlistedVenueCount: 1,
        configuredProviderCount: 0,
      )
      ..policies = const [
        AdminVenueVerifyPolicy(
          venueId: 'v1',
          name: 'สนาม ก',
          status: 'approved',
          globalScope: 'whitelist',
          isAllowlisted: true,
          costBearer: 'platform',
          hasEvidencePolicy: true,
          configuredProviderCount: 0,
        ),
        AdminVenueVerifyPolicy(
          venueId: 'v2',
          name: 'สนาม ข',
          status: 'approved',
          globalScope: 'whitelist',
          costBearer: 'owner',
          monthlyQuota: 500,
          verifyTimeoutMinutes: 30,
          hasEvidencePolicy: true,
          configuredProviderCount: 1,
          callsThisMonth: 10,
        ),
      ];
    await _pumpPanel(tester, repo);

    expect(find.text('สนาม ก'), findsOneWidget);
    expect(find.text('สนาม ข'), findsOneWidget);
    expect(find.text('เฉพาะสถานที่ใน allowlist'), findsOneWidget);
    expect(find.text('อยู่ใน allowlist'), findsOneWidget);
    expect(find.text('ไม่อยู่ใน allowlist'), findsOneWidget);
    expect(
      find.text(
        'ยังไม่มี provider ที่เปิดและตั้ง endpoint/secret reference ครบ — สลิปจะตกไปให้เจ้าของตรวจแทน',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ใช้/จอง 10/500 ครั้งเดือนนี้'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('admin-verify-allowlist-v2')),
    );
    await tester.pumpAndSettle();
    expect(repo.savedAllowlisted, isTrue);
    // The heartbeat timer is created inside the test's async zone; stop it
    // here or the binding reports a pending timer.
    await PresenceService.instance.stop();
  });

  testWidgets('saving venue cost controls forwards bearer, quota and timeout', (
    tester,
  ) async {
    final repo = _FakeBookCourtRepository()
      ..globalPolicy = const GlobalSlipVerificationPolicy(scope: 'whitelist')
      ..policies = const [
        AdminVenueVerifyPolicy(
          venueId: 'v3',
          name: 'สนาม ค',
          status: 'approved',
          globalScope: 'whitelist',
          isAllowlisted: true,
        ),
      ];
    await _pumpPanel(tester, repo);

    await tester.tap(find.text('ตั้งค่าค่าใช้จ่าย'));
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
    expect(repo.savedAllowlisted, isTrue);
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
      ..globalPolicy = const GlobalSlipVerificationPolicy(scope: 'whitelist')
      ..policies = const [
        AdminVenueVerifyPolicy(
          venueId: 'v4',
          name: 'สนาม ง',
          status: 'approved',
          globalScope: 'whitelist',
          isAllowlisted: true,
          monthlyQuota: 500,
          verifyTimeoutMinutes: 30,
          configuredProviderCount: 1,
        ),
      ];
    await _pumpPanel(tester, repo);

    await tester.tap(find.text('ตั้งค่าค่าใช้จ่าย'));
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
