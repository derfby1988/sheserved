import 'package:flutter_test/flutter_test.dart';

import 'package:sheserved/features/sport_club/book_court/application/book_court_query.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/domain/book_court_filter.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_discovery_filter.dart';

VenueSummary _venue(
  String id, {
  String? province,
  String? district,
  double? lat,
  double? lng,
  double? rating,
  Set<String> amenities = const {},
}) => VenueSummary(
  id: id,
  name: 'Venue $id',
  province: province,
  district: district,
  lat: lat,
  lng: lng,
  averageRating: rating,
  amenityIds: amenities,
);

void main() {
  group('BookCourtQuery', () {
    BookCourtQuery buildQuery({
      required Future<List<VenueSummary>> Function({
        String? sportId,
        String? province,
        String? district,
        String? query,
        int limit,
        int offset,
      })
      listVenues,
      Set<String> bookedIds = const {},
      Set<String> managedIds = const {},
      int pageSize = 20,
    }) {
      return BookCourtQuery(
        listVenues: listVenues,
        hydrateVenues: (venues) async => venues,
        bookedVenueIds: (_) async => bookedIds,
        managedVenueIds: (_) async => managedIds,
        pageSize: pageSize,
      );
    }

    test('passes shared filter values to the data source', () async {
      String? gotSport, gotProvince, gotDistrict, gotQuery;
      final query = buildQuery(
        listVenues: ({
          sportId,
          province,
          district,
          query,
          limit = 50,
          offset = 0,
        }) async {
          gotSport = sportId;
          gotProvince = province;
          gotDistrict = district;
          gotQuery = query;
          return [];
        },
      );

      await query.fetch(
        shared: const SportsDiscoveryFilter(
          sportId: 's1',
          province: 'p',
          district: 'd',
          query: 'court',
        ),
        filter: const BookCourtFilter(),
        offset: 0,
      );
      expect(gotSport, 's1');
      expect(gotProvince, 'p');
      expect(gotDistrict, 'd');
      expect(gotQuery, 'court');
    });

    test('domain filter fields are never sent to the venue list query',
        () async {
      var calls = 0;
      final query = buildQuery(
        listVenues: ({
          sportId,
          province,
          district,
          query,
          limit = 50,
          offset = 0,
        }) async {
          calls++;
          return [_venue('v1')];
        },
      );

      // BookCourtFilter.date/minPrice exist in the domain filter but are
      // applied client-side; the list RPC receives only shared fields.
      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: BookCourtFilter(
          date: DateTime(2026, 1, 1),
          minPrice: 100,
          courtType: 'grass',
        ),
        offset: 0,
      );
      expect(calls, greaterThan(0));
      expect(page.venues, hasLength(1));
    });

    test('stale requests throw and discard the page', () async {
      var stale = false;
      final query = buildQuery(
        listVenues: ({
          sportId,
          province,
          district,
          query,
          limit = 50,
          offset = 0,
        }) async {
          stale = true; // a newer request superseded this one mid-flight
          return [_venue('v1')];
        },
      );

      expect(
        () => query.fetch(
          shared: const SportsDiscoveryFilter(),
          filter: const BookCourtFilter(),
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

    test('bookedByMeOnly keeps only venues the user booked', () async {
      final query = buildQuery(
        listVenues: ({
          sportId,
          province,
          district,
          query,
          limit = 50,
          offset = 0,
        }) async =>
            [_venue('v1'), _venue('v2'), _venue('v3')],
        bookedIds: {'v2'},
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const BookCourtFilter(bookedByMeOnly: true),
        offset: 0,
        userId: 'u1',
      );
      expect(page.venues.map((v) => v.id), ['v2']);
    });

    test('personal filters yield an empty page without a user id', () async {
      var bookedLookups = 0;
      final query = BookCourtQuery(
        listVenues: ({
          sportId,
          province,
          district,
          query,
          limit = 50,
          offset = 0,
        }) async =>
            [_venue('v1'), _venue('v2')],
        hydrateVenues: (venues) async => venues,
        bookedVenueIds: (_) async {
          bookedLookups++;
          return {'v1'};
        },
        managedVenueIds: (_) async => const {},
      );

      // No userId -> the personal id set is never consulted and the
      // (logged-out) "booked by me" page is empty, never leaked data.
      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const BookCourtFilter(bookedByMeOnly: true),
        offset: 0,
      );
      expect(page.venues, isEmpty);
      expect(bookedLookups, 0);
    });

    test('radius filter drops venues outside the shared radius', () async {
      final query = buildQuery(
        listVenues: ({
          sportId,
          province,
          district,
          query,
          limit = 50,
          offset = 0,
        }) async => [
          _venue('near', lat: 13.756, lng: 100.502), // ~1 km away
          _venue('far', lat: 14.5, lng: 100.5), // ~80 km away
          _venue('no-geo'),
        ],
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(
          locationEnabled: true,
          radiusKm: 10,
        ),
        filter: const BookCourtFilter(),
        offset: 0,
        userLat: 13.75,
        userLng: 100.5,
      );
      expect(page.venues.map((v) => v.id), ['near']);
    });

    test('amenity and rating filters apply to hydrated venues', () async {
      final query = buildQuery(
        listVenues: ({
          sportId,
          province,
          district,
          query,
          limit = 50,
          offset = 0,
        }) async => [
          _venue('a', rating: 4.6, amenities: {'parking', 'shower'}),
          _venue('b', rating: 4.8, amenities: {'parking'}),
          _venue('c', rating: 3.0, amenities: {'parking', 'shower'}),
        ],
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const BookCourtFilter(
          amenityIds: {'parking', 'shower'},
          minRating: 4.0,
        ),
        offset: 0,
      );
      expect(page.venues.map((v) => v.id), ['a']);
    });

    test('keeps fetching until the visible page is full', () async {
      // 8 venues; the rating filter drops every second row so a single
      // upstream page can never fill a 4-slot visible page.
      final all = [
        for (var i = 0; i < 8; i++)
          _venue('v$i', rating: i.isEven ? 4.5 : 1.0),
      ];
      final offsets = <int>[];
      final query = buildQuery(
        listVenues: ({
          sportId,
          province,
          district,
          query,
          limit = 50,
          offset = 0,
        }) async {
          offsets.add(offset);
          return all.skip(offset).take(limit).toList();
        },
        pageSize: 4,
      );

      final page = await query.fetch(
        shared: const SportsDiscoveryFilter(),
        filter: const BookCourtFilter(minRating: 4.0),
        offset: 0,
      );
      expect(page.venues.map((v) => v.id), ['v0', 'v2', 'v4', 'v6']);
      expect(page.nextOffset, 8);
      expect(page.hasMore, isTrue);
      expect(offsets, [0, 4]);
    });
  });
}
