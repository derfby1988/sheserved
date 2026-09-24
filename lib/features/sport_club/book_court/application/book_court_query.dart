import '../../presentation/widgets/sport_club_utils.dart';
import '../../shared/domain/sports_discovery_filter.dart';
import '../data/book_court_models.dart';
import '../domain/book_court_filter.dart';

/// One page of visible venues plus pagination state.
class BookCourtVenuePage {
  final List<VenueSummary> venues;
  final int nextOffset;
  final bool hasMore;

  const BookCourtVenuePage({
    required this.venues,
    required this.nextOffset,
    required this.hasMore,
  });
}

typedef BookCourtListVenues =
    Future<List<VenueSummary>> Function({
      String? sportId,
      String? province,
      String? district,
      String? query,
      int limit,
      int offset,
    });

typedef BookCourtHydrate =
    Future<List<VenueSummary>> Function(List<VenueSummary> venues);

typedef BookCourtPersonalIds = Future<Set<String>> Function(String userId);

/// Feed query/pagination logic for the Book Court venue list.
///
/// Pure with respect to widget state: repository surfaces arrive as
/// injected callbacks so the query is unit-testable without Supabase.
/// [isStale] is polled between async steps; when it returns true the query
/// throws `StateError('STALE_FILTER_REQUEST')` so superseded responses
/// never overwrite newer state.
class BookCourtQuery {
  final BookCourtListVenues listVenues;
  final BookCourtHydrate hydrateVenues;
  final BookCourtPersonalIds bookedVenueIds;
  final BookCourtPersonalIds managedVenueIds;
  final int pageSize;

  const BookCourtQuery({
    required this.listVenues,
    required this.hydrateVenues,
    required this.bookedVenueIds,
    required this.managedVenueIds,
    this.pageSize = 20,
  });

  /// Fetches up to [pageSize] venues starting at [offset] applying the
  /// shared filter plus the Book Court domain filter.
  ///
  /// `bookedByMeOnly`/`ownerOnly` require [userId]; when it is null the
  /// caller is expected to have already gated those toggles behind login.
  Future<BookCourtVenuePage> fetch({
    required SportsDiscoveryFilter shared,
    required BookCourtFilter filter,
    required int offset,
    String? userId,
    double? userLat,
    double? userLng,
    bool Function()? isStale,
  }) async {
    var nextOffset = offset;
    var hasMore = true;
    final visible = <VenueSummary>[];

    // Personal filters resolve once per fetch so paginated batches agree.
    final bookedIds = (filter.bookedByMeOnly && userId != null)
        ? await bookedVenueIds(userId)
        : const <String>{};
    final managedIds = (filter.ownerOnly && userId != null)
        ? await managedVenueIds(userId)
        : const <String>{};
    if (isStale?.call() == true) {
      throw StateError('STALE_FILTER_REQUEST');
    }

    while (visible.length < pageSize && hasMore) {
      final page = await listVenues(
        sportId: shared.sportId,
        province: shared.province,
        district: shared.district,
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

      // Location radius uses the shared filter values.
      var batch = page;
      if (shared.isLocationReady && userLat != null && userLng != null) {
        batch = batch.where((v) {
          if (v.lat == null || v.lng == null) return false;
          return distanceKm(userLat, userLng, v.lat!, v.lng!) <=
              shared.radiusKm;
        }).toList();
      }

      batch = batch.where((v) {
        if (filter.bookedByMeOnly && !bookedIds.contains(v.id)) {
          return false;
        }
        if (filter.ownerOnly && !managedIds.contains(v.id)) return false;
        if (filter.amenityIds.isNotEmpty &&
            !v.amenityIds.containsAll(filter.amenityIds)) {
          return false;
        }
        if (filter.minRating != null &&
            (v.averageRating ?? 0) < filter.minRating!) {
          return false;
        }
        return true;
      }).toList();

      if (batch.isNotEmpty) {
        final hydrated = await hydrateVenues(batch);
        if (isStale?.call() == true) {
          throw StateError('STALE_FILTER_REQUEST');
        }
        visible.addAll(hydrated);
      }
    }

    if (shared.isLocationReady && userLat != null && userLng != null) {
      visible.sort((a, b) {
        final da = (a.lat != null && a.lng != null)
            ? distanceKm(userLat, userLng, a.lat!, a.lng!)
            : double.infinity;
        final db = (b.lat != null && b.lng != null)
            ? distanceKm(userLat, userLng, b.lat!, b.lng!)
            : double.infinity;
        return da.compareTo(db);
      });
    }

    return BookCourtVenuePage(
      venues: visible,
      nextOffset: nextOffset,
      hasMore: hasMore,
    );
  }
}
