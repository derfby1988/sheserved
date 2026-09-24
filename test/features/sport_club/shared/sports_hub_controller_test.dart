import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sheserved/features/sport_club/book_court/domain/book_court_filter.dart';
import 'package:sheserved/features/sport_club/domain/sport_club_filter.dart';
import 'package:sheserved/features/sport_club/find_coach/domain/find_coach_filter.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_controller.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_filter_store.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_discovery_filter.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_hub_filter_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SportsHubController', () {
    test('updates shared filter without touching domain filters', () {
      final controller = SportsHubController(userIdProvider: () => 'u1');
      controller.updateCourts(
        const BookCourtFilter(minPrice: 100, bookedByMeOnly: true),
      );
      controller.updateCoaches(const FindCoachFilter(verifiedOnly: true));
      controller.updateShared(
        const SportsDiscoveryFilter(
          sportId: 'sport-1',
          province: 'กรุงเทพมหานคร',
        ),
      );

      expect(controller.shared.sportId, 'sport-1');
      expect(controller.courts.minPrice, 100);
      expect(controller.coaches.verifiedOnly, isTrue);
    });

    test(
      'shared sport selection replaces the current sport and can clear it',
      () {
        const current = SportsDiscoveryFilter(
          sportId: 'sport-1',
          query: 'court',
        );

        final selected = current.withSportId('sport-2');
        expect(selected.sportId, 'sport-2');
        expect(selected.query, 'court');
        expect(selected.withSportId(null).sportId, isNull);
      },
    );

    test('domain filter edits never leak into other domains', () {
      final controller = SportsHubController(userIdProvider: () => 'u1');
      controller.updateCourts(
        BookCourtFilter(
          date: DateTime(2026, 10, 1),
          minPrice: 50,
          indoorOnly: true,
        ),
      );

      // Booking date must never appear in the coach filter or shared state.
      expect(controller.coaches, const FindCoachFilter());
      expect(controller.shared.sportId, isNull);
      expect(controller.buddies, const SportBuddiesFilter());
    });

    test('toSportClubFilter carries shared + buddies fields only', () {
      final controller = SportsHubController(userIdProvider: () => 'u1');
      controller.updateShared(
        const SportsDiscoveryFilter(
          sportId: 's1',
          query: 'badminton',
          province: 'เชียงใหม่',
          district: 'เมือง',
          locationEnabled: true,
          radiusKm: 15,
        ),
      );
      controller.updateBuddies(
        const SportBuddiesFilter(joinedOnly: true, noFeesOnly: true),
      );
      controller.updateCourts(const BookCourtFilter(minPrice: 999));
      controller.updateCoaches(const FindCoachFilter(maxHourlyRate: 500));

      final legacy = controller.toSportClubFilter();
      expect(legacy.sportId, 's1');
      expect(legacy.q, 'badminton');
      expect(legacy.province, 'เชียงใหม่');
      expect(legacy.district, 'เมือง');
      expect(legacy.locationEnabled, isTrue);
      expect(legacy.radiusKm, 15);
      expect(legacy.joinedOnly, isTrue);
      expect(legacy.noFeesOnly, isTrue);
    });

    test('absorbSportClubFilter splits shared from buddies fields', () {
      final controller = SportsHubController(userIdProvider: () => 'u1');
      controller.absorbSportClubFilter(
        const SportClubFilter(
          sportId: 's7',
          q: 'tennis',
          province: 'ขอนแก่น',
          joinedOnly: true,
          openOnly: true,
          radiusKm: 30,
        ),
      );

      expect(controller.shared.sportId, 's7');
      expect(controller.shared.query, 'tennis');
      expect(controller.shared.province, 'ขอนแก่น');
      expect(controller.shared.radiusKm, 30);
      expect(controller.buddies.joinedOnly, isTrue);
      expect(controller.buddies.openOnly, isTrue);
      // The legacy-only page filter never gains court/coach fields.
      expect(controller.courts, const BookCourtFilter());
    });

    test('seedFromSportClubFilter applies once and only on fresh state', () {
      final controller = SportsHubController(userIdProvider: () => 'u1');
      controller.seedFromSportClubFilter(
        const SportClubFilter(sportId: 's1', province: 'p1'),
      );
      expect(controller.shared.sportId, 's1');

      // Second seed must not overwrite the existing hub state.
      controller.seedFromSportClubFilter(
        const SportClubFilter(sportId: 's2', province: 'p2'),
      );
      expect(controller.shared.sportId, 's1');
      expect(controller.shared.province, 'p1');
    });

    test('seed is ignored when hub already has persisted state', () {
      final controller = SportsHubController(userIdProvider: () => 'u1');
      controller.updateShared(const SportsDiscoveryFilter(sportId: 'existing'));
      controller.seedFromSportClubFilter(
        const SportClubFilter(sportId: 'legacy'),
      );
      expect(controller.shared.sportId, 'existing');
    });

    test('logout deactivates personal filters but keeps shared state', () {
      final controller = SportsHubController(userIdProvider: () => 'u1');
      controller.updateShared(
        const SportsDiscoveryFilter(sportId: 's1', province: 'p'),
      );
      controller.updateBuddies(
        const SportBuddiesFilter(joinedOnly: true, managedOnly: true),
      );
      controller.updateCourts(
        const BookCourtFilter(bookedByMeOnly: true, ownerOnly: true),
      );

      controller.handleUserChanged(null);

      expect(controller.shared.sportId, 's1');
      expect(controller.buddies.joinedOnly, isFalse);
      expect(controller.buddies.managedOnly, isFalse);
      expect(controller.courts.bookedByMeOnly, isFalse);
      expect(controller.courts.ownerOnly, isFalse);
    });

    test('persists and restores the whole hub state', () async {
      SharedPreferences.setMockInitialValues({});
      const store = SportsHubFilterStore();
      // Unique key: other tests' controllers may still have queued writes
      // for 'u1' in flight, which would clobber this test's saved state.
      final controller = SportsHubController(
        store: store,
        userIdProvider: () => 'persist-user',
      );
      controller.updateShared(
        const SportsDiscoveryFilter(sportId: 's1', radiusKm: 42),
      );
      controller.updateCourts(
        BookCourtFilter(
          date: DateTime(2026, 10, 5),
          startTime: const TimeOfDay(hour: 18, minute: 30),
          amenityIds: const {'parking'},
        ),
      );
      controller.updateCoaches(
        const FindCoachFilter(skillLevel: 'beginner', verifiedOnly: true),
      );
      // Fire-and-forget save; allow the async write to flush.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final restored = await store.load('persist-user');
      expect(restored, controller.state);
    });

    test('notifies listeners on each domain update', () {
      final controller = SportsHubController(userIdProvider: () => 'u1');
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.updateShared(const SportsDiscoveryFilter(sportId: 's1'));
      controller.updateCourts(const BookCourtFilter(minRating: 4));
      controller.updateCoaches(const FindCoachFilter(availableOnly: true));
      controller.updateBuddies(const SportBuddiesFilter(openOnly: true));
      expect(notifications, 4);
      // No-op update must not notify again.
      controller.updateBuddies(const SportBuddiesFilter(openOnly: true));
      expect(notifications, 4);
    });
  });
}
