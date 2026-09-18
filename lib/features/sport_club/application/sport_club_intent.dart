/// Resolved route-intent for the sport-club page.
///
/// [recognized] is true when the route arguments carried a supported
/// `intent` + non-empty `groupId`, even if the group is not currently in the
/// feed — callers mark the intent handled either way so it is not retried.
typedef SportClubIntentResolution = ({
  bool recognized,
  String? kind,
  String? groupId,
  Map<String, dynamic>? group,
  bool requiresOwnerApproval,
});

/// Pure resolution of `/community/sport-club` route arguments.
///
/// Recognized intents: `join_group` (open the session picker) and
/// `review_pending` (open the group detail sheet). UI concerns — reading
/// `ModalRoute`, posting frame callbacks, opening sheets — stay in the page.
SportClubIntentResolution resolveSportClubIntent(
  Object? args,
  List<Map<String, dynamic>> groups,
  String? userId,
) {
  const none = (
    recognized: false,
    kind: null,
    groupId: null,
    group: null,
    requiresOwnerApproval: false,
  );
  if (args is! Map) return none;
  final kind = args['intent']?.toString();
  final groupId = args['groupId']?.toString();
  if (groupId == null ||
      groupId.isEmpty ||
      (kind != 'join_group' && kind != 'review_pending')) {
    return none;
  }
  final group = groups.cast<Map<String, dynamic>?>().firstWhere(
        (g) => g?['id']?.toString() == groupId,
        orElse: () => null,
      );
  final isGroupOwner = group != null &&
      userId != null &&
      (group['created_by']?.toString() ?? '').isNotEmpty &&
      group['created_by']?.toString() == userId;
  return (
    recognized: true,
    kind: kind,
    groupId: groupId,
    group: group,
    requiresOwnerApproval:
        group != null && group['requires_owner_approval'] == true && !isGroupOwner,
  );
}
