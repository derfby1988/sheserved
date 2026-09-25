import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/sport_club/presentation/pages/sport_club_page.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/feed/empty_filter_state.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_controller.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_filter_store.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_discovery_filter.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_hub_filter_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _DeferredFilterStore extends SportsHubFilterStore {
  final Completer<SportsHubFilterState?> loadedState =
      Completer<SportsHubFilterState?>();
  int loadCalls = 0;

  @override
  Future<SportsHubFilterState?> load(String? userId) {
    loadCalls++;
    return loadedState.future;
  }

  @override
  Future<void> save(String? userId, SportsHubFilterState state) async {}
}

class _FakeFitnessBuddiesRepository extends FitnessBuddiesRepository {
  _FakeFitnessBuddiesRepository()
    : super(
        SupabaseClient(
          'https://example.com',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  int listGroupsCalls = 0;
  String? lastRequestedSportId;

  @override
  Future<List<Map<String, dynamic>>> getApprovedSports({
    String? userId,
  }) async => [
    {'id': 'sport-1', 'name_th': 'แบดมินตัน', 'icon': '🏸'},
  ];

  @override
  Future<List<Map<String, dynamic>>> listGroups({
    String? sportId,
    String? q,
    String? province,
    String? district,
    String? skillLevel,
    bool allLevelsOnly = false,
    bool genderAnyOnly = false,
    bool openOnly = false,
    int limit = 50,
    int offset = 0,
  }) async {
    listGroupsCalls++;
    lastRequestedSportId = sportId;
    return [];
  }

  @override
  Future<Set<String>> filterGroupIdsWithAnySessions(
    List<String> groupIds,
  ) async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'restores saved hub sport without dropping sports or stranding feed loading',
    (tester) async {
      final store = _DeferredFilterStore();
      final hub = SportsHubController(
        store: store,
        userIdProvider: () => 'user-1',
      );
      addTearDown(hub.dispose);
      unawaited(hub.load());
      final repository = _FakeFitnessBuddiesRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SportClubPage(
              embeddedInSportsHub: true,
              hubController: hub,
              repository: repository,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(store.loadCalls, greaterThanOrEqualTo(1));

      store.loadedState.complete(
        const SportsHubFilterState(
          shared: SportsDiscoveryFilter(sportId: 'sport-1'),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('แบดมินตัน'), findsOneWidget);
      expect(find.byType(SkeletonGroupCard), findsNothing);
      expect(find.text('ไม่พบก๊วนตามตัวกรองที่เลือก'), findsOneWidget);
      expect(repository.listGroupsCalls, 1);
      expect(repository.lastRequestedSportId, 'sport-1');
    },
  );
}
