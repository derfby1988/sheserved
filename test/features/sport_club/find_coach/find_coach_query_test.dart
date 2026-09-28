import 'package:flutter_test/flutter_test.dart';

import 'package:sheserved/features/sport_club/find_coach/application/find_coach_query.dart';
import 'package:sheserved/features/sport_club/find_coach/data/coach_models.dart';
import 'package:sheserved/features/sport_club/find_coach/domain/find_coach_filter.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_discovery_filter.dart';

CoachSummary _coach(
  String id, {
  Set<String> sportIds = const {'s1'},
  List<CoachServiceArea> areas = const [],
  TeachingMode mode = TeachingMode.both,
  bool verified = true,
  double? rate,
  Set<String> skillLevels = const {'beginner'},
  List<String> specialties = const [],
  double? averageRating10,
  Set<String> offeringTypes = const {},
}) => CoachSummary(
  id: id,
  userId: 'u-$id',
  displayName: 'Coach $id',
  sportIds: sportIds,
  serviceAreas: areas,
  teachingMode: mode,
  isVerified: verified,
  hourlyRate: rate,
  skillLevels: skillLevels,
  specialties: specialties,
  averageRating10: averageRating10,
  offeringTypes: offeringTypes,
);

void main() {
  group('FindCoachQuery', () {
    FindCoachQuery buildQuery({
      required Future<List<CoachSummary>> Function({
        String? query,
        int limit,
        int offset,
      })
      listCoaches,
      int pageSize = 20,
    }) => FindCoachQuery(
      listCoaches: listCoaches,
      hydrateCoaches: (coaches) async => coaches,
      pageSize: pageSize,
    );

    test('shared sport filter drops coaches without the sport', () async {
      final query = buildQuery(
        listCoaches: ({query, limit = 20, offset = 0}) async => [
          _coach('a', sportIds: {'s1'}),
          _coach('b', sportIds: {'s2'}),
        ],
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(sportId: 's1'),
        filter: const FindCoachFilter(),
        offset: 0,
      );
      expect(page.coaches.map((c) => c.id), ['a']);
    });

    test('shared province/district match coach service areas', () async {
      final query = buildQuery(
        listCoaches: ({query, limit = 20, offset = 0}) async => [
          _coach(
            'bkk',
            areas: const [
              CoachServiceArea(province: 'กรุงเทพมหานคร', district: 'บางรัก'),
            ],
          ),
          _coach(
            'cnx',
            areas: const [
              CoachServiceArea(province: 'เชียงใหม่', district: 'เมือง'),
            ],
          ),
        ],
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(
          province: 'เชียงใหม่',
          district: 'เมือง',
        ),
        filter: const FindCoachFilter(),
        offset: 0,
      );
      expect(page.coaches.map((c) => c.id), ['cnx']);
    });

    test('radius filter uses service area centres and coach radius',
        () async {
      final query = buildQuery(
        listCoaches: ({query, limit = 20, offset = 0}) async => [
          _coach(
            'near',
            areas: const [
              CoachServiceArea(lat: 13.756, lng: 100.502),
            ],
          ),
          _coach(
            'far-but-covers',
            areas: const [
              CoachServiceArea(lat: 14.5, lng: 100.5, radiusKm: 200),
            ],
          ),
          _coach(
            'far',
            areas: const [
              CoachServiceArea(lat: 14.5, lng: 100.5),
            ],
          ),
        ],
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(
          locationEnabled: true,
          radiusKm: 10,
        ),
        filter: const FindCoachFilter(),
        offset: 0,
        userLat: 13.75,
        userLng: 100.5,
      );
      // 'far-but-covers' qualifies because the user sits inside its own
      // service radius even though the area centre is 80km away.
      expect(page.coaches.map((c) => c.id), ['near', 'far-but-covers']);
    });

    test('domain filters: verified, mode, rate, level, specialty', () async {
      final query = buildQuery(
        listCoaches: ({query, limit = 20, offset = 0}) async => [
          _coach('ok'),
          _coach('unverified', verified: false),
          _coach('online-only', mode: TeachingMode.online),
          _coach('pricey', rate: 1500),
          _coach('advanced', skillLevels: {'advanced'}),
          _coach(
            'no-spec',
            specialties: const ['yoga'],
            mode: TeachingMode.online,
          ),
        ],
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const FindCoachFilter(
          verifiedOnly: true,
          teachingMode: 'onsite',
          maxHourlyRate: 1000,
          skillLevel: 'beginner',
          specialties: ['badminton'],
        ),
        offset: 0,
      );
      // Only 'ok' survives — but it has no specialties either... 'ok' was
      // built with empty specialties so it is dropped too.
      expect(page.coaches, isEmpty);

      final page2 = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const FindCoachFilter(
          verifiedOnly: true,
          teachingMode: 'onsite',
          maxHourlyRate: 1000,
          skillLevel: 'beginner',
        ),
        offset: 0,
      );
      // 'ok' (rate not listed) survives the cap; 'pricey' is dropped.
      expect(page2.coaches.map((c) => c.id), ['ok']);
    });

    test('stale request aborts and discards', () {
      var stale = false;
      final query = buildQuery(
        listCoaches: ({query, limit = 20, offset = 0}) async {
          stale = true;
          return [_coach('a')];
        },
      );

      expect(
        () => query.fetch(
          shared: const SportsDiscoveryFilter(),
          filter: const FindCoachFilter(),
          offset: 0,
          isStale: () => stale,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'STALE_FILTER_REQUEST',
          ),
        ),
      );
    });

    test('minRating10 uses the 1–10 aggregate and drops unrated', () async {
      final query = buildQuery(
        listCoaches: ({query, limit = 20, offset = 0}) async => [
          _coach('high', averageRating10: 8.4),
          _coach('low', averageRating10: 4.0),
          _coach('unrated'),
        ],
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const FindCoachFilter(minRating10: 7),
        offset: 0,
      );
      expect(page.coaches.map((c) => c.id), ['high']);
    });

    test('favoritesOnly and myCoachesOnly apply the relationship sets',
        () async {
      final query = buildQuery(
        listCoaches: ({query, limit = 20, offset = 0}) async => [
          _coach('fav'),
          _coach('mine'),
          _coach('other'),
        ],
      );

      final fav = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const FindCoachFilter(favoritesOnly: true),
        offset: 0,
        favoriteCoachIds: const {'fav'},
      );
      expect(fav.coaches.map((c) => c.id), ['fav']);

      final mine = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const FindCoachFilter(myCoachesOnly: true),
        offset: 0,
        myCoachIds: const {'mine'},
      );
      expect(mine.coaches.map((c) => c.id), ['mine']);

      // Signed-out viewers have empty relationship sets — the filters
      // hide everyone rather than leaking private favorites.
      final anon = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const FindCoachFilter(favoritesOnly: true),
        offset: 0,
      );
      expect(anon.coaches, isEmpty);
    });

    test('offeringType matches hydrated offering kinds', () async {
      final query = buildQuery(
        listCoaches: ({query, limit = 20, offset = 0}) async => [
          _coach('course', offeringTypes: {'course'}),
          _coach('slot', offeringTypes: {'one_on_one'}),
          _coach('both', offeringTypes: {'course', 'group_class'}),
        ],
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const FindCoachFilter(offeringType: 'course'),
        offset: 0,
      );
      expect(page.coaches.map((c) => c.id), ['course', 'both']);
    });

    test('location-enabled sorts by nearest service area', () async {
      final query = buildQuery(
        listCoaches: ({query, limit = 20, offset = 0}) async => [
          _coach(
            'far',
            areas: const [CoachServiceArea(lat: 14.0, lng: 100.5)],
          ),
          _coach(
            'near',
            areas: const [CoachServiceArea(lat: 13.751, lng: 100.5)],
          ),
        ],
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(
          locationEnabled: true,
          radiusKm: 500,
        ),
        filter: const FindCoachFilter(),
        offset: 0,
        userLat: 13.75,
        userLng: 100.5,
      );
      expect(page.coaches.map((c) => c.id), ['near', 'far']);
    });
  });
}
