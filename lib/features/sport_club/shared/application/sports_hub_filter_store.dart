import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sports_hub_filter_state.dart';

/// Persistence boundary for the Sports Hub filter state.
///
/// Pure storage only: no AuthService, Geolocator, BuildContext, or setState.
/// Uses the new `sports_hub_shared_filter_v1_<userId>` namespace; the legacy
/// `sport_club_filters_v1_<userId>` key (owned by [SportClubFilterStore])
/// stays untouched until migration/compatibility has fully passed.
class SportsHubFilterStore {
  const SportsHubFilterStore();

  static const _prefix = 'sports_hub_shared_filter_v1_';

  Future<SportsHubFilterState?> load(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$userId');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SportsHubFilterState.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String? userId, SportsHubFilterState state) async {
    if (userId == null || userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$userId', jsonEncode(state.toJson()));
    } catch (_) {
      // Filtering must keep working even when local storage is unavailable.
    }
  }
}
