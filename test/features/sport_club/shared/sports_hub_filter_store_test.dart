import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sheserved/features/sport_club/book_court/domain/book_court_filter.dart';
import 'package:sheserved/features/sport_club/find_coach/domain/find_coach_filter.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_filter_store.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_discovery_filter.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_hub_filter_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = SportsHubFilterStore();

  test('returns null for a user with no saved state', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await store.load('store-u1'), isNull);
    expect(await store.load(null), isNull);
  });

  test('round-trips every domain of the hub state', () async {
    SharedPreferences.setMockInitialValues({});
    const state = SportsHubFilterState(
      shared: SportsDiscoveryFilter(
        sportId: 's1',
        query: 'tennis',
        province: 'p',
        district: 'd',
        locationEnabled: true,
        radiusKm: 25,
      ),
      buddies: SportBuddiesFilter(joinedOnly: true),
      courts: BookCourtFilter(
        minPrice: 100,
        startTime: TimeOfDay(hour: 9, minute: 30),
        amenityIds: {'parking'},
      ),
      coaches: FindCoachFilter(verifiedOnly: true, skillLevel: 'pro'),
    );

    await store.save('store-u1', state);
    final restored = await store.load('store-u1');
    expect(restored, state);
  });

  test('keys are namespaced per user', () async {
    SharedPreferences.setMockInitialValues({});
    await store.save(
      'store-u1',
      const SportsHubFilterState(
        shared: SportsDiscoveryFilter(sportId: 'u1-sport'),
      ),
    );

    expect(await store.load('store-u2'), isNull);
    final restored = await store.load('store-u1');
    expect(restored?.shared.sportId, 'u1-sport');
  });

  test('corrupt payloads are treated as missing state', () async {
    SharedPreferences.setMockInitialValues({
      'sports_hub_shared_filter_v1_store-u1': '{not-json',
    });
    expect(await store.load('store-u1'), isNull);
  });
}
