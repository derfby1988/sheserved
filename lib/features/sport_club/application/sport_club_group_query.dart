import '../domain/sport_club_filter.dart';
import '../presentation/widgets/sport_club_utils.dart';

/// One page of visible groups plus pagination state.
class SportClubGroupPage {
  final List<Map<String, dynamic>> groups;
  final int nextOffset;
  final bool hasMore;

  /// IDs of groups in [groups] that have at least one session of any state
  /// (including ended). Exposed for card hydration so cards don't re-query
  /// `hasAnySessions` per group.
  final Set<String> groupIdsWithAnySessions;

  const SportClubGroupPage({
    required this.groups,
    required this.nextOffset,
    required this.hasMore,
    this.groupIdsWithAnySessions = const {},
  });
}

typedef SportClubListGroups = Future<List<Map<String, dynamic>>> Function({
  String? sportId,
  String? q,
  String? province,
  String? district,
  bool openOnly,
  int limit,
  int offset,
});

typedef SportClubSessionGroupIds = Future<Set<String>> Function(
  List<String> groupIds,
);

/// Feed query/pagination logic for the sport-club group list.
///
/// Pure with respect to widget state: every input arrives via parameters and
/// the repository surface is injected as callbacks, so the query can be unit
/// tested without a Supabase client.
class SportClubGroupQuery {
  final SportClubListGroups listGroups;
  final SportClubSessionGroupIds idsWithAnySessions;
  final SportClubSessionGroupIds idsWithUpcomingSessions;
  final int pageSize;

  const SportClubGroupQuery({
    required this.listGroups,
    required this.idsWithAnySessions,
    required this.idsWithUpcomingSessions,
    this.pageSize = 10,
  });

  /// Fetches up to [pageSize] visible groups starting at [offset].
  ///
  /// [isStale] is polled between async steps; when it returns true the query
  /// throws `StateError('STALE_FILTER_REQUEST')` so callers can discard
  /// superseded results.
  Future<SportClubGroupPage> fetch({
    required SportClubFilter filter,
    required int offset,
    required Set<String> adminIds,
    required Set<String> joinedGroupIds,
    required Set<String> blockedGroupIds,
    bool isAdmin = false,
    double? userLat,
    double? userLng,
    bool Function()? isStale,
  }) async {
    var nextOffset = offset;
    var hasMore = true;
    final visibleGroups = <Map<String, dynamic>>[];
    final allIdsWithAnySessions = <String>{};

    while (visibleGroups.length < pageSize && hasMore) {
      final page = await listGroups(
        sportId: filter.sportId,
        q: filter.q,
        openOnly: filter.openOnly,
        province: filter.province,
        district: filter.district,
        limit: pageSize,
        offset: nextOffset,
      );
      if (isStale?.call() == true) {
        throw StateError('STALE_FILTER_REQUEST');
      }
      if (page.isEmpty) {
        hasMore = false;
        break;
      }

      nextOffset += page.length;
      hasMore = page.length >= pageSize;
      final locationFiltered = applyLocationFilter(
        page,
        locationEnabled: filter.locationEnabled,
        userLat: userLat,
        userLng: userLng,
        radiusKm: filter.radiusKm,
      );
      final groupIds = locationFiltered
          .map((g) => g['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      // ผู้ใช้ทั่วไปเห็นทุกก๊วนที่มีรอบนัด (รวมรอบที่สิ้นสุดแล้ว)
      final groupIdsWithAnySessions = await idsWithAnySessions(groupIds);
      allIdsWithAnySessions.addAll(groupIdsWithAnySessions);
      // เมื่อกด filter "ยังเปิดรับ" ให้แสดงเฉพาะก๊วนที่ยังมีรอบนัดไม่สิ้นสุด
      final groupIdsWithUpcomingSessions = filter.openOnly
          ? await idsWithUpcomingSessions(groupIds)
          : null;
      if (isStale?.call() == true) {
        throw StateError('STALE_FILTER_REQUEST');
      }

      visibleGroups.addAll(
        locationFiltered.where((group) {
          final groupId = group['id']?.toString() ?? '';
          final isManaged = isAdmin || adminIds.contains(groupId);
          final isJoined = joinedGroupIds.contains(groupId);
          final matchesPersonalFilter =
              (!filter.joinedOnly && !filter.managedOnly) ||
              (filter.joinedOnly && isJoined) ||
              (filter.managedOnly && isManaged) ||
              (filter.joinedOnly &&
                  filter.managedOnly &&
                  (isJoined || isManaged));
          if (!matchesPersonalFilter) return false;
          if (isAdmin ||
              isManaged ||
              isJoined ||
              blockedGroupIds.contains(groupId)) {
            return true;
          }
          if (filter.openOnly) {
            return groupIdsWithUpcomingSessions?.contains(groupId) ?? false;
          }
          return groupIdsWithAnySessions.contains(groupId);
        }),
      );
    }

    sortGroupsByDistance(
      visibleGroups,
      locationEnabled: filter.locationEnabled,
      userLat: userLat,
      userLng: userLng,
    );
    final visibleIds = visibleGroups
        .map((g) => g['id']?.toString() ?? '')
        .toSet();
    return SportClubGroupPage(
      groups: visibleGroups,
      nextOffset: nextOffset,
      hasMore: hasMore,
      groupIdsWithAnySessions: allIdsWithAnySessions
          .intersection(visibleIds),
    );
  }
}
