import '../../book_court/domain/book_court_filter.dart';
import '../../find_coach/domain/find_coach_filter.dart';
import 'sports_discovery_filter.dart';

/// Aggregate filter state shared by the three Sports Hub pages.
///
/// [shared] holds values meaningful for every page (sport, keyword,
/// province, district, location/radius). Each domain filter is isolated:
/// mutating one page's filter never touches another domain's, and domain
/// values must not leak into queries of a different page.
class SportsHubFilterState {
  const SportsHubFilterState({
    this.shared = const SportsDiscoveryFilter(),
    this.buddies = const SportBuddiesFilter(),
    this.courts = const BookCourtFilter(),
    this.coaches = const FindCoachFilter(),
  });

  final SportsDiscoveryFilter shared;
  final SportBuddiesFilter buddies;
  final BookCourtFilter courts;
  final FindCoachFilter coaches;

  SportsHubFilterState copyWith({
    SportsDiscoveryFilter? shared,
    SportBuddiesFilter? buddies,
    BookCourtFilter? courts,
    FindCoachFilter? coaches,
  }) {
    return SportsHubFilterState(
      shared: shared ?? this.shared,
      buddies: buddies ?? this.buddies,
      courts: courts ?? this.courts,
      coaches: coaches ?? this.coaches,
    );
  }

  /// Turns off personal (login-required) filters in every domain while
  /// keeping the shared filter intact. Used on logout.
  SportsHubFilterState deactivatePersonalFilters() {
    return copyWith(
      buddies: buddies.deactivatePersonalFilters(),
      courts: courts.deactivatePersonalFilters(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shared': shared.toJson(),
      'buddies': buddies.toJson(),
      'courts': courts.toJson(),
      'coaches': coaches.toJson(),
    };
  }

  factory SportsHubFilterState.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> mapOf(Object? value) =>
        value is Map ? Map<String, dynamic>.from(value) : const {};
    return SportsHubFilterState(
      shared: SportsDiscoveryFilter.fromJson(mapOf(json['shared'])),
      buddies: SportBuddiesFilter.fromJson(mapOf(json['buddies'])),
      courts: BookCourtFilter.fromJson(mapOf(json['courts'])),
      coaches: FindCoachFilter.fromJson(mapOf(json['coaches'])),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SportsHubFilterState &&
            other.shared == shared &&
            other.buddies == buddies &&
            other.courts == courts &&
            other.coaches == coaches;
  }

  @override
  int get hashCode => Object.hash(shared, buddies, courts, coaches);
}

/// Domain-specific filter for Find Buddies (the legacy Sport Club feed).
///
/// Mirrors the personal/qualification toggles of `SportClubFilter`; the
/// shared values (sport, keyword, province, district, location/radius) live
/// in [SportsDiscoveryFilter] and are adapted into `SportClubFilter` at the
/// boundary.
class SportBuddiesFilter {
  const SportBuddiesFilter({
    this.openOnly = false,
    this.joinedOnly = false,
    this.managedOnly = false,
    this.allLevelsOnly = false,
    this.genderAnyOnly = false,
    this.noFeesOnly = false,
  });

  final bool openOnly;
  final bool joinedOnly;
  final bool managedOnly;
  final bool allLevelsOnly;
  final bool genderAnyOnly;
  final bool noFeesOnly;

  bool get hasPersonalFilter => joinedOnly || managedOnly;

  SportBuddiesFilter copyWith({
    bool? openOnly,
    bool? joinedOnly,
    bool? managedOnly,
    bool? allLevelsOnly,
    bool? genderAnyOnly,
    bool? noFeesOnly,
  }) {
    return SportBuddiesFilter(
      openOnly: openOnly ?? this.openOnly,
      joinedOnly: joinedOnly ?? this.joinedOnly,
      managedOnly: managedOnly ?? this.managedOnly,
      allLevelsOnly: allLevelsOnly ?? this.allLevelsOnly,
      genderAnyOnly: genderAnyOnly ?? this.genderAnyOnly,
      noFeesOnly: noFeesOnly ?? this.noFeesOnly,
    );
  }

  SportBuddiesFilter deactivatePersonalFilters() {
    if (!hasPersonalFilter) return this;
    return copyWith(joinedOnly: false, managedOnly: false);
  }

  Map<String, dynamic> toJson() {
    return {
      'openOnly': openOnly,
      'joinedOnly': joinedOnly,
      'managedOnly': managedOnly,
      'allLevelsOnly': allLevelsOnly,
      'genderAnyOnly': genderAnyOnly,
      'noFeesOnly': noFeesOnly,
    };
  }

  factory SportBuddiesFilter.fromJson(Map<String, dynamic> json) {
    return SportBuddiesFilter(
      openOnly: json['openOnly'] == true,
      joinedOnly: json['joinedOnly'] == true,
      managedOnly: json['managedOnly'] == true,
      allLevelsOnly: json['allLevelsOnly'] == true,
      genderAnyOnly: json['genderAnyOnly'] == true,
      noFeesOnly: json['noFeesOnly'] == true,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SportBuddiesFilter &&
            other.openOnly == openOnly &&
            other.joinedOnly == joinedOnly &&
            other.managedOnly == managedOnly &&
            other.allLevelsOnly == allLevelsOnly &&
            other.genderAnyOnly == genderAnyOnly &&
            other.noFeesOnly == noFeesOnly;
  }

  @override
  int get hashCode => Object.hash(
    openOnly,
    joinedOnly,
    managedOnly,
    allLevelsOnly,
    genderAnyOnly,
    noFeesOnly,
  );
}
