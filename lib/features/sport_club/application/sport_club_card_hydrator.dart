/// Fully-hydrated, render-ready data for a single [GroupCard].
///
/// Produced at page level by [SportClubCardHydrator] so the card widget can
/// render synchronously without issuing per-card repository requests.
class SportClubGroupCardData {
  const SportClubGroupCardData({
    this.upcomingSessions = const [],
    this.hasAnySessions = false,
    this.groupFees = const [],
    this.costItemsBySession = const {},
    this.groupPositions = const [],
    this.sessionError,
  });

  /// Upcoming sessions sorted ascending by `starts_at` (booking summaries
  /// attached by the repository).
  final List<Map<String, dynamic>> upcomingSessions;

  /// Whether the group has any session at all, including already-ended ones
  /// (drives the 'ยังไม่มีรอบนัด' vs 'รอบนัดล่าสุดสิ้นสุดแล้ว' wording).
  final bool hasAnySessions;

  /// Standard group fees (`fitness_group_fees_public`).
  final List<Map<String, dynamic>> groupFees;

  /// Session cost items grouped by `session_id`
  /// (`fitness_session_cost_items_public`).
  final Map<String, List<Map<String, dynamic>>> costItemsBySession;

  /// Field-position lineup (`fitness_group_positions_public`).
  final List<Map<String, dynamic>> groupPositions;

  /// Non-null when the sessions request failed; the card shows the error
  /// text instead of session/CTA content (mirrors the old FutureBuilder
  /// error branch).
  final Object? sessionError;

  static const empty = SportClubGroupCardData();
}

/// One batched repository query covering a list of group ids.
typedef SportClubCardBatchQuery =
    Future<List<Map<String, dynamic>>> Function(List<String> groupIds);

/// Batches the per-card secondary queries (upcoming sessions, group fees,
/// session cost items, positions) into one request per dataset for the
/// whole visible page, then groups the rows per group.
///
/// Error semantics mirror the old per-card `Future.wait`:
/// - sessions failure → every card of the batch gets [sessionError] set;
/// - fees / cost items / positions failure → that dataset degrades to empty.
class SportClubCardHydrator {
  const SportClubCardHydrator({
    required this.upcomingSessionsForGroups,
    required this.groupFeesForGroups,
    required this.sessionCostItemsForGroups,
    required this.groupPositionsForGroups,
  });

  final SportClubCardBatchQuery upcomingSessionsForGroups;
  final SportClubCardBatchQuery groupFeesForGroups;
  final SportClubCardBatchQuery sessionCostItemsForGroups;
  final SportClubCardBatchQuery groupPositionsForGroups;

  /// Returns render-ready data keyed by group id for every id in [groupIds].
  ///
  /// [groupIdsWithAnySessions] is metadata already computed by
  /// [SportClubGroupQuery] — groups that have at least one session of any
  /// state — so cards don't re-query `hasAnySessions` individually.
  Future<Map<String, SportClubGroupCardData>> hydrate({
    required List<String> groupIds,
    required Set<String> groupIdsWithAnySessions,
  }) async {
    final result = <String, SportClubGroupCardData>{};
    if (groupIds.isEmpty) return result;

    Object? sessionError;
    final sessionsF = upcomingSessionsForGroups(groupIds).then(
      (rows) => rows,
      onError: (Object e) {
        sessionError = e;
        return <Map<String, dynamic>>[];
      },
    );
    final feesF = groupFeesForGroups(groupIds).then(
      (rows) => rows,
      onError: (_) => <Map<String, dynamic>>[],
    );
    final costItemsF = sessionCostItemsForGroups(groupIds).then(
      (rows) => rows,
      onError: (_) => <Map<String, dynamic>>[],
    );
    final positionsF = groupPositionsForGroups(groupIds).then(
      (rows) => rows,
      onError: (_) => <Map<String, dynamic>>[],
    );

    final sessions = await sessionsF;
    final fees = await feesF;
    final costItems = await costItemsF;
    final positions = await positionsF;

    final sessionsByGroup = _byGroupId(sessions);
    final feesByGroup = _byGroupId(fees);
    final positionsByGroup = _byGroupId(positions);

    for (final rows in sessionsByGroup.values) {
      rows.sort(_compareStartsAt);
    }

    for (final gid in groupIds) {
      final upcoming = sessionsByGroup[gid] ?? const <Map<String, dynamic>>[];
      final itemsBySession = <String, List<Map<String, dynamic>>>{};
      for (final item in costItems) {
        if (item['group_id']?.toString() != gid) continue;
        final sid = item['session_id']?.toString() ?? '';
        if (sid.isNotEmpty) {
          itemsBySession.putIfAbsent(sid, () => []).add(item);
        }
      }
      result[gid] = SportClubGroupCardData(
        upcomingSessions: upcoming,
        hasAnySessions:
            upcoming.isNotEmpty || groupIdsWithAnySessions.contains(gid),
        groupFees: feesByGroup[gid] ?? const <Map<String, dynamic>>[],
        costItemsBySession: itemsBySession,
        groupPositions:
            positionsByGroup[gid] ?? const <Map<String, dynamic>>[],
        sessionError: sessionError,
      );
    }
    return result;
  }

  static Map<String, List<Map<String, dynamic>>> _byGroupId(
    List<Map<String, dynamic>> rows,
  ) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final gid = row['group_id']?.toString() ?? '';
      if (gid.isNotEmpty) out.putIfAbsent(gid, () => []).add(row);
    }
    return out;
  }

  static int _compareStartsAt(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aStart = DateTime.tryParse(a['starts_at']?.toString() ?? '');
    final bStart = DateTime.tryParse(b['starts_at']?.toString() ?? '');
    if (aStart == null && bStart == null) return 0;
    if (aStart == null) return 1;
    if (bStart == null) return -1;
    return aStart.compareTo(bStart);
  }
}
