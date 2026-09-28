import 'package:flutter_test/flutter_test.dart';

import 'package:sheserved/features/sport_club/shared/application/sports_hub_sport_catalog.dart';

Map<String, dynamic> _sport(String id, [String? name]) => {
  'id': id,
  'name_th': name ?? id,
};

List<String> _ids(Iterable<Map<String, dynamic>> rows) =>
    rows.map((r) => r['id'] as String).toList();

void main() {
  group('SportsHubSportCatalog.load', () {
    test('uses ranked order from the RPC path', () async {
      final catalog = SportsHubSportCatalog(
        userIdProvider: () => 'u1',
        loadRankedSports: () async =>
            [_sport('s2'), _sport('s1'), _sport('s3')],
        loadApprovedSports: () async => [_sport('s1'), _sport('s2')],
      );

      await catalog.load();

      expect(_ids(catalog.sports), ['s2', 's1', 's3']);
      expect(catalog.isLoaded, isTrue);
    });

    test('falls back to plain approved list when ranking fails', () async {
      final catalog = SportsHubSportCatalog(
        userIdProvider: () => 'u1',
        loadRankedSports: () async => throw Exception('rpc down'),
        loadApprovedSports: () async => [_sport('s1'), _sport('s2')],
      );

      await catalog.load();

      expect(_ids(catalog.sports), ['s1', 's2']);
      expect(catalog.isLoaded, isTrue);
    });

    test(
      'applies the account cached order when a later ranking read fails',
      () async {
        var failRanked = false;
        final catalog = SportsHubSportCatalog(
          userIdProvider: () => 'u1',
          loadRankedSports: () async {
            if (failRanked) throw Exception('rpc down');
            return [_sport('s3'), _sport('s1')];
          },
          // The plain list returns Thai order (s1, s2, s3) plus a new sport.
          loadApprovedSports: () async =>
              [_sport('s1'), _sport('s2'), _sport('s3')],
        );

        await catalog.load();
        expect(_ids(catalog.sports), ['s3', 's1']);

        failRanked = true;
        await catalog.load();

        // s3/s1 keep their ranked positions; the new sport s2 joins the tail.
        expect(_ids(catalog.sports), ['s3', 's1', 's2']);
      },
    );

    test('keeps the previous snapshot when every load path fails', () async {
      var failAll = false;
      final catalog = SportsHubSportCatalog(
        userIdProvider: () => 'u1',
        loadRankedSports: () async {
          if (failAll) throw Exception('down');
          return [_sport('s1')];
        },
        loadApprovedSports: () async {
          if (failAll) throw Exception('down');
          return [_sport('s1')];
        },
      );

      await catalog.load();
      failAll = true;
      await catalog.load();

      expect(_ids(catalog.sports), ['s1']);
      expect(catalog.isLoaded, isTrue);
    });

    test('keeps ranked orders isolated per account', () async {
      var userId = 'u1';
      final catalog = SportsHubSportCatalog(
        userIdProvider: () => userId,
        loadRankedSports: () async =>
            userId == 'u1' ? [_sport('s2'), _sport('s1')] : [_sport('s1')],
        loadApprovedSports: () async => [_sport('s1'), _sport('s2')],
      );

      await catalog.load();
      expect(_ids(catalog.sports), ['s2', 's1']);

      userId = 'u2';
      await catalog.load();
      expect(_ids(catalog.sports), ['s1']);
    });
  });

  group('SportsHubSportCatalog.recordDetailOpen', () {
    test('records one RPC call per sport and skips guests', () async {
      final calls = <String>[];
      var userId = 'u1';
      final catalog = SportsHubSportCatalog(
        userIdProvider: () => userId,
        recordOpen:
            ({
              required String eventId,
              required String sportId,
              required String domain,
              String? entityId,
            }) async {
              calls.add('$domain|$entityId|$sportId');
              return true;
            },
      );

      userId = '';
      catalog.recordDetailOpen(
        domain: 'buddies',
        entityId: 'g1',
        sportIds: const ['s1'],
      );
      expect(calls, isEmpty);

      userId = 'u1';
      catalog.recordDetailOpen(
        domain: 'courts',
        entityId: 'v1',
        sportIds: const ['s1', 's2'],
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['courts|v1|s1', 'courts|v1|s2']);
    });

    test('dedupes reopening the same entity inside the window', () async {
      var calls = 0;
      var now = DateTime(2026, 9, 28, 12);
      final catalog = SportsHubSportCatalog(
        userIdProvider: () => 'u1',
        now: () => now,
        recordOpen:
            ({
              required String eventId,
              required String sportId,
              required String domain,
              String? entityId,
            }) async {
              calls++;
              return true;
            },
      );

      catalog.recordDetailOpen(
        domain: 'coaches',
        entityId: 'c1',
        sportIds: const ['s1'],
      );
      now = now.add(const Duration(hours: 1));
      catalog.recordDetailOpen(
        domain: 'coaches',
        entityId: 'c1',
        sportIds: const ['s1'],
      );
      // Same entity in another domain still counts (page-balanced input).
      catalog.recordDetailOpen(
        domain: 'buddies',
        entityId: 'c1',
        sportIds: const ['s1'],
      );

      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);

      // Outside the 24h window the same entity counts again.
      now = now.add(const Duration(hours: 24));
      catalog.recordDetailOpen(
        domain: 'coaches',
        entityId: 'c1',
        sportIds: const ['s1'],
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 3);
    });

    test('retries once with the same event id and never throws', () async {
      final eventIds = <String>[];
      var failFirst = true;
      final catalog = SportsHubSportCatalog(
        userIdProvider: () => 'u1',
        retryDelay: Duration.zero,
        recordOpen:
            ({
              required String eventId,
              required String sportId,
              required String domain,
              String? entityId,
            }) async {
              eventIds.add(eventId);
              if (failFirst) {
                failFirst = false;
                throw Exception('network');
              }
              return true;
            },
      );

      catalog.recordDetailOpen(
        domain: 'buddies',
        entityId: 'g1',
        sportIds: const ['s1'],
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(eventIds.length, 2);
      expect(eventIds[0], eventIds[1]);
    });
  });
}
