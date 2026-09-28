/// Domain-specific filter for the Find Coach page.
///
/// Coach availability, teaching mode, rating and relationship filters stay
/// here; they are never merged into the shared discovery filter.
class FindCoachFilter {
  const FindCoachFilter({
    this.skillLevel,
    this.specialties = const [],
    this.maxHourlyRate,
    this.verifiedOnly = false,
    this.availableOnly = false,
    this.teachingMode,
    this.minRating10,
    this.favoritesOnly = false,
    this.myCoachesOnly = false,
    this.offeringType,
  });

  final String? skillLevel;
  final List<String> specialties;
  final double? maxHourlyRate;
  final bool verifiedOnly;
  final bool availableOnly;

  /// `onsite` / `online` / `both`.
  final String? teachingMode;

  /// Minimum coach rating on the 1–10 aggregate scale.
  final double? minRating10;

  /// Private favorites of the signed-in user.
  final bool favoritesOnly;

  /// Coaches the user has a confirmed/completed booking or enrollment with.
  final bool myCoachesOnly;

  /// `one_on_one` / `group_class` / `course` — coaches that publish at
  /// least one active offering of this kind.
  final String? offeringType;

  int get activeCount => [
    skillLevel != null,
    specialties.isNotEmpty,
    maxHourlyRate != null,
    verifiedOnly,
    availableOnly,
    teachingMode != null,
    minRating10 != null,
    favoritesOnly,
    myCoachesOnly,
    offeringType != null,
  ].where((active) => active).length;

  FindCoachFilter copyWith({
    String? skillLevel,
    bool clearSkillLevel = false,
    List<String>? specialties,
    double? maxHourlyRate,
    bool clearMaxHourlyRate = false,
    bool? verifiedOnly,
    bool? availableOnly,
    String? teachingMode,
    bool clearTeachingMode = false,
    double? minRating10,
    bool clearMinRating10 = false,
    bool? favoritesOnly,
    bool? myCoachesOnly,
    String? offeringType,
    bool clearOfferingType = false,
  }) {
    return FindCoachFilter(
      skillLevel: clearSkillLevel ? null : (skillLevel ?? this.skillLevel),
      specialties: specialties ?? this.specialties,
      maxHourlyRate: clearMaxHourlyRate
          ? null
          : (maxHourlyRate ?? this.maxHourlyRate),
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      availableOnly: availableOnly ?? this.availableOnly,
      teachingMode: clearTeachingMode
          ? null
          : (teachingMode ?? this.teachingMode),
      minRating10: clearMinRating10
          ? null
          : (minRating10 ?? this.minRating10),
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      myCoachesOnly: myCoachesOnly ?? this.myCoachesOnly,
      offeringType: clearOfferingType
          ? null
          : (offeringType ?? this.offeringType),
    );
  }

  FindCoachFilter clearAll() => const FindCoachFilter();

  Map<String, dynamic> toJson() {
    return {
      'skillLevel': skillLevel,
      'specialties': specialties,
      'maxHourlyRate': maxHourlyRate,
      'verifiedOnly': verifiedOnly,
      'availableOnly': availableOnly,
      'teachingMode': teachingMode,
      'minRating10': minRating10,
      'favoritesOnly': favoritesOnly,
      'myCoachesOnly': myCoachesOnly,
      'offeringType': offeringType,
    };
  }

  factory FindCoachFilter.fromJson(Map<String, dynamic> json) {
    return FindCoachFilter(
      skillLevel: json['skillLevel']?.toString(),
      specialties:
          (json['specialties'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      maxHourlyRate: (json['maxHourlyRate'] as num?)?.toDouble(),
      verifiedOnly: json['verifiedOnly'] == true,
      availableOnly: json['availableOnly'] == true,
      teachingMode: json['teachingMode']?.toString(),
      minRating10: (json['minRating10'] as num?)?.toDouble(),
      favoritesOnly: json['favoritesOnly'] == true,
      myCoachesOnly: json['myCoachesOnly'] == true,
      offeringType: json['offeringType']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FindCoachFilter &&
            other.skillLevel == skillLevel &&
            _listEquals(other.specialties, specialties) &&
            other.maxHourlyRate == maxHourlyRate &&
            other.verifiedOnly == verifiedOnly &&
            other.availableOnly == availableOnly &&
            other.teachingMode == teachingMode &&
            other.minRating10 == minRating10 &&
            other.favoritesOnly == favoritesOnly &&
            other.myCoachesOnly == myCoachesOnly &&
            other.offeringType == offeringType;
  }

  @override
  int get hashCode => Object.hash(
    skillLevel,
    Object.hashAll(specialties),
    maxHourlyRate,
    verifiedOnly,
    availableOnly,
    teachingMode,
    minRating10,
    favoritesOnly,
    myCoachesOnly,
    offeringType,
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
