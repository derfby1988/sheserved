/// Immutable value object for the sport-club feed filter.
///
/// This object stores persisted and search-affecting filter values only.
/// Runtime data such as the user's current coordinates and UI lifecycle state
/// remain in the page/controller layer.
class SportClubFilter {
  const SportClubFilter({
    this.sportId,
    this.q = '',
    this.province,
    this.district,
    this.openOnly = false,
    this.joinedOnly = false,
    this.managedOnly = false,
    this.allLevelsOnly = false,
    this.genderAnyOnly = false,
    this.noFeesOnly = false,
    this.locationEnabled = false,
    this.radiusKm = 10,
  });

  static const double defaultRadiusKm = 10;

  final String? sportId;
  final String q;
  final String? province;
  final String? district;
  final bool openOnly;
  final bool joinedOnly;
  final bool managedOnly;
  final bool allLevelsOnly;
  final bool genderAnyOnly;
  final bool noFeesOnly;
  final bool locationEnabled;
  final double radiusKm;

  int get activeCount => [
    q.trim().isNotEmpty,
    province?.trim().isNotEmpty == true,
    district?.trim().isNotEmpty == true,
    openOnly,
    joinedOnly,
    managedOnly,
    allLevelsOnly,
    genderAnyOnly,
    noFeesOnly,
    locationEnabled,
  ].where((active) => active).length;

  String get summary => activeCount == 0 ? 'ตัวกรอง' : 'ตัวกรอง ($activeCount)';

  bool get isLocationReady => locationEnabled && radiusKm > 0;

  bool get isPersonalFilterActive => joinedOnly || managedOnly;

  SportClubFilter copyWith({
    String? sportId,
    bool clearSportId = false,
    String? q,
    String? province,
    bool clearProvince = false,
    String? district,
    bool clearDistrict = false,
    bool? openOnly,
    bool? joinedOnly,
    bool? managedOnly,
    bool? allLevelsOnly,
    bool? genderAnyOnly,
    bool? noFeesOnly,
    bool? locationEnabled,
    double? radiusKm,
  }) {
    return SportClubFilter(
      sportId: clearSportId ? null : (sportId ?? this.sportId),
      q: q ?? this.q,
      province: clearProvince ? null : (province ?? this.province),
      district: clearDistrict ? null : (district ?? this.district),
      openOnly: openOnly ?? this.openOnly,
      joinedOnly: joinedOnly ?? this.joinedOnly,
      managedOnly: managedOnly ?? this.managedOnly,
      allLevelsOnly: allLevelsOnly ?? this.allLevelsOnly,
      genderAnyOnly: genderAnyOnly ?? this.genderAnyOnly,
      noFeesOnly: noFeesOnly ?? this.noFeesOnly,
      locationEnabled: locationEnabled ?? this.locationEnabled,
      radiusKm: radiusKm ?? this.radiusKm,
    );
  }

  /// Clears the user-facing filters counted by [activeCount].
  ///
  /// Matches the page's original clear behavior: the selected sport chip and
  /// the radius value are preserved.
  SportClubFilter clearAll() {
    return copyWith(
      q: '',
      clearProvince: true,
      clearDistrict: true,
      openOnly: false,
      joinedOnly: false,
      managedOnly: false,
      allLevelsOnly: false,
      genderAnyOnly: false,
      noFeesOnly: false,
      locationEnabled: false,
    );
  }

  SportClubFilter toggleQuickFilter(String filter) {
    switch (filter) {
      case 'open':
        return copyWith(openOnly: !openOnly);
      case 'joined':
        return copyWith(joinedOnly: !joinedOnly);
      case 'managed':
        return copyWith(managedOnly: !managedOnly);
      default:
        return this;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'sportId': sportId,
      'q': q,
      'province': province,
      'district': district,
      'openOnly': openOnly,
      'joinedOnly': joinedOnly,
      'managedOnly': managedOnly,
      'allLevelsOnly': allLevelsOnly,
      'genderAnyOnly': genderAnyOnly,
      'noFeesOnly': noFeesOnly,
      'locationEnabled': locationEnabled,
      'radiusKm': radiusKm,
    };
  }

  factory SportClubFilter.fromJson(Map<String, dynamic> json) {
    return SportClubFilter(
      sportId: json['sportId']?.toString(),
      q: json['q']?.toString() ?? '',
      province: json['province']?.toString(),
      district: json['district']?.toString(),
      openOnly: json['openOnly'] == true,
      joinedOnly: json['joinedOnly'] == true,
      managedOnly: json['managedOnly'] == true,
      allLevelsOnly: json['allLevelsOnly'] == true,
      genderAnyOnly: json['genderAnyOnly'] == true,
      noFeesOnly: json['noFeesOnly'] == true,
      locationEnabled: json['locationEnabled'] == true,
      radiusKm: (json['radiusKm'] as num?)?.toDouble() ?? defaultRadiusKm,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SportClubFilter &&
            other.sportId == sportId &&
            other.q == q &&
            other.province == province &&
            other.district == district &&
            other.openOnly == openOnly &&
            other.joinedOnly == joinedOnly &&
            other.managedOnly == managedOnly &&
            other.allLevelsOnly == allLevelsOnly &&
            other.genderAnyOnly == genderAnyOnly &&
            other.noFeesOnly == noFeesOnly &&
            other.locationEnabled == locationEnabled &&
            other.radiusKm == radiusKm;
  }

  @override
  int get hashCode => Object.hash(
    sportId,
    q,
    province,
    district,
    openOnly,
    joinedOnly,
    managedOnly,
    allLevelsOnly,
    genderAnyOnly,
    noFeesOnly,
    locationEnabled,
    radiusKm,
  );
}
