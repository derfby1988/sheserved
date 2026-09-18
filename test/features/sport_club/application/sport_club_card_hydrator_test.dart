import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/application/sport_club_card_hydrator.dart';

Map<String, dynamic> mkSession(
  String id,
  String groupId,
  String startsAt,
) => {'id': id, 'group_id': groupId, 'starts_at': startsAt};

Map<String, dynamic> mkRow(String groupId, [Map<String, dynamic>? extra]) => {
  'group_id': groupId,
  ...?extra,
};

void main() {
  group('SportClubCardHydrator.hydrate', () {
    test('returns empty map for empty groupIds without calling queries', () async {
      var called = 0;
      Future<List<Map<String, dynamic>>> query(List<String> ids) async {
        called++;
        return const [];
      }

      final hydrator = SportClubCardHydrator(
        upcomingSessionsForGroups: query,
        groupFeesForGroups: query,
        sessionCostItemsForGroups: query,
        groupPositionsForGroups: query,
      );
      final result = await hydrator.hydrate(
        groupIds: const [],
        groupIdsWithAnySessions: const {},
      );
      expect(result, isEmpty);
      expect(called, 0);
    });

    test('groups rows by group_id and sorts sessions by starts_at', () async {
      final hydrator = SportClubCardHydrator(
        upcomingSessionsForGroups: (ids) async => [
          mkSession('s2', 'a', '2026-01-03T10:00:00Z'),
          mkSession('s1', 'a', '2026-01-02T10:00:00Z'),
          mkSession('s3', 'b', '2026-01-01T10:00:00Z'),
        ],
        groupFeesForGroups: (ids) async => [
          mkRow('a', {'name': 'monthly'}),
        ],
        sessionCostItemsForGroups: (ids) async => [
          mkRow('a', {'session_id': 's1', 'name': 'court'}),
          mkRow('a', {'session_id': 's1', 'name': 'shuttlecock'}),
          mkRow('b', {'session_id': 's3', 'name': 'water'}),
        ],
        groupPositionsForGroups: (ids) async => [
          mkRow('b', {'label': 'GK', 'slots': 1}),
        ],
      );
      final result = await hydrator.hydrate(
        groupIds: ['a', 'b'],
        groupIdsWithAnySessions: {'a', 'b'},
      );

      expect(result.keys, {'a', 'b'});
      expect(
        result['a']!.upcomingSessions.map((s) => s['id']),
        ['s1', 's2'],
      );
      expect(result['a']!.groupFees.length, 1);
      expect(result['a']!.costItemsBySession['s1']!.length, 2);
      expect(result['b']!.upcomingSessions.map((s) => s['id']), ['s3']);
      expect(result['b']!.groupPositions.length, 1);
    });

    test('hasAnySessions comes from metadata or non-empty upcoming', () async {
      final hydrator = SportClubCardHydrator(
        upcomingSessionsForGroups: (ids) async => [
          mkSession('s1', 'b', '2026-01-01T10:00:00Z'),
        ],
        groupFeesForGroups: (_) async => const [],
        sessionCostItemsForGroups: (_) async => const [],
        groupPositionsForGroups: (_) async => const [],
      );
      final result = await hydrator.hydrate(
        groupIds: ['a', 'b', 'c'],
        groupIdsWithAnySessions: {'a'},
      );
      expect(result['a']!.hasAnySessions, isTrue); // ended sessions exist
      expect(result['b']!.hasAnySessions, isTrue); // has upcoming
      expect(result['c']!.hasAnySessions, isFalse);
    });

    test('session query failure sets sessionError on every card', () async {
      final error = StateError('boom');
      final hydrator = SportClubCardHydrator(
        upcomingSessionsForGroups: (_) async => throw error,
        groupFeesForGroups: (_) async => [mkRow('a')],
        sessionCostItemsForGroups: (_) async => const [],
        groupPositionsForGroups: (_) async => const [],
      );
      final result = await hydrator.hydrate(
        groupIds: ['a', 'b'],
        groupIdsWithAnySessions: {'a'},
      );
      expect(result['a']!.sessionError, same(error));
      expect(result['b']!.sessionError, same(error));
      // Non-session datasets still hydrate normally.
      expect(result['a']!.groupFees.length, 1);
      expect(result['a']!.hasAnySessions, isTrue);
    });

    test('optional dataset failures degrade to empty lists', () async {
      final hydrator = SportClubCardHydrator(
        upcomingSessionsForGroups: (_) async => [
          mkSession('s1', 'a', '2026-01-01T10:00:00Z'),
        ],
        groupFeesForGroups: (_) async => throw Exception('fees'),
        sessionCostItemsForGroups: (_) async => throw Exception('items'),
        groupPositionsForGroups: (_) async => throw Exception('positions'),
      );
      final result = await hydrator.hydrate(
        groupIds: ['a'],
        groupIdsWithAnySessions: const {},
      );
      expect(result['a']!.sessionError, isNull);
      expect(result['a']!.upcomingSessions.length, 1);
      expect(result['a']!.groupFees, isEmpty);
      expect(result['a']!.costItemsBySession, isEmpty);
      expect(result['a']!.groupPositions, isEmpty);
    });
  });
}
