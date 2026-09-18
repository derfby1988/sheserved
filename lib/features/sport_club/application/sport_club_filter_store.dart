import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sport_club_filter.dart';

/// Persistence boundary for the sport-club feed filter.
///
/// Pure storage only: no AuthService, Geolocator, BuildContext, or setState.
/// The caller supplies the user id; the stored schema is unchanged from the
/// legacy `sport_club_filters_v1_<userId>` format for backward compatibility.
class SportClubFilterStore {
  const SportClubFilterStore();

  static const _prefix = 'sport_club_filters_v1_';

  Future<SportClubFilter?> load(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$userId');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SportClubFilter.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String? userId, SportClubFilter filter) async {
    if (userId == null || userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$userId', jsonEncode(filter.toJson()));
    } catch (_) {
      // Filtering must keep working even when local storage is unavailable.
    }
  }
}
