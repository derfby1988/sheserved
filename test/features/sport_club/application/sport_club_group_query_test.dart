import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/application/sport_club_group_query.dart';
import 'package:sheserved/features/sport_club/domain/sport_club_filter.dart';

Map<String, dynamic> mkGroup(String id, {double? lat, double? lng}) {
  final group = <String, dynamic>{'id': id};
  if (lat != null) {
    group['lat'] = lat;
  }
  if (lng != null) {
    group['lng'] = lng;
  }
  return group;
}

/// Builds a query whose listGroups serves [pages] by offset (each page is a
/// fixed-size chunk) and whose session-id lookups return the given sets.
SportClubGroupQuery makeQuery(
  List<List<Map<String, dynamic>>> pages, {
  Set<String> Function(List<String>)? anySessions,
  Set<String> Function(List<String>)? upcomingSessions,
  int pageSize = 3,
  List<int>? offsets,
}) {
  return SportClubGroupQuery(
    pageSize: pageSize,
    listGroups: ({
      sportId,
      q,
      province,
      district,
      openOnly = false,
      limit = 50,
      offset = 0,
    }) async {
      offsets?.add(offset);
      final index = offset ~/ pageSize;
      return index < pages.length ? pages[index] : <Map<String, dynamic>>[];
    },
    idsWithAnySessions: (ids) async =>
        anySessions?.call(ids) ?? ids.toSet(),
    idsWithUpcomingSessions: (ids) async =>
        upcomingSessions?.call(ids) ?? ids.toSet(),
  );
}

const noSets = <String>{};

