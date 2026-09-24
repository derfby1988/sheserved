/// Domain-specific filter for the Find Coach page.
///
/// Coach availability and teaching mode stay here; they are never merged
/// into the shared discovery filter.
class FindCoachFilter {
  const FindCoachFilter({
    this.skillLevel,
    this.specialties = const [],
    this.maxHourlyRate,
    this.verifiedOnly = false,
    this.availableOnly = false,
    this.teachingMode,
  });

  final String? skillLevel;
  final List<String> specialties;
  final double? maxHourlyRate;
  final bool verifiedOnly;
  final bool availableOnly;

  /// `onsite` / `online` / `both`.
  final String? teachingMode;

  int get activeCount => [
    skillLevel != null,
    specialties.isNotEmpty,
    maxHourlyRate != null,
    verifiedOnly,
    availableOnly,
    teachingMode != null,
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
            other.teachingMode == teachingMode;
  }

  @override
  int get hashCode => Object.hash(
    skillLevel,
    Object.hashAll(specialties),
    maxHourlyRate,
    verifiedOnly,
    availableOnly,
    teachingMode,
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
