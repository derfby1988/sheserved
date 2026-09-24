import 'package:flutter/foundation.dart';

import '../../book_court/domain/book_court_filter.dart';
import '../../domain/sport_club_filter.dart';
import '../../find_coach/domain/find_coach_filter.dart';
import '../domain/sports_discovery_filter.dart';
import '../domain/sports_hub_filter_state.dart';
import 'sports_hub_filter_store.dart';

/// Owns the Sports Hub filter state and persistence.
///
/// The shell ([SportsHubPage]) creates one controller and passes it to all
/// three pages. Pages read [state] and report user edits through the
/// `update*` methods; the controller notifies listeners so every page can
/// react to shared filter changes while keeping domain filters isolated.
///
/// The controller never runs domain queries itself — pages own their data.
class SportsHubController extends ChangeNotifier {
  SportsHubController({
    SportsHubFilterStore store = const SportsHubFilterStore(),
    String? Function()? userIdProvider,
  }) : _store = store,
       _userIdProvider = userIdProvider;

  final SportsHubFilterStore _store;
  final String? Function()? _userIdProvider;

  SportsHubFilterState _state = const SportsHubFilterState();
  bool _loaded = false;

  SportsHubFilterState get state => _state;
  SportsDiscoveryFilter get shared => _state.shared;
  SportBuddiesFilter get buddies => _state.buddies;
  BookCourtFilter get courts => _state.courts;
  FindCoachFilter get coaches => _state.coaches;
  bool get isLoaded => _loaded;

  String? get _userId => _userIdProvider?.call();

  /// Loads the persisted state for the current user. Safe to call more than
  /// once; later calls reload from storage (e.g. after user switch).
  Future<void> load() async {
    final saved = await _store.load(_userId);
    if (saved != null && saved != _state) {
      _state = saved;
      _loaded = true;
      notifyListeners();
      return;
    }
    _loaded = true;
  }

  void updateShared(SportsDiscoveryFilter next) {
    if (next == _state.shared) return;
    _commit(_state.copyWith(shared: next));
  }

  void updateBuddies(SportBuddiesFilter next) {
    if (next == _state.buddies) return;
    _commit(_state.copyWith(buddies: next));
  }

  void updateCourts(BookCourtFilter next) {
    if (next == _state.courts) return;
    _commit(_state.copyWith(courts: next));
  }

  void updateCoaches(FindCoachFilter next) {
    if (next == _state.coaches) return;
    _commit(_state.copyWith(coaches: next));
  }

  /// Call when the signed-in user changes. On logout (null id) all personal
  /// filters are deactivated; the shared filter stays untouched.
  void handleUserChanged(String? userId) {
    if (userId == null || userId.isEmpty) {
      final next = _state.deactivatePersonalFilters();
      if (next != _state) _commit(next);
    }
  }

  /// Adapts the hub state into the legacy [SportClubFilter] consumed by the
  /// Find Buddies page. Only shared values and buddies-domain toggles are
  /// carried over — court/coach fields can never leak into group queries.
  SportClubFilter toSportClubFilter() {
    return SportClubFilter(
      sportId: _state.shared.sportId,
      q: _state.shared.query,
      province: _state.shared.province,
      district: _state.shared.district,
      locationEnabled: _state.shared.locationEnabled,
      radiusKm: _state.shared.radiusKm,
      openOnly: _state.buddies.openOnly,
      joinedOnly: _state.buddies.joinedOnly,
      managedOnly: _state.buddies.managedOnly,
      allLevelsOnly: _state.buddies.allLevelsOnly,
      genderAnyOnly: _state.buddies.genderAnyOnly,
      noFeesOnly: _state.buddies.noFeesOnly,
    );
  }

  /// Seeds the hub state from a legacy [SportClubFilter] exactly once, and
  /// only while the hub still holds its untouched default state (i.e. the
  /// new `sports_hub_shared_filter_v1` namespace has no saved data yet).
  /// This migrates existing users' sport/location choices without
  /// overwriting a hub state that was already persisted.
  void seedFromSportClubFilter(SportClubFilter filter) {
    if (_seededFromLegacy) return;
    _seededFromLegacy = true;
    if (_state != const SportsHubFilterState()) return;
    absorbSportClubFilter(filter);
  }

  bool _seededFromLegacy = false;

  /// Applies an edit that originated inside the Find Buddies page back into
  /// the hub state, splitting shared fields from buddies-domain toggles.
  void absorbSportClubFilter(SportClubFilter filter) {
    final nextShared = _state.shared.copyWith(
      sportId: filter.sportId,
      clearSportId: filter.sportId == null,
      query: filter.q,
      province: filter.province,
      clearProvince: filter.province == null,
      district: filter.district,
      clearDistrict: filter.district == null,
      locationEnabled: filter.locationEnabled,
      radiusKm: filter.radiusKm,
    );
    final nextBuddies = _state.buddies.copyWith(
      openOnly: filter.openOnly,
      joinedOnly: filter.joinedOnly,
      managedOnly: filter.managedOnly,
      allLevelsOnly: filter.allLevelsOnly,
      genderAnyOnly: filter.genderAnyOnly,
      noFeesOnly: filter.noFeesOnly,
    );
    if (nextShared == _state.shared && nextBuddies == _state.buddies) return;
    _commit(_state.copyWith(shared: nextShared, buddies: nextBuddies));
  }

  // Serializes writes so a slow earlier save can never overwrite a newer
  // state when several `_commit` calls land in the same frame.
  Future<void> _persistQueue = Future<void>.value();

  void _commit(SportsHubFilterState next) {
    _state = next;
    notifyListeners();
    // Fire-and-forget: filtering must never block on storage, but the
    // writes run in order so the last persisted state is always latest.
    final userId = _userId;
    _persistQueue = _persistQueue.then((_) => _store.save(userId, next));
  }
}
