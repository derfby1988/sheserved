/// Shared discovery filter for the Sports Hub.
///
/// Holds only the values that are meaningful across all three hub pages
/// (Find Buddies, Book Court, Find Coach): sport, keyword, province,
/// district, and location/radius. Domain-specific values such as booking
/// date, price range, or coach teaching mode live in the per-domain filter
/// objects and must never be merged into this object automatically.
class SportsDiscoveryFilter {
  const SportsDiscoveryFilter({
    this.sportId,
    this.query = '',
    this.province,
    this.district,
    this.locationEnabled = false,
    this.radiusKm = defaultRadiusKm,
  });

  static const double defaultRadiusKm = 10;

  final String? sportId;
  final String query;
  final String? province;
  final String? district;
  final bool locationEnabled;
  final double radiusKm;

  bool get isLocationReady => locationEnabled && radiusKm > 0;

  int get activeCount => [
    query.trim().isNotEmpty,
    province?.trim().isNotEmpty == true,
    district?.trim().isNotEmpty == true,
    locationEnabled,
  ].where((active) => active).length;

  SportsDiscoveryFilter copyWith({
    String? sportId,
    bool clearSportId = false,
    String? query,
    String? province,
    bool clearProvince = false,
    String? district,
    bool clearDistrict = false,
    bool? locationEnabled,
    double? radiusKm,
  }) {
    return SportsDiscoveryFilter(
      sportId: clearSportId ? null : (sportId ?? this.sportId),
      query: query ?? this.query,
      province: clearProvince ? null : (province ?? this.province),
      district: clearDistrict ? null : (district ?? this.district),
      locationEnabled: locationEnabled ?? this.locationEnabled,
      radiusKm: radiusKm ?? this.radiusKm,
    );
  }

  SportsDiscoveryFilter withSportId(String? nextSportId) {
    return copyWith(sportId: nextSportId, clearSportId: nextSportId == null);
  }

  Map<String, dynamic> toJson() {
    return {
      'sportId': sportId,
      'query': query,
      'province': province,
      'district': district,
      'locationEnabled': locationEnabled,
      'radiusKm': radiusKm,
    };
  }

  factory SportsDiscoveryFilter.fromJson(Map<String, dynamic> json) {
    return SportsDiscoveryFilter(
      sportId: json['sportId']?.toString(),
      query: json['query']?.toString() ?? '',
      province: json['province']?.toString(),
      district: json['district']?.toString(),
      locationEnabled: json['locationEnabled'] == true,
      radiusKm: (json['radiusKm'] as num?)?.toDouble() ?? defaultRadiusKm,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SportsDiscoveryFilter &&
            other.sportId == sportId &&
            other.query == query &&
            other.province == province &&
            other.district == district &&
            other.locationEnabled == locationEnabled &&
            other.radiusKm == radiusKm;
  }

  @override
  int get hashCode => Object.hash(
    sportId,
    query,
    province,
    district,
    locationEnabled,
    radiusKm,
  );
}