void main() {
  group('SportClubGroupQuery.fetch', () {
    test('empty first page yields no groups and hasMore false', () async {
      final q = makeQuery([[]]);
      final page = await q.fetch(
        filter: const SportClubFilter(),
        offset: 0,
        adminIds: noSets,
        joinedGroupIds: noSets,
        blockedGroupIds: noSets,
      );
      expect(page.groups, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextOffset, 0);
    });

    test('returns a full page and advances nextOffset', () async {
      final q = makeQuery([
        [mkGroup('a'), mkGroup('b'), mkGroup('c')],
      ]);
      final page = await q.fetch(
        filter: const SportClubFilter(),
        offset: 0,
        adminIds: noSets,
        joinedGroupIds: noSets,
        blockedGroupIds: noSets,
      );
      expect(page.groups.map((g) => g['id']), ['a', 'b', 'c']);
      expect(page.nextOffset, 3);
      expect(page.hasMore, isTrue);
    });

    test('short last page ends pagination', () async {
      final q = makeQuery([
        [mkGroup('a'), mkGroup('b')],
      ]);
      final page = await q.fetch(
        filter: const SportClubFilter(),
        offset: 0,
        adminIds: noSets,
        joinedGroupIds: noSets,
        blockedGroupIds: noSets,
      );
      expect(page.groups.length, 2);
      expect(page.hasMore, isFalse);
      expect(page.nextOffset, 2);
    });

    test('groups without sessions are hidden from regular users', () async {
      final q = makeQuery(
        [
          [mkGroup('a'), mkGroup('b'), mkGroup('c')],
        ],
        anySessions: (ids) => {'a', 'c'},
      );
      final page = await q.fetch(
        filter: const SportClubFilter(),
        offset: 0,
        adminIds: noSets,
        joinedGroupIds: noSets,
        blockedGroupIds: noSets,
      );
      expect(page.groups.map((g) => g['id']), ['a', 'c']);
    });

    test('joined/managed/blocked groups stay visible without sessions',
        () async {
      final q = makeQuery(
        [
          [mkGroup('a'), mkGroup('b'), mkGroup('c'), mkGroup('d')],
        ],
        anySessions: (ids) => <String>{},
      );
      final page = await q.fetch(
        filter: const SportClubFilter(),
        offset: 0,
        adminIds: {'b'},
        joinedGroupIds: {'c'},
        blockedGroupIds: {'d'},
      );
      expect(page.groups.map((g) => g['id']), ['b', 'c', 'd']);
    });

    test('joinedOnly and managedOnly combine as OR', () async {
      final q = makeQuery(
        [
          [mkGroup('a'), mkGroup('b'), mkGroup('c')],
        ],
        anySessions: (ids) => ids.toSet(),
      );
      final page = await q.fetch(
        filter: const SportClubFilter(joinedOnly: true, managedOnly: true),
        offset: 0,
        adminIds: {'a'},
        joinedGroupIds: {'c'},
        blockedGroupIds: noSets,
      );
      expect(page.groups.map((g) => g['id']), ['a', 'c']);
    });

    test('openOnly requires upcoming sessions for non-members', () async {
      final q = makeQuery(
        [
          [mkGroup('a'), mkGroup('b')],
        ],
        upcomingSessions: (ids) => {'b'},
      );
      final page = await q.fetch(
        filter: const SportClubFilter(openOnly: true),
        offset: 0,
        adminIds: noSets,
        joinedGroupIds: noSets,
        blockedGroupIds: noSets,
      );
      expect(page.groups.map((g) => g['id']), ['b']);
    });

    test('site admin sees every group regardless of sessions', () async {
      final q = makeQuery(
        [
          [mkGroup('a'), mkGroup('b')],
        ],
        anySessions: (ids) => <String>{},
      );
      final page = await q.fetch(
        filter: const SportClubFilter(),
        offset: 0,
        adminIds: noSets,
        joinedGroupIds: noSets,
        blockedGroupIds: noSets,
        isAdmin: true,
      );
      expect(page.groups.length, 2);
    });

    test('groupIdsWithAnySessions exposes only visible group ids', () async {
      final q = makeQuery(
        [
          [mkGroup('a'), mkGroup('b'), mkGroup('c'), mkGroup('d')],
        ],
        // 'b' has sessions but is invisible; 'c' is joined without sessions.
        anySessions: (ids) => {'a', 'b'},
        upcomingSessions: (ids) => <String>{},
      );
      final page = await q.fetch(
        filter: const SportClubFilter(openOnly: true),
        offset: 0,
        adminIds: noSets,
        joinedGroupIds: {'c'},
        blockedGroupIds: noSets,
      );
      expect(page.groups.map((g) => g['id']), ['c']);
      expect(page.groupIdsWithAnySessions, isEmpty);
    });

    test('groupIdsWithAnySessions accumulates across raw pages', () async {
      final q = makeQuery(
        [
          [mkGroup('x'), mkGroup('a'), mkGroup('b')],
          [mkGroup('c'), mkGroup('d'), mkGroup('e')],
        ],
        anySessions: (ids) =>
            ids.where((id) => id != 'x' && id != 'e').toSet(),
      );
      final page = await q.fetch(
        filter: const SportClubFilter(),
        offset: 0,
        adminIds: noSets,
        joinedGroupIds: noSets,
        blockedGroupIds: noSets,
      );
      expect(page.groups.map((g) => g['id']), ['a', 'b', 'c', 'd']);
      expect(page.groupIdsWithAnySessions, {'a', 'b', 'c', 'd'});
    });

    test('keeps fetching later pages until the visible page fills', () async {
      final offsets = <int>[];
      final q = makeQuery(
        [
          [mkGroup('x'), mkGroup('y'), mkGroup('z')],
          [mkGroup('a'), mkGroup('b'), mkGroup('c')],
        ],
        anySessions: (ids) => {'a', 'b'},
        offsets: offsets,
      );
      final page = await q.fetch(
        filter: const SportClubFilter(),
        offset: 0,
        adminIds: noSets,
        joinedGroupIds: noSets,
        blockedGroupIds: noSets,
      );
      expect(page.groups.map((g) => g['id']), ['a', 'b']);
      expect(offsets, [0, 3, 6]);
      expect(page.nextOffset, 6);
      expect(page.hasMore, isFalse);
    });

    test('location filter drops far groups and sorts by distance', () async {
      final q = makeQuery(
        [
          [
            mkGroup('far', lat: 20, lng: 20),
            mkGroup('near', lat: 0.01, lng: 0.01),
            mkGroup('mid', lat: 0.05, lng: 0.05),
          ],
        ],
        anySessions: (ids) => ids.toSet(),
      );
      final page = await q.fetch(
        filter: const SportClubFilter(locationEnabled: true, radiusKm: 15),
        offset: 0,
        adminIds: noSets,
        joinedGroupIds: noSets,
        blockedGroupIds: noSets,
        userLat: 0,
        userLng: 0,
      );
      expect(page.groups.map((g) => g['id']), ['near', 'mid']);
    });

    test('stale request throws StateError', () async {
      final q = makeQuery([
        [mkGroup('a'), mkGroup('b'), mkGroup('c')],
      ]);
      expect(
        () => q.fetch(
          filter: const SportClubFilter(),
          offset: 0,
          adminIds: noSets,
          joinedGroupIds: noSets,
          blockedGroupIds: noSets,
          isStale: () => true,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
