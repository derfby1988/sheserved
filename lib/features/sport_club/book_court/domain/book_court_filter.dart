import 'package:flutter/material.dart';

/// Domain-specific filter for the Book Court page.
///
/// Booking date/time live here (in the venue's local-time context), never in
/// [SportsDiscoveryFilter]. The shared location radius is owned by the shared
/// filter; the `radius` quick filter only toggles shared `locationEnabled`.
class BookCourtFilter {
  const BookCourtFilter({
    this.date,
    this.startTime,
    this.duration,
    this.minPrice,
    this.maxPrice,
    this.minRating,
    this.availableOnly = false,
    this.bookedByMeOnly = false,
    this.ownerOnly = false,
    this.amenityIds = const {},
    this.courtType,
    this.indoorOnly = false,
    this.openNowOnly = false,
  });

  /// Booking date in the venue's local timezone.
  final DateTime? date;
  final TimeOfDay? startTime;
  final Duration? duration;
  final double? minPrice;
  final double? maxPrice;
  final double? minRating;
  final bool availableOnly;
  final bool bookedByMeOnly;
  final bool ownerOnly;
  final Set<String> amenityIds;
  final String? courtType;
  final bool indoorOnly;
  final bool openNowOnly;

  /// Personal filters that require a logged-in user.
  bool get hasPersonalFilter => bookedByMeOnly || ownerOnly;

  int get activeCount => [
    date != null,
    startTime != null,
    duration != null,
    minPrice != null,
    maxPrice != null,
    minRating != null,
    availableOnly,
    bookedByMeOnly,
    ownerOnly,
    amenityIds.isNotEmpty,
    courtType != null,
    indoorOnly,
    openNowOnly,
  ].where((active) => active).length;

  BookCourtFilter copyWith({
    DateTime? date,
    bool clearDate = false,
    TimeOfDay? startTime,
    bool clearStartTime = false,
    Duration? duration,
    bool clearDuration = false,
    double? minPrice,
    bool clearMinPrice = false,
    double? maxPrice,
    bool clearMaxPrice = false,
    double? minRating,
    bool clearMinRating = false,
    bool? availableOnly,
    bool? bookedByMeOnly,
    bool? ownerOnly,
    Set<String>? amenityIds,
    String? courtType,
    bool clearCourtType = false,
    bool? indoorOnly,
    bool? openNowOnly,
  }) {
    return BookCourtFilter(
      date: clearDate ? null : (date ?? this.date),
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
      duration: clearDuration ? null : (duration ?? this.duration),
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      minRating: clearMinRating ? null : (minRating ?? this.minRating),
      availableOnly: availableOnly ?? this.availableOnly,
      bookedByMeOnly: bookedByMeOnly ?? this.bookedByMeOnly,
      ownerOnly: ownerOnly ?? this.ownerOnly,
      amenityIds: amenityIds ?? this.amenityIds,
      courtType: clearCourtType ? null : (courtType ?? this.courtType),
      indoorOnly: indoorOnly ?? this.indoorOnly,
      openNowOnly: openNowOnly ?? this.openNowOnly,
    );
  }

  /// Turns off filters that are only meaningful for a signed-in user.
  /// Shared/sport/location values are untouched.
  BookCourtFilter deactivatePersonalFilters() {
    if (!hasPersonalFilter) return this;
    return copyWith(bookedByMeOnly: false, ownerOnly: false);
  }

  BookCourtFilter clearAll() {
    return const BookCourtFilter();
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date?.toIso8601String(),
      'startTimeMinutes': startTime == null
          ? null
          : startTime!.hour * 60 + startTime!.minute,
      'durationMinutes': duration?.inMinutes,
      'minPrice': minPrice,
      'maxPrice': maxPrice,
      'minRating': minRating,
      'availableOnly': availableOnly,
      'bookedByMeOnly': bookedByMeOnly,
      'ownerOnly': ownerOnly,
      'amenityIds': amenityIds.toList(),
      'courtType': courtType,
      'indoorOnly': indoorOnly,
      'openNowOnly': openNowOnly,
    };
  }

  factory BookCourtFilter.fromJson(Map<String, dynamic> json) {
    final dateRaw = json['date']?.toString();
    final startMinutes = (json['startTimeMinutes'] as num?)?.toInt();
    final durationMinutes = (json['durationMinutes'] as num?)?.toInt();
    return BookCourtFilter(
      date: dateRaw == null ? null : DateTime.tryParse(dateRaw),
      startTime: startMinutes == null
          ? null
          : TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60),
      duration: durationMinutes == null
          ? null
          : Duration(minutes: durationMinutes),
      minPrice: (json['minPrice'] as num?)?.toDouble(),
      maxPrice: (json['maxPrice'] as num?)?.toDouble(),
      minRating: (json['minRating'] as num?)?.toDouble(),
      availableOnly: json['availableOnly'] == true,
      bookedByMeOnly: json['bookedByMeOnly'] == true,
      ownerOnly: json['ownerOnly'] == true,
      amenityIds:
          (json['amenityIds'] as List?)
              ?.map((e) => e.toString())
              .toSet() ??
          const {},
      courtType: json['courtType']?.toString(),
      indoorOnly: json['indoorOnly'] == true,
      openNowOnly: json['openNowOnly'] == true,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BookCourtFilter &&
            other.date == date &&
            other.startTime == startTime &&
            other.duration == duration &&
            other.minPrice == minPrice &&
            other.maxPrice == maxPrice &&
            other.minRating == minRating &&
            other.availableOnly == availableOnly &&
            other.bookedByMeOnly == bookedByMeOnly &&
            other.ownerOnly == ownerOnly &&
            _setEquals(other.amenityIds, amenityIds) &&
            other.courtType == courtType &&
            other.indoorOnly == indoorOnly &&
            other.openNowOnly == openNowOnly;
  }

  @override
  int get hashCode => Object.hash(
    date,
    startTime,
    duration,
    minPrice,
    maxPrice,
    minRating,
    availableOnly,
    bookedByMeOnly,
    ownerOnly,
    Object.hashAllUnordered(amenityIds),
    courtType,
    indoorOnly,
    openNowOnly,
  );

  static bool _setEquals(Set<String> a, Set<String> b) {
    return a.length == b.length && a.containsAll(b);
  }
}
