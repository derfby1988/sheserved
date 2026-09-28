import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/sports_hub_catalog_repository.dart';

/// Snapshot of the shared, ranked sport catalog for one Sports Hub session
/// (plan 21.7.13).
///
/// The shell owns exactly one instance. Ordering is computed once per load:
/// the ranked RPC ordering when it succeeds, otherwise the last successful
/// per-account order applied to a freshly fetched catalog, otherwise plain
/// Thai-name order. The list never reorders during a session unless [load]
/// is called again (hub mount or user change), so the chips never shuffle
/// while the user browses.
class SportsHubSportCatalog extends ChangeNotifier {
  SportsHubSportCatalog({
    Future<List<Map<String, dynamic>>> Function()? loadRankedSports,
    Future<List<Map<String, dynamic>>> Function()? loadApprovedSports,
    Future<bool> Function({
      required String eventId,
      required String sportId,
      required String domain,
      String? entityId,
    })? recordOpen,
    String? Function()? userIdProvider,
    Duration dedupeWindow = const Duration(hours: 24),
    Duration retryDelay = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _loadRankedSports = loadRankedSports,
       _loadApprovedSports = loadApprovedSports,
       _recordOpen = recordOpen,
       _userIdProvider = userIdProvider,
       _dedupeWindow = dedupeWindow,
       _retryDelay = retryDelay,
       _now = now ?? DateTime.now;

  final Future<List<Map<String, dynamic>>> Function()? _loadRankedSports;
  final Future<List<Map<String, dynamic>>> Function()? _loadApprovedSports;
  final Future<bool> Function({
    required String eventId,
    required String sportId,
    required String domain,
    String? entityId,
  })? _recordOpen;
  final String? Function()? _userIdProvider;
  final Duration _dedupeWindow;
  final Duration _retryDelay;
  final DateTime Function() _now;

  List<Map<String, dynamic>> _sports = const [];
  Set<String> _myCreatedSportIds = const {};
  bool _loaded = false;
  Object? _loadError;

  /// Last successful ranked order per account, used to keep the personal
  /// order when a ranking read fails later in the session.
  final Map<String, List<String>> _orderByAccount = {};

  /// `(domain|entity|sport)` -> last recorded open time, so reopening the
  /// same entity inside the dedupe window does not even hit the RPC.
  final Map<String, DateTime> _recentOpens = {};

  List<Map<String, dynamic>> get sports => _sports;
  Set<String> get myCreatedSportIds => _myCreatedSportIds;
  bool get isLoaded => _loaded;

  /// Non-null when every load path failed and there is no usable snapshot.
  /// The bar should surface retry instead of pretending the empty catalog
  /// is a real result.
  Object? get loadError =>
      (_loadError != null && _sports.isEmpty) ? _loadError : null;

  SportsHubCatalogRepository get _repository =>
      SportsHubCatalogRepository(Supabase.instance.client);

  String get _accountKey => _userIdProvider?.call() ?? '';

  /// Loads (or reloads) the ranked catalog for the current account.
  /// Ranking failures fall back to the account's cached order or the plain
  /// approved list — never to an empty or reordered mid-session bar.
  Future<void> load() async {
    try {
      final ranked = await (_loadRankedSports?.call() ??
          _repository.listRankedApprovedSports(
            _userIdProvider?.call(),
          ));
      _sports = List.unmodifiable(ranked.map(Map<String, dynamic>.from));
      _orderByAccount[_accountKey] = _sportIds(_sports);
      _loaded = true;
      _loadError = null;
      notifyListeners();
      return;
    } catch (_) {}

    try {
      final base = await (_loadApprovedSports?.call() ??
          _repository.listApprovedSports());
      final cachedOrder = _orderByAccount[_accountKey];
      _sports = List.unmodifiable(
        (cachedOrder == null ? base : _applyOrder(base, cachedOrder))
            .map(Map<String, dynamic>.from),
      );
      _loaded = true;
      _loadError = null;
      notifyListeners();
    } catch (e) {
      // Keep the previous snapshot — a failed reload must not clear the bar.
      _loaded = true;
      _loadError = e;
      if (_sports.isEmpty) notifyListeners();
    }
  }

  /// Badges for sports the buddy-page user created. Published by the Find
  /// Buddies page which owns the membership snapshot.
  void setMyCreatedSportIds(Set<String> ids) {
    if (setEquals(ids, _myCreatedSportIds)) return;
    _myCreatedSportIds = ids;
    notifyListeners();
  }

  /// Records a user detail-open of [entityId] for each sport in [sportIds].
  /// Fire-and-forget: failures are retried once with the same event id and
  /// never block the caller. Guests are not tracked.
  void recordDetailOpen({
    required String domain,
    required String? entityId,
    required Iterable<String> sportIds,
  }) {
    final userId = _userIdProvider?.call();
    if (userId == null || userId.isEmpty) return;
    final now = _now();
    for (final sportId in sportIds) {
      if (sportId.isEmpty) continue;
      final key = '$domain|$entityId|$sportId';
      final last = _recentOpens[key];
      if (last != null && now.difference(last) < _dedupeWindow) continue;
      _recentOpens[key] = now;
      unawaited(
        _recordOnce(
          userId: userId,
          eventId: const Uuid().v4(),
          sportId: sportId,
          domain: domain,
          entityId: entityId,
        ),
      );
    }
  }

  Future<void> _recordOnce({
    required String userId,
    required String eventId,
    required String sportId,
    required String domain,
    String? entityId,
    bool retried = false,
  }) async {
    try {
      await (_recordOpen?.call(
            eventId: eventId,
            sportId: sportId,
            domain: domain,
            entityId: entityId,
          ) ??
          _repository.recordDetailOpen(
            userId: userId,
            eventId: eventId,
            sportId: sportId,
            domain: domain,
            entityId: entityId,
          ));
    } catch (_) {
      if (retried) return;
      unawaited(
        Future.delayed(_retryDelay, () {
          _recordOnce(
            userId: userId,
            eventId: eventId,
            sportId: sportId,
            domain: domain,
            entityId: entityId,
            retried: true,
          );
        }),
      );
    }
  }

  /// Reorders [sports] to a previously fetched ranked [order]; sports missing
  /// from it keep their deterministic name/id tail position.
  List<Map<String, dynamic>> _applyOrder(
    List<Map<String, dynamic>> sports,
    List<String> order,
  ) {
    final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
    final sorted = List<Map<String, dynamic>>.from(sports);
    sorted.sort((a, b) {
      final ra = rank[a['id']?.toString()] ?? 1 << 30;
      final rb = rank[b['id']?.toString()] ?? 1 << 30;
      if (ra != rb) return ra.compareTo(rb);
      final an = a['name_th']?.toString() ?? '';
      final bn = b['name_th']?.toString() ?? '';
      final byName = an.compareTo(bn);
      if (byName != 0) return byName;
      return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
    });
    return sorted;
  }

  List<String> _sportIds(List<Map<String, dynamic>> sports) =>
      sports.map((s) => s['id']?.toString() ?? '').toList();

  @override
  void dispose() {
    _recentOpens.clear();
    super.dispose();
  }
}
