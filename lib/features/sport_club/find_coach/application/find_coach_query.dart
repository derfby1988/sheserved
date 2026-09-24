import '../../presentation/widgets/sport_club_utils.dart';
import '../../shared/domain/sports_discovery_filter.dart';
import '../data/coach_models.dart';
import '../domain/find_coach_filter.dart';

/// One page of visible coaches plus pagination state.
class CoachDirectoryPage {
  final List<CoachSummary> coaches;
  final int nextOffset;
  final bool hasMore;

  const CoachDirectoryPage({
    required this.coaches,
    required this.nextOffset,
    required this.hasMore,
  });
}

typedef FindCoachListCoaches =
    Future<List<CoachSummary>> Function({
      String? query,
      int limit,
      int offset,
    });

typedef FindCoachHydrate =
    Future<List<CoachSummary>> Function(List<CoachSummary> coaches);

/// Feed query/pagination logic for the coach directory.
///
/// Same contract as [BookCourtQuery]: repository surfaces arrive as
/// injected callbacks and [isStale] is polled between async steps so
/// superseded responses never overwrite newer state.
class FindCoachQuery {
  final FindCoachListCoaches listCoaches;
  final FindCoachHydrate hydrateCoaches;
  final int pageSize;

  const FindCoachQuery({
    required this.listCoaches,
    required this.hydrateCoaches,
    this.pageSize = 20,
  });

  Future<CoachDirectoryPage> fetch({
    required SportsDiscoveryFilter shared,
    required FindCoachFilter filter,
    required int offset,
    double? userLat,
    double? userLng,
    bool Function()? isStale,
  }) async {
    var nextOffset = offset;
    var hasMore = true;
    final visible = <CoachSummary>[];

    while (visible.length < pageSize && hasMore) {
      final page = await listCoaches(
        query: shared.query,
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

      final hydrated = await hydrateCoaches(page);
      if (isStale?.call() == true) {
        throw StateError('STALE_FILTER_REQUEST');
      }

      visible.addAll(
        hydrated.where(
          (c) => _matches(
            c,
            shared: shared,
            filter: filter,
            userLat: userLat,
            userLng: userLng,
          ),
        ),
      );
    }

    if (shared.isLocationReady && userLat != null && userLng != null) {
      visible.sort((a, b) {
        final da = _nearestDistanceKm(a, userLat, userLng);
        final db = _nearestDistanceKm(b, userLat, userLng);
        return da.compareTo(db);
      });
    }

    return CoachDirectoryPage(
      coaches: visible,
      nextOffset: nextOffset,
      hasMore: hasMore,
    );
  }

  bool _matches(
    CoachSummary c, {
    required SportsDiscoveryFilter shared,
    required FindCoachFilter filter,
    double? userLat,
    double? userLng,
  }) {
    // Shared sport filter.
    if (shared.sportId != null && !c.sportIds.contains(shared.sportId)) {
      return false;
    }
    // Shared province/district match against service areas.
    if (shared.province?.isNotEmpty == true) {
      final inProvince = c.serviceAreas.any(
        (a) => a.province == shared.province,
      );
      if (!inProvince) return false;
      if (shared.district?.isNotEmpty == true) {
        final inDistrict = c.serviceAreas.any(
          (a) =>
              a.province == shared.province &&
              a.district == shared.district,
        );
        if (!inDistrict) return false;
      }
    }
    // Shared radius: coach must have a service area covering the user, or
    // an area centre within radius of the user.
    if (shared.isLocationReady && userLat != null && userLng != null) {
      final covered = c.serviceAreas.any((a) {
        if (a.lat == null || a.lng == null) return false;
        final d = distanceKm(userLat, userLng, a.lat!, a.lng!);
        // Within the user's radius, or the user falls inside the coach's
        // own service radius.
        return d <= shared.radiusKm || d <= (a.radiusKm ?? 0);
      });
      if (!covered) return false;
    }
    // Coach-domain filters.
    if (filter.verifiedOnly && !c.isVerified) return false;
    if (filter.teachingMode != null) {
      final mode = filter.teachingMode!;
      if (c.teachingMode != TeachingMode.both &&
          c.teachingMode != teachingModeFrom(mode)) {
        return false;
      }
    }
    // A coach without a listed rate can't be compared against the cap;
    // they stay visible ("ราคาตามตกลง") rather than being silently dropped.
    if (filter.maxHourlyRate != null &&
        c.hourlyRate != null &&
        c.hourlyRate! > filter.maxHourlyRate!) {
      return false;
    }
    if (filter.skillLevel != null &&
        !c.skillLevels.contains(filter.skillLevel)) {
      return false;
    }
    if (filter.specialties.isNotEmpty) {
      final coachSpecs = c.specialties.map((s) => s.toLowerCase()).toSet();
      final ok = filter.specialties.any(
        (s) => coachSpecs.contains(s.toLowerCase()),
      );
      if (!ok) return false;
    }
    return true;
  }

  static double _nearestDistanceKm(
    CoachSummary c,
    double userLat,
    double userLng,
  ) {
    var best = double.infinity;
    for (final a in c.serviceAreas) {
      if (a.lat == null || a.lng == null) continue;
      final d = distanceKm(userLat, userLng, a.lat!, a.lng!);
      if (d < best) best = d;
    }
    return best;
  }
}
