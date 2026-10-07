import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../application/court_card_style_service.dart';
import '../../data/book_court_models.dart';
import '../../domain/court_card_3d_params.dart';
import '../../domain/court_card_style.dart';
import 'court_card_art.dart';
import 'court_card_slab.dart';

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

  /// Overrides the admin 3D params — used by the style panel preview.
  final CourtCard3DParams? params3dOverride;

  const CourtCard({
    super.key,
    required this.venue,
    this.distanceKm,
    this.onTap,
    this.upcomingBookings = const [],
    this.styleOverride,
    this.params3dOverride,
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
    if (override != null) {
      return _buildStyle(
        override,
        appointmentLabel,
        widget.params3dOverride ?? CourtCardStyleService.instance.params3d.value,
      );
    }
    final svc = CourtCardStyleService.instance;
    return ValueListenableBuilder<CourtCardStyle>(
      valueListenable: svc.style,
      builder: (context, style, _) => ValueListenableBuilder<CourtCard3DParams>(
        valueListenable: svc.params3d,
        builder: (context, p3d, _) => _buildStyle(
          style,
          appointmentLabel,
          widget.params3dOverride ?? p3d,
        ),
      ),
    );
  }

  Widget _buildStyle(
    CourtCardStyle style,
    String? appointmentLabel,
    CourtCard3DParams p3d,
  ) =>
      style.isThreeDimensional
      ? _buildThreeDimensional(style, appointmentLabel, p3d)
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
    CourtCard3DParams p3d,
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

    // Compute light angle sheen alignment from the admin parameter
    final sheenBeginX = -math.cos(p3d.lightAngle);
    final sheenBeginY = -math.sin(p3d.lightAngle);
    final sheenEndX = math.cos(p3d.lightAngle);
    final sheenEndY = math.sin(p3d.lightAngle);

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateX(p3d.rotateX)
        ..rotateY(p3d.rotateY),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: CourtCardSlab(
          level: score.level,
          thickness: p3d.thickness,
          opacity: p3d.opacity,
          sheenBegin: Alignment(sheenBeginX, sheenBeginY),
          sheenEnd: Alignment(sheenEndX, sheenEndY),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column: Venue details & bold score
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                venue.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF161A26),
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              // Big Score display
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    score.value,
                                    style: const TextStyle(
                                      fontSize: 32,
                                      height: 1.05,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF111827),
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                  if (score.suffix != null)
                                    Text(
                                      score.suffix!,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF4B5563),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Subtitle with red dot badge (matching prototype ● Individual)
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFFD91E28),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0x66D91E28),
                                          blurRadius: 5,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    score.label,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFD91E28),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Location and Rating Detail Row
                              Row(
                                children: [
                                  if (venue.averageRating != null) ...[
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: AppColors.alertGold,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      venue.averageRating!.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1E2330),
                                      ),
                                    ),
                                    Text(
                                      ' (${venue.reviewCount})',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  const Icon(
                                    Icons.place_outlined,
                                    size: 12,
                                    color: Color(0xFF374151),
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      distanceKm == null
                                          ? location
                                          : '$location · ${distanceKm.toStringAsFixed(1)} กม.',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF374151),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Court count and amenities
                              Row(
                                children: [
                                  const Icon(
                                    Icons.sports_tennis_rounded,
                                    size: 13,
                                    color: Color(0xFF374151),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${venue.courtCount} รายการ',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF374151),
                                    ),
                                  ),
                                  if (venue.amenityIds.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    for (final key in venue.amenityIds.take(3))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: Icon(
                                          _amenityIcon(key),
                                          size: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                              if (startingPriceText != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'ราคาเริ่มต้นที่ $startingPriceText บ.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Right column: Prominent 3D cube stack art OR custom replacement image
                        if (p3d.show3dIcon) ...[
                          const SizedBox(width: 6),
                          CourtCardCubeArt(
                            style: style,
                            level: score.level,
                            size: 96,
                          ),
                        ] else if (p3d.customImageUrl != null &&
                            p3d.customImageUrl!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _buildCustomCardArt(p3d.customImageUrl!, 96),
                        ],
                      ],
                    ),
                    if (appointmentLabel != null) ...[
                      const SizedBox(height: 8),
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
                    // Horizontal Stepper Track from prototype
                    _buildStepperTrack(score.level, score.suffix == '/5'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Horizontal stepper track with 5 levels, matching the prototype design:
  /// numbers 1-5, continuous track line with glowing active node, and descriptive labels.
  Widget _buildStepperTrack(int activeLevel, bool isRating) {
    final labels = isRating
        ? const ['1 ดาว', '2 ดาว', '3 ดาว', '4 ดาว', '5 ดาว']
        : const [
            '1–2 คอร์ท',
            '3–5 คอร์ท',
            '6–9 คอร์ท',
            '10–14 คอร์ท',
            '15+ คอร์ท',
          ];

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / 5;
          return Column(
            children: [
              // Numbers 1 to 5
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 1; i <= 5; i++)
                    SizedBox(
                      width: itemWidth,
                      child: Text(
                        '$i',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: i == activeLevel
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: i == activeLevel
                              ? const Color(0xFFD91E28)
                              : const Color(0xFF374151),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              // Connecting line with nodes
              Stack(
                alignment: Alignment.center,
                children: [
                  // Horizontal line
                  Container(
                    height: 1.5,
                    margin: EdgeInsets.symmetric(horizontal: itemWidth / 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  // Nodes
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 1; i <= 5; i++)
                        SizedBox(
                          width: itemWidth,
                          child: Center(
                            child: i == activeLevel
                                ? Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFFD91E28),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFFFF2838,
                                          ).withValues(alpha: 0.65),
                                          blurRadius: 6,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  )
                                : Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i < activeLevel
                                          ? const Color(0xFFE26D74)
                                          : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Labels
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 1; i <= 5; i++)
                    SizedBox(
                      width: itemWidth,
                      child: Text(
                        labels[i - 1],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: i == activeLevel
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: i == activeLevel
                              ? const Color(0xFFD91E28)
                              : const Color(0xFF374151),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
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

  static Widget _buildCustomCardArt(String imageUrl, double size) {
    Widget content;
    if (imageUrl.startsWith('preset:')) {
      final key = imageUrl.substring('preset:'.length);
      final (iconData, label, color) = switch (key) {
        'tennis' => (Icons.sports_tennis_rounded, 'เทนนิส', const Color(0xFFD91E28)),
        'badminton' => (Icons.sports_baseball_rounded, 'แบดมินตัน', const Color(0xFF00897B)),
        'football' => (Icons.sports_soccer_rounded, 'ฟุตบอล', const Color(0xFF1E88E5)),
        'basketball' => (Icons.sports_basketball_rounded, 'บาสเกตบอล', const Color(0xFFFB8C00)),
        'trophy' => (Icons.emoji_events_rounded, 'รางวัล', const Color(0xFFF59E0B)),
        'stadium' => (Icons.stadium_rounded, 'สนาม', const Color(0xFF8B5CF6)),
        _ => (Icons.sports_rounded, 'กีฬา', const Color(0xFFD91E28)),
      };
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconData, size: size * 0.44, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      );
    } else if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      content = Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(
          Icons.broken_image_rounded,
          color: Colors.grey,
        ),
      );
    } else if (imageUrl.startsWith('data:image')) {
      try {
        final comma = imageUrl.indexOf(',');
        final bytes = comma != -1
            ? base64Decode(imageUrl.substring(comma + 1))
            : base64Decode(imageUrl);
        content = Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      } catch (_) {
        content = const Icon(Icons.broken_image_rounded, color: Colors.grey);
      }
    } else {
      content = Image.file(
        File(imageUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(
          Icons.image_outlined,
          color: Colors.grey,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.60),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF2535).withValues(alpha: 0.20),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Center(child: content),
      ),
    );
  }
}

