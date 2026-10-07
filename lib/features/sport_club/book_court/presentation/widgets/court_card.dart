import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../application/court_card_style_service.dart';
import '../../data/book_court_models.dart';
import '../../domain/court_card_style.dart';
import 'court_card_art.dart';

/// Venue card for the Book Court discovery feed.
///
/// The chrome follows [CourtCardStyleService.instance] — the admin picks the
/// style on the "รูปแบบการ์ด" tab and every card re-renders immediately.
class CourtCard extends StatefulWidget {
  final VenueSummary venue;
  final double? distanceKm;
  final VoidCallback? onTap;
  final List<VenueBooking> upcomingBookings;

  /// Renders this style instead of the admin-selected one — used by the
  /// "รูปแบบการ์ด" previews, which show every style at once.
  final CourtCardStyle? styleOverride;

  const CourtCard({
    super.key,
    required this.venue,
    this.distanceKm,
    this.onTap,
    this.upcomingBookings = const [],
    this.styleOverride,
  });

  @override
  State<CourtCard> createState() => _CourtCardState();
}

class _CourtCardState extends State<CourtCard> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _scheduleCountdownUpdate();
  }

  @override
  void didUpdateWidget(covariant CourtCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = DateTime.now();
    final oldBooking = _nearestUpcomingBooking(
      oldWidget.upcomingBookings,
      oldWidget.venue.id,
      now,
    );
    final newBooking = _nearestUpcomingBooking(
      widget.upcomingBookings,
      widget.venue.id,
      now,
    );
    if (oldBooking?.id != newBooking?.id ||
        oldBooking?.startsAt != newBooking?.startsAt ||
        oldWidget.venue.id != widget.venue.id) {
      _scheduleCountdownUpdate();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  static VenueBooking? _nearestUpcomingBooking(
    List<VenueBooking> bookings,
    String venueId,
    DateTime now,
  ) {
    VenueBooking? next;
    for (final booking in bookings) {
      if (booking.venueId != venueId ||
          !booking.isConfirmed ||
          !booking.startsAt.isAfter(now) ||
          !booking.endsAt.isAfter(now)) {
        continue;
      }
      if (next == null || booking.startsAt.isBefore(next.startsAt)) {
        next = booking;
      }
    }
    return next;
  }

  void _scheduleCountdownUpdate() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final booking = _nearestUpcomingBooking(
      widget.upcomingBookings,
      widget.venue.id,
      DateTime.now(),
    );
    if (booking == null) return;
    final remaining = booking.startsAt.difference(DateTime.now());
    final delay = remaining < const Duration(minutes: 1)
        ? remaining
        : const Duration(minutes: 1);
    _countdownTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
      _scheduleCountdownUpdate();
    });
  }

  static String _countdownLabel(DateTime startsAt, DateTime now) {
    final seconds = startsAt.difference(now).inSeconds;
    final totalMinutes = seconds < 60 ? 1 : (seconds + 59) ~/ 60;
    if (totalMinutes < 60) return '$totalMinutes นาที';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '$hours ชม.' : '$hours ชม. $minutes นาที';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcomingBooking = _nearestUpcomingBooking(
      widget.upcomingBookings,
      widget.venue.id,
      now,
    );
    final appointmentLabel = upcomingBooking == null
        ? null
        : 'คุณมีนัดหมาย ${_courtLabel(upcomingBooking)} '
              'กำลังจะเริ่มใน '
              '${_countdownLabel(upcomingBooking.startsAt, now)}';

    final override = widget.styleOverride;
    if (override != null) return _buildStyle(override, appointmentLabel);
    return ValueListenableBuilder<CourtCardStyle>(
      valueListenable: CourtCardStyleService.instance.style,
      builder: (context, style, _) => _buildStyle(style, appointmentLabel),
    );
  }

  Widget _buildStyle(CourtCardStyle style, String? appointmentLabel) =>
      style.isThreeDimensional
      ? _buildThreeDimensional(style, appointmentLabel)
      : _buildClassic(appointmentLabel);

  // =============== Classic (flat) chrome ================================

  Widget _buildClassic(String? appointmentLabel) {
    final venue = widget.venue;
    final distanceKm = widget.distanceKm;
    final startingPrice = venue.startingPriceAmount;
    final startingPriceText = startingPrice == null
        ? null
        : _formatAmount(startingPrice);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (venue.photoUrls.isNotEmpty)
              SizedBox(
                height: 140,
                width: double.infinity,
                child: Image.network(
                  venue.photoUrls.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 140,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          venue.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (venue.averageRating != null) ...[
                        const Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: AppColors.alertGold,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          venue.averageRating!.toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          ' (${venue.reviewCount})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            venue.district,
                            venue.province,
                          ].whereType<String>().join(', '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (distanceKm != null)
                        Text(
                          '${distanceKm.toStringAsFixed(1)} กม.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.sports_tennis_rounded,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${venue.courtCount} รายการ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const Spacer(),
                      if (venue.amenityIds.isNotEmpty)
                        Row(
                          children: [
                            for (final key in venue.amenityIds.take(4))
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  _amenityIcon(key),
                                  size: 15,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                  if (startingPriceText != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'ราคาเริ่มต้นที่ $startingPriceText บ.',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                  if (appointmentLabel != null) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          appointmentLabel,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFC2185B),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============== 3D glass chrome ======================================

  Widget _buildThreeDimensional(
    CourtCardStyle style,
    String? appointmentLabel,
  ) {
    final venue = widget.venue;
    final score = _score(venue);
    final startingPriceText = venue.startingPriceAmount == null
        ? null
        : _formatAmount(venue.startingPriceAmount!);
    final location = [
      venue.district,
      venue.province,
    ].whereType<String>().join(', ');
    final distanceKm = widget.distanceKm;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateX(0.10)
        ..rotateY(-0.13),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.96),
              Colors.white.withValues(alpha: 0.72),
              const Color(0xFFF3D9DC).withValues(alpha: 0.80),
            ],
            stops: const [0, 0.55, 1],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.9),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.55),
              blurRadius: 8,
              offset: const Offset(-4, -4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          venue.name,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E2330),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.place_outlined,
                              size: 13,
                              color: Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                distanceKm == null
                                    ? location
                                    : '$location · '
                                          '${distanceKm.toStringAsFixed(1)} กม.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (venue.averageRating != null) ...[
                              const Icon(
                                Icons.star_rounded,
                                size: 15,
                                color: AppColors.alertGold,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                venue.averageRating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E2330),
                                ),
                              ),
                              Text(
                                ' (${venue.reviewCount})',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Icon(
                              Icons.sports_tennis_rounded,
                              size: 13,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${venue.courtCount} รายการ',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                        if (venue.amenityIds.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              for (final key in venue.amenityIds.take(4))
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(
                                    _amenityIcon(key),
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (startingPriceText != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'ราคาเริ่มต้นที่ $startingPriceText บ.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                        if (appointmentLabel != null) ...[
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                appointmentLabel,
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFC2185B),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _scoreBlock(style, score),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scoreBlock(
    CourtCardStyle style,
    ({String value, String? suffix, String label, int level}) score,
  ) {
    return SizedBox(
      width: 108,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    score.value,
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E2330),
                    ),
                  ),
                  if (score.suffix != null)
                    Text(
                      score.suffix!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Text(
            score.label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB01B25),
            ),
          ),
          const SizedBox(height: 4),
          CourtCardCubeArt(style: style, level: score.level, size: 86),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var step = 1; step <= 5; step++)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: step <= score.level
                        ? const Color(0xFFD91E28)
                        : const Color(0xFFD6D9E0),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Big number shown on the 3D card: the venue rating when it has reviews,
  /// otherwise its court count (both mapped onto a 1–5 band).
  static ({String value, String? suffix, String label, int level}) _score(
    VenueSummary venue,
  ) {
    final rating = venue.averageRating;
    if (rating != null) {
      return (
        value: rating.toStringAsFixed(1),
        suffix: '/5',
        label: 'คะแนนสนาม',
        level: rating.round().clamp(1, 5),
      );
    }
    return (
      value: '${venue.courtCount}',
      suffix: null,
      label: 'รายการ',
      level: _supplyLevel(venue.courtCount),
    );
  }

  static int _supplyLevel(int courts) {
    if (courts <= 2) return 1;
    if (courts <= 5) return 2;
    if (courts <= 9) return 3;
    if (courts <= 14) return 4;
    return 5;
  }

  static String _courtLabel(VenueBooking booking) {
    final unitLabel = booking.unitLabel?.trim();
    final courtName = booking.courtName?.trim();
    return [
      unitLabel == null || unitLabel.isEmpty ? 'คอร์ท' : unitLabel,
      if (courtName != null && courtName.isNotEmpty) courtName,
    ].join(' ');
  }

  static String _formatAmount(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);

  static IconData _amenityIcon(String key) => switch (key) {
    'parking' => Icons.local_parking_rounded,
    'restroom' => Icons.wc_rounded,
    'shower' => Icons.shower_rounded,
    'ev_charging' => Icons.ev_station_rounded,
    'equipment_rental' => Icons.sports_baseball_rounded,
    'lighting' => Icons.lightbulb_outline_rounded,
    'locker' => Icons.lock_rounded,
    'wifi' => Icons.wifi_rounded,
    'cafe' => Icons.local_cafe_rounded,
    'first_aid' => Icons.medical_services_rounded,
    _ => Icons.check_circle_outline_rounded,
  };
}
