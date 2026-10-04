import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';
import 'package:sheserved/shared/widgets/thai_address_picker/glass_date_time_picker.dart';
import 'package:sheserved/shared/widgets/thai_buddhist_date_picker.dart';

import '../../application/book_court_booking_service.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../../domain/venue_local_time.dart';
import '../pages/court_reviews_page.dart';
import 'court_availability_picker.dart';
import 'court_booking_action_dialogs.dart';
import 'court_review_rating_card.dart';

typedef CourtBookingCallback =
    Future<void> Function(
      VenueCourt court, {
      DateTime? initialDate,
      DateTime? initialSlotStart,
    });

/// Venue detail bottom sheet: info, courts, operating hours, availability
/// and reviews. Booking entry points are delegated to [onBookCourt] so the
/// sheet itself never creates bookings — cancelling one of the user's own
/// confirmed bookings is the only mutation handled inline.
///
/// Court rows keep the sheet calm by hiding their actions behind a left
/// swipe (same Slidable pattern as the group detail sheet). Tapping a row
/// expands its availability grid right underneath that row — one grid at a
/// time — so nothing is swipe-only.
class CourtDetailSheet extends StatefulWidget {
  final VenueSummary venue;
  final BookCourtRepository repo;
  final String? sharedSportId;
  final ScrollController? scrollController;
  final String? userId;
  final CourtBookingCallback? onBookCourt;
  final Future<void> Function()? onWriteReview;
  final Future<void> Function()? onOpenMyBookings;

  const CourtDetailSheet({
    super.key,
    required this.venue,
    required this.repo,
    this.sharedSportId,
    this.scrollController,
    this.userId,
    this.onBookCourt,
    this.onWriteReview,
    this.onOpenMyBookings,
  });

  static Future<void> show(
    BuildContext context, {
    required VenueSummary venue,
    required BookCourtRepository repo,
    String? sharedSportId,
    String? userId,
    CourtBookingCallback? onBookCourt,
    Future<void> Function()? onWriteReview,
    Future<void> Function()? onOpenMyBookings,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => CourtDetailSheet(
          venue: venue,
          repo: repo,
          sharedSportId: sharedSportId,
          scrollController: scrollController,
          userId: userId,
          onBookCourt: onBookCourt,
          onWriteReview: onWriteReview,
          onOpenMyBookings: onOpenMyBookings,
        ),
      ),
    );
  }

  @override
  State<CourtDetailSheet> createState() => _CourtDetailSheetState();
}

class _CourtDetailSheetState extends State<CourtDetailSheet>
    with WidgetsBindingObserver {
  List<VenueCourt> _courts = [];
  List<VenueBooking> _upcomingBookings = [];
  List<VenueOperatingHours> _hours = [];
  List<VenueReview> _reviews = [];
  VenueOwnerPublicProfile? _ownerProfile;
  String? _bookingNotice;
  bool _hoursExpanded = false;
  bool _loading = true;
  bool _availabilityLoading = false;
  bool _checkingSlot = false;
  String? _expandedCourtId;
  String? _availabilityError;
  String? _availabilityNotice;
  CourtAvailability? _availability;
  late DateTime _availabilityDate;
  int _availabilityRequestId = 0;
  Timer? _opensAtTimer;

  late final BookCourtBookingService _booking = BookCourtBookingService(
    create: widget.repo.createBooking,
    cancel: widget.repo.cancelBooking,
    decide: widget.repo.decideBooking,
    changeSlot: widget.repo.changePendingBookingSlot,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _availabilityDate = VenueLocalTime.today(widget.venue.timezone);
    _load();
  }

  @override
  void dispose() {
    _opensAtTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Foreground resume refreshes the expanded grid — a sealed slot may
  /// have reached its opensAt while the app was suspended.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final courtId = _expandedCourtId;
    if (courtId == null) return;
    final court = _courts.where((c) => c.id == courtId).firstOrNull;
    if (court != null) _loadAvailability(court);
  }

  /// Reloads shortly after the nearest upcoming opensAt so sealed slots
  /// flip to selectable while the panel stays open.
  void _scheduleOpensAtRefresh(VenueCourt court, CourtAvailability a) {
    _opensAtTimer?.cancel();
    _opensAtTimer = null;
    DateTime? next = a.nextReleaseAt;
    for (final entry in a.notOpen) {
      if (next == null || entry.opensAt.isBefore(next)) next = entry.opensAt;
    }
    if (next == null) return;
    var delay = next.difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    _opensAtTimer = Timer(delay + const Duration(seconds: 1), () {
      if (mounted && _expandedCourtId == court.id) _loadAvailability(court);
    });
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repo.listPublicCourts(
          widget.venue.id,
          sportId: widget.sharedSportId,
        ),
        widget.repo.listPublicOperatingHours(widget.venue.id),
        widget.repo.listVenueReviews(widget.venue.id, limit: 5),
        _loadPublicOwnerProfile(),
        _loadUpcomingBookings(),
      ]);
      if (!mounted) return;
      setState(() {
        _courts = results[0] as List<VenueCourt>;
        _hours = results[1] as List<VenueOperatingHours>;
        _reviews = results[2] as List<VenueReview>;
        _ownerProfile = results[3] as VenueOwnerPublicProfile?;
        _upcomingBookings = results[4] as List<VenueBooking>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The user's own confirmed bookings whose slot has not ended yet, soonest
  /// first — instant-confirmed and owner-approved bookings both land in
  /// `confirmed`, so one status check covers both. Deliberately not scoped to
  /// this venue: the point of the section is to warn about a clash before the
  /// user books again. Booking instants are absolute, so "has not ended yet"
  /// is a plain timestamp comparison with no venue-local math.
  Future<List<VenueBooking>> _loadUpcomingBookings() async {
    final userId = widget.userId;
    if (userId == null) return const [];
    try {
      final bookings = await widget.repo.listMyBookings(userId);
      final now = DateTime.now();
      return bookings
          .where((b) => b.isConfirmed && b.endsAt.isAfter(now))
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _cancelUpcoming(VenueBooking booking) async {
    if (!booking.cancellableByBooker) {
      await CourtBookingActionDialogs.showCutoffPassed(context);
      return;
    }
    final ok = await CourtBookingActionDialogs.confirmUserCancel(
      context,
      venueName: booking.venueName ?? '',
      cutoffMinutes: booking.cancellationCutoffMinutes,
    );
    if (!ok || !mounted) return;
    try {
      await _booking.cancelBooking(userId: widget.userId, booking: booking);
      final upcoming = await _loadUpcomingBookings();
      if (!mounted) return;
      setState(() {
        _upcomingBookings = upcoming;
        _bookingNotice = 'ยกเลิกการจองแล้ว';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _bookingNotice = _mapBookingError(e));
    }
  }

  Future<VenueOwnerPublicProfile?> _loadPublicOwnerProfile() async {
    try {
      return await widget.repo.getPublicVenueOwnerProfile(widget.venue.id);
    } catch (_) {
      return null;
    }
  }

  /// Opens the full review page (summary, bands, topics, filtered list)
  /// and refreshes the compact preview when coming back.
  Future<void> _openReviewsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CourtReviewsPage(venue: widget.venue, repo: widget.repo),
      ),
    );
    if (mounted) _load();
  }

  Future<CourtAvailability> _fetchAvailability(
    VenueCourt court,
    DateTime date,
  ) {
    final nextDate = VenueLocalTime.addCalendarDays(date, 1);
    return widget.repo.getCourtAvailability(
      court.id,
      VenueLocalTime.atWallTime(date, widget.venue.timezone, 0),
      VenueLocalTime.atWallTime(nextDate, widget.venue.timezone, 0),
    );
  }

  /// Tapping a court row opens its grid and closes whichever other grid was
  /// open, so the sheet never shows two tables at once. Tapping the open row
  /// again closes it.
  void _toggleCourtAvailability(VenueCourt court) {
    if (_checkingSlot) return;
    if (_expandedCourtId == court.id) {
      _availabilityRequestId++;
      _opensAtTimer?.cancel();
      setState(() {
        _expandedCourtId = null;
        _availability = null;
        _availabilityError = null;
        _availabilityNotice = null;
        _availabilityLoading = false;
      });
      return;
    }
    _loadAvailability(court);
  }

  Future<void> _loadAvailability(
    VenueCourt court, {
    bool preserveNotice = false,
  }) async {
    final requestId = ++_availabilityRequestId;
    final date = _availabilityDate;
    setState(() {
      _expandedCourtId = court.id;
      _availability = null;
      _availabilityError = null;
      if (!preserveNotice) _availabilityNotice = null;
      _availabilityLoading = true;
    });
    try {
      final availability = await _fetchAvailability(court, date);
      if (!mounted ||
          requestId != _availabilityRequestId ||
          _expandedCourtId != court.id) {
        return;
      }
      setState(() {
        _availability = availability;
        _availabilityLoading = false;
      });
      _scheduleOpensAtRefresh(court, availability);
    } catch (_) {
      if (mounted &&
          requestId == _availabilityRequestId &&
          _expandedCourtId == court.id) {
        setState(() {
          _availabilityError = 'โหลดตารางว่างไม่สำเร็จ';
          _availabilityLoading = false;
        });
      }
    }
  }

  Future<void> _verifySlotAndBook(
    VenueCourt court,
    DateTime start,
    DateTime end,
  ) async {
    if (_checkingSlot || widget.onBookCourt == null) return;
    final requestId = _availabilityRequestId;
    final date = _availabilityDate;
    setState(() {
      _checkingSlot = true;
      _availabilityNotice = null;
    });

    CourtAvailability? latestAvailability;
    var checkFailed = false;
    try {
      latestAvailability = await _fetchAvailability(court, date);
    } catch (_) {
      checkFailed = true;
    }
    if (!mounted) return;
    final requestIsCurrent =
        requestId == _availabilityRequestId &&
        _expandedCourtId == court.id &&
        _availabilityDate == date;
    setState(() => _checkingSlot = false);
    if (!requestIsCurrent) return;

    if (checkFailed) {
      setState(
        () => _availabilityNotice = 'ตรวจสอบเวลาว่างไม่สำเร็จ กรุณาลองใหม่',
      );
      await _loadAvailability(court, preserveNotice: true);
      return;
    }

    final isFree =
        CourtAvailabilityPicker(
          availability: latestAvailability!,
          date: date,
          timezone: widget.venue.timezone,
          now: latestAvailability.serverNow,
        ).freeSlots.any(
          (slot) =>
              slot.start.isAtSameMomentAs(start) &&
              slot.end.isAtSameMomentAs(end),
        );
    if (!isFree) {
      // A sealed slot deserves its own notice with the opensAt instant.
      final opensAt = latestAvailability.opensAtFor(start);
      final serverNow = latestAvailability.serverNow;
      if (opensAt != null &&
          (serverNow == null || opensAt.isAfter(serverNow))) {
        setState(
          () => _availabilityNotice =
              'ช่วงเวลานี้ยังไม่เปิดจอง — '
              '${VenueLocalTime.formatInstantWall(opensAt, widget.venue.timezone)}',
        );
      } else {
        setState(
          () => _availabilityNotice = 'เวลานี้ไม่ว่างแล้ว กรุณาเลือกเวลาอื่น',
        );
      }
      await _loadAvailability(court, preserveNotice: true);
      return;
    }

    await _bookCourt(court, initialDate: date, initialSlotStart: start);
  }

  /// Delegates booking to [onBookCourt]; the booking dialog stays open on top
  /// of this sheet, so when the flow finishes (booked, declined or failed)
  /// the expanded grid is reloaded — never the rest of the sheet.
  Future<void> _bookCourt(
    VenueCourt court, {
    DateTime? initialDate,
    DateTime? initialSlotStart,
  }) async {
    await widget.onBookCourt!(
      court,
      initialDate: initialDate,
      initialSlotStart: initialSlotStart,
    );
    if (!mounted || _expandedCourtId != court.id) return;
    await _loadAvailability(court);
  }

  Future<void> _pickAvailabilityDate() async {
    final courtId = _expandedCourtId;
    final today = VenueLocalTime.today(widget.venue.timezone);
    final picked = await GlassDatePicker.show(
      context,
      initialDate: _availabilityDate.isBefore(today)
          ? today
          : _availabilityDate,
      firstDate: today,
      lastDate: VenueLocalTime.addCalendarDays(
        today,
        VenueLocalTime.maxAdvanceDays,
      ),
    );
    if (picked == null || courtId == null || !mounted) return;
    final court = _courts.where((c) => c.id == courtId).firstOrNull;
    if (court == null) return;
    setState(() => _availabilityDate = picked);
    await _loadAvailability(court);
  }

  Widget _availabilityLoadingBlock() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('กำลังโหลดตารางว่าง', style: TextStyle(fontSize: 13)),
      const SizedBox(height: 10),
      LinearProgressIndicator(
        minHeight: 4,
        borderRadius: BorderRadius.circular(2),
        color: AppColors.primaryDark,
        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
      ),
    ],
  );

  Widget _availabilityNoticeRow(String message) => Row(
    children: [
      Icon(Icons.info_outline_rounded, size: 18, color: Colors.orange.shade800),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(fontSize: 12.5))),
    ],
  );

  Widget _availabilityErrorRow(VenueCourt court) => Row(
    children: [
      Icon(Icons.error_outline_rounded, size: 18, color: Colors.red.shade600),
      const SizedBox(width: 8),
      const Expanded(child: Text('โหลดตารางว่างไม่สำเร็จ')),
      TextButton.icon(
        onPressed: () => _loadAvailability(court),
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('ลองใหม่'),
      ),
    ],
  );

  Widget _upcomingHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.swipe_left_rounded,
            size: 15,
            color: AppColors.primaryDark,
          ),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'ปัดการ์ดนัดหมายไปทางซ้ายเพื่อยกเลิกการจอง',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookingNoticeRow(String message) => Row(
    children: [
      Icon(Icons.info_outline_rounded, size: 18, color: Colors.orange.shade800),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(fontSize: 12.5))),
    ],
  );

  Widget _buildUpcomingBookingRow(VenueBooking booking, {bool isLast = false}) {
    final priceLabel = booking.priceTotal != null
        ? 'ราคารวม ${booking.priceTotal!.toStringAsFixed(2)} บาท'
        : booking.priceAmount != null
        ? '${booking.priceAmount!.toStringAsFixed(0)} บาท/'
              '${_unitLabel(booking.pricingUnit ?? 'hour')}'
        : null;

    final tile = NeumorphicInsetBox(
      height: null,
      borderRadius: 14,
      padding: EdgeInsets.zero,
      border: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking.venueName ?? booking.venueUnitLabel ?? 'สถานที่',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: NeumorphicTheme.textPrimary,
                    ),
                  ),
                ),
                _confirmedChip(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${booking.unitLabel ?? 'สนาม'} ${booking.courtName ?? ''}',
              style: const TextStyle(
                fontSize: 13,
                color: NeumorphicTheme.textSecondary,
              ),
            ),
            Text(
              _bookingRangeLabel(booking),
              style: const TextStyle(
                fontSize: 13,
                color: NeumorphicTheme.textSecondary,
              ),
            ),
            if (priceLabel != null)
              Text(
                priceLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: NeumorphicTheme.textPrimary,
                ),
              ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Slidable(
          key: ValueKey('upcoming_${booking.id}'),
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: 0.26,
            children: [
              _responsiveSlidableAction(
                onPressed: (_) => _cancelUpcoming(booking),
                backgroundColor: const Color(0xFFC62828),
                foregroundColor: Colors.white,
                icon: Icons.cancel_outlined,
                label: 'ยกเลิก',
              ),
            ],
          ),
          child: tile,
        ),
      ),
    );
  }

  static Widget _confirmedChip() {
    const color = Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'ยืนยันแล้ว',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// Booking instants are stored UTC — render them in the venue's timezone
  /// so the slot matches what the booker picked. The day collapses to
  /// 'วันนี้'/'พรุ่งนี้' when it can, else a short Thai date (12 ต.ค. 69).
  static String _bookingRangeLabel(VenueBooking booking) {
    String two(int n) => n.toString().padLeft(2, '0');
    final start = VenueLocalTime.wallTimeOfInstant(
      booking.startsAt,
      booking.timezone,
    );
    final end = VenueLocalTime.wallTimeOfInstant(
      booking.endsAt,
      booking.timezone,
    );
    final today = VenueLocalTime.today(booking.timezone);
    final startDate = VenueLocalTime.dateOfInstant(
      booking.startsAt,
      booking.timezone,
    );
    final dayLabel = startDate == today
        ? 'วันนี้'
        : startDate == VenueLocalTime.addCalendarDays(today, 1)
        ? 'พรุ่งนี้'
        : ThaiDateUtils.formatShortDateBE2Digit(start);
    return '$dayLabel ${two(start.hour)}:${two(start.minute)}'
        '–${two(end.hour)}:${two(end.minute)}';
  }

  static String _mapBookingError(Object e) {
    final raw = e.toString();
    if (raw.contains('CUTOFF_PASSED')) {
      return 'เลยเวลายกเลิกฟรีแล้ว กรุณาติดต่อเจ้าของสถานที่โดยตรง';
    }
    if (raw.contains('BOOKING_NOT_FOUND')) return 'ไม่พบการจองนี้แล้ว';
    if (raw.contains('UNAUTHORIZED')) return 'กรุณาเข้าสู่ระบบใหม่';
    return 'ยกเลิกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  @override
  Widget build(BuildContext context) {
    final venue = widget.venue;
    return Container(
      decoration: BoxDecoration(
        color: NeumorphicTheme.baseColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.9),
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: NeumorphicTheme.shadowDark.withValues(alpha: 0.35),
            blurRadius: 25,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pinned header — never scrolls with the content below.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 36,
                          child: Stack(
                            children: [
                              Center(
                                child: Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: NeumorphicSheetCloseButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          venue.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: NeumorphicTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                      children: [
                        if (venue.address?.isNotEmpty == true ||
                            venue.district != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.place_outlined,
                                size: 16,
                                color: NeumorphicTheme.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  [
                                    venue.address,
                                    venue.district,
                                    venue.province,
                                  ].whereType<String>().join(', '),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: NeumorphicTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (venue.description?.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(
                            venue.description!,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: NeumorphicTheme.textPrimary,
                            ),
                          ),
                        ],
                        if (_hours.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleHours,
                            child: _frostedCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sectionHeader(
                                    icon: Icons.schedule_rounded,
                                    title: 'เวลาเปิด-ปิด',
                                    trailing: _hoursToggle(),
                                  ),
                                  const SizedBox(height: 10),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 48),
                                    child: _hoursExpanded
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              for (final h in _weekOrderedHours)
                                                _hoursRow(h),
                                            ],
                                          )
                                        : _collapsedHoursRow(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _frostedCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader(
                                icon: Icons.sports_tennis_rounded,
                                title: 'รายการที่จองได้',
                                badge: _courts.isEmpty
                                    ? null
                                    : '${_courts.length}',
                              ),
                              if (_courts.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _swipeHint(canBook: widget.onBookCourt != null),
                              ],
                              const SizedBox(height: 8),
                              if (_courts.isEmpty)
                                NeumorphicInsetBox(
                                  width: double.infinity,
                                  height: null,
                                  borderRadius: 14,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.event_busy_rounded,
                                        size: 32,
                                        color: NeumorphicTheme.textSecondary,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'ยังไม่มีรายการที่เปิดจอง',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: NeumorphicTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                for (final court in _courts)
                                  _buildCourtTile(
                                    court,
                                    isLast: court == _courts.last,
                                  ),
                            ],
                          ),
                        ),
                        if (_upcomingBookings.isNotEmpty ||
                            _bookingNotice != null) ...[
                          const SizedBox(height: 16),
                          _frostedCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionHeader(
                                  icon: Icons.upcoming_rounded,
                                  title: 'นัดหมายกำลังจะเริ่ม',
                                  badge: _upcomingBookings.isEmpty
                                      ? null
                                      : '${_upcomingBookings.length}',
                                ),
                                if (_upcomingBookings.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _upcomingHint(),
                                  const SizedBox(height: 8),
                                  for (final booking in _upcomingBookings)
                                    _buildUpcomingBookingRow(
                                      booking,
                                      isLast: booking == _upcomingBookings.last,
                                    ),
                                ],
                                if (_bookingNotice != null) ...[
                                  const SizedBox(height: 8),
                                  _bookingNoticeRow(_bookingNotice!),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (widget.onOpenMyBookings != null) ...[
                          const SizedBox(height: 12),
                          _myBookingsButton(),
                        ],
                        const SizedBox(height: 16),
                        _frostedCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CourtReviewRatingCard(
                                averageRating: venue.averageRating,
                                reviewCount: venue.reviewCount,
                                reviews: _reviews,
                                ownerProfile: _ownerProfile,
                                onSeeAll: _openReviewsPage,
                              ),
                              if (widget.onWriteReview != null) ...[
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: _reviewButton(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _reviewButton() {
    return NeumorphicContainer(
      borderRadius: 14,
      depth: 3,
      blur: 6,
      border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onWriteReview,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  size: 16,
                  color: AppColors.primaryDark,
                ),
                SizedBox(width: 6),
                Text(
                  'เขียนรีวิว',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _myBookingsButton() {
    return NeumorphicContainer(
      width: double.infinity,
      borderRadius: 14,
      depth: 3,
      blur: 6,
      border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onOpenMyBookings,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: AppColors.primaryDark,
                ),
                SizedBox(width: 8),
                Text(
                  'ประวัติการจองของฉัน',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.primaryDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The hours card stays one line tall until the user taps it: collapsed it
  /// shows today's venue-local window only, expanded it lists the whole week.
  void _toggleHours() => setState(() => _hoursExpanded = !_hoursExpanded);

  /// Weeks run Monday-first; [VenueOperatingHours.dayOfWeek] uses 0 = Sunday.
  List<VenueOperatingHours> get _weekOrderedHours =>
      [..._hours]
        ..sort((a, b) => (a.dayOfWeek + 6) % 7 - ((b.dayOfWeek + 6) % 7));

  Widget _collapsedHoursRow() {
    final todayDow = VenueLocalTime.now(widget.venue.timezone).weekday % 7;
    final today = _hours.where((h) => h.dayOfWeek == todayDow).firstOrNull;
    if (today == null) {
      return const Text(
        'ไม่ระบุเวลาเปิด-ปิดของวันนี้',
        style: TextStyle(fontSize: 12.5, color: NeumorphicTheme.textSecondary),
      );
    }
    return _hoursRow(today);
  }

  Widget _hoursToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _hoursExpanded ? 'ซ่อน' : 'ดูทั้งสัปดาห์',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: NeumorphicTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        NeumorphicIconButton(
          icon: _hoursExpanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          onPressed: _toggleHours,
          size: 28,
          iconSize: 18,
          color: AppColors.primaryDark,
        ),
      ],
    );
  }

  /// 'HH:MM[:SS]' → 'HH.MM'
  static String _formatClock(String? raw) {
    final parts = (raw ?? '').split(':');
    return parts.length >= 2 ? '${parts[0]}.${parts[1]}' : raw ?? '';
  }

  /// 'HH:MM[:SS]' → minutes since midnight; null when missing/unparsable.
  static int? _clockMinutes(String? raw) {
    final parts = (raw ?? '').split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// Live open/closed state — only meaningful on today's row, the one line
  /// that stays visible when the week is collapsed.
  bool? _isOpenNow(VenueOperatingHours h) {
    if (h.isClosed) return null;
    final now = VenueLocalTime.now(widget.venue.timezone);
    if (h.dayOfWeek != now.weekday % 7) return null;
    final open = _clockMinutes(h.openTime);
    final close = _clockMinutes(h.closeTime);
    if (open == null || close == null) return null;
    final minute = now.hour * 60 + now.minute;
    return close > open
        ? minute >= open && minute < close
        : minute >= open || minute < close;
  }

  Widget _hoursRow(VenueOperatingHours h) {
    final closed = h.isClosed;
    final openNow = closed ? null : _isOpenNow(h);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              _dayLabel(h.dayOfWeek),
              style: const TextStyle(
                fontSize: 12.5,
                color: NeumorphicTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                Text(
                  closed
                      ? 'ปิด'
                      : '${_formatClock(h.openTime)} - ${_formatClock(h.closeTime)} น.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: closed
                        ? Colors.red.shade400
                        : NeumorphicTheme.textPrimary,
                  ),
                ),
                if (openNow != null)
                  Text(
                    openNow ? 'เปิดอยู่' : 'ปิดแล้ว',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: openNow
                          ? Colors.green.shade600
                          : Colors.red.shade400,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _swipeHint({required bool canBook}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.swipe_left_rounded,
            size: 15,
            color: AppColors.primaryDark,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              canBook
                  ? 'ปัดการ์ด${widget.venue.venueUnitLabel ?? 'สนาม'}ไปทางซ้ายเพื่อดูตารางว่างหรือจอง'
                  : 'ปัดการ์ด${widget.venue.venueUnitLabel ?? 'สนาม'}ไปทางซ้ายเพื่อดูตารางว่าง',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _bookingReleaseTime(CourtAvailability? availability) {
    final rawTime = availability?.release?.selectedDayReleaseTime;
    if (rawTime == null) return null;
    final releaseTime = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    return 'เวลาเปิดรับจอง: $releaseTime';
  }

  String? _nextReleaseMessage(CourtAvailability availability) {
    final nextReleaseAt = availability.nextReleaseAt;
    if (nextReleaseAt == null) return null;
    final wall = VenueLocalTime.wallTimeOfInstant(
      nextReleaseAt,
      widget.venue.timezone,
    );
    final date = _formatDate(DateTime(wall.year, wall.month, wall.day));
    final time =
        '${wall.hour.toString().padLeft(2, '0')}:'
        '${wall.minute.toString().padLeft(2, '0')}';
    return 'เปิดจองครั้งถัดไปในวันที่ $date เริ่มเวลา $time น.';
  }

  /// The grid that opens underneath the court row it belongs to. It sits in a
  /// sunken field so it reads as an extension of the row that was tapped.
  Widget _buildAvailabilityPanel(VenueCourt court) {
    final availability = _availability;
    CourtAvailabilityPicker? picker;
    String? releaseSummary;
    if (availability != null) {
      final availabilityPicker = CourtAvailabilityPicker(
        availability: availability,
        date: _availabilityDate,
        timezone: widget.venue.timezone,
        now: availability.serverNow,
        onSlotTap: widget.onBookCourt == null || _checkingSlot
            ? null
            : (start, end) => _verifySlotAndBook(court, start, end),
      );
      picker = availabilityPicker;
      releaseSummary = availabilityPicker.allSlotsClosed
          ? _nextReleaseMessage(availability)
          : _bookingReleaseTime(availability);
    }
    return NeumorphicInsetBox(
      height: null,
      borderRadius: 14,
      padding: const EdgeInsets.all(12),
      border: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 18,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'ตารางว่าง',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: NeumorphicTheme.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _pickAvailabilityDate,
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(_formatDate(_availabilityDate)),
              ),
            ],
          ),
          if (releaseSummary != null)
            Text(
              releaseSummary,
              style: const TextStyle(
                fontSize: 11,
                color: NeumorphicTheme.textSecondary,
              ),
            ),
          if (_availabilityNotice != null) ...[
            const SizedBox(height: 6),
            _availabilityNoticeRow(_availabilityNotice!),
          ],
          if (_checkingSlot) ...[
            const SizedBox(height: 8),
            const Text(
              'กำลังตรวจสอบเวลาว่างจากตารางล่าสุด',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              minHeight: 4,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              color: AppColors.primaryDark,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            ),
          ],
          const SizedBox(height: 8),
          if (_availabilityLoading)
            _availabilityLoadingBlock()
          else if (_availabilityError != null)
            _availabilityErrorRow(court)
          else
            ?picker,
        ],
      ),
    );
  }

  Widget _buildCourtTile(VenueCourt court, {bool isLast = false}) {
    final expanded = _expandedCourtId == court.id;
    final isInstant = court.approvalMode == BookingApprovalMode.instant;
    final displayedPrice = court.startingPriceAmount ?? court.priceAmount;
    final displayedPriceLabel = displayedPrice == null
        ? null
        : displayedPrice == displayedPrice.roundToDouble()
        ? displayedPrice.toStringAsFixed(0)
        : displayedPrice.toStringAsFixed(2);

    final actions = <Widget>[
      _responsiveSlidableAction(
        onPressed: (_) => _loadAvailability(court),
        backgroundColor: AppColors.primary,
        foregroundColor: NeumorphicTheme.textPrimary,
        icon: Icons.schedule_rounded,
        label: 'ดูตารางว่าง',
      ),
      if (widget.onBookCourt != null)
        _responsiveSlidableAction(
          onPressed: (_) => _bookCourt(court),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          icon: isInstant ? Icons.flash_on_rounded : Icons.send_rounded,
          label: isInstant ? 'จองเลย' : 'ขอจอง',
        ),
    ];

    final tile = NeumorphicInsetBox(
      height: null,
      borderRadius: 14,
      padding: EdgeInsets.zero,
      border: BorderSide(
        color: expanded
            ? AppColors.primaryDark
            : Colors.white.withValues(alpha: 0.7),
        width: expanded ? 1.6 : 1,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _toggleCourtAvailability(court),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${court.unitLabel ?? 'สนาม'} ${court.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: NeumorphicTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (court.indoor != null)
                            _tag(court.indoor! ? 'ในร่ม' : 'กลางแจ้ง'),
                          if (court.courtType != null) _tag(court.courtType!),
                          _tag(isInstant ? 'จองได้ทันที' : 'รอเจ้าของอนุมัติ'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (displayedPriceLabel != null)
                      Text(
                        court.hasTimePricing ||
                                court.startingPriceAmount != null
                            ? 'เริ่มต้น $displayedPriceLabel ฿/ชม.'
                            : '$displayedPriceLabel ฿/${_unitLabel(court.pricingUnit)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Slidable(
              key: ValueKey('court_${court.id}'),
              endActionPane: ActionPane(
                motion: const ScrollMotion(),
                extentRatio: (actions.length * 0.26).clamp(0.26, 0.6),
                children: actions,
              ),
              child: tile,
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            _buildAvailabilityPanel(court),
          ],
        ],
      ),
    );
  }

  static Widget _frostedCard({required Widget child}) {
    return NeumorphicContainer(
      padding: const EdgeInsets.all(14),
      borderRadius: 20,
      depth: 4,
      blur: 8,
      border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      child: child,
    );
  }

  static Widget _sectionHeader({
    required IconData icon,
    required String title,
    String? badge,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: NeumorphicTheme.baseColor,
            boxShadow: NeumorphicTheme.smallShadows(distance: 2, blur: 4),
          ),
          child: Icon(icon, size: 18, color: AppColors.primaryDark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: NeumorphicTheme.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: NeumorphicTheme.baseColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: NeumorphicTheme.smallShadows(
                      distance: 1.5,
                      blur: 3,
                    ),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _responsiveSlidableAction({
    required void Function(BuildContext) onPressed,
    required Color backgroundColor,
    required Color foregroundColor,
    required IconData icon,
    required String label,
  }) {
    return CustomSlidableAction(
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foregroundColor, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: NeumorphicTheme.baseColor,
      borderRadius: BorderRadius.circular(8),
      boxShadow: NeumorphicTheme.smallShadows(distance: 1.5, blur: 3),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: NeumorphicTheme.textSecondary,
      ),
    ),
  );

  static String _formatDate(DateTime date) =>
      ThaiDateUtils.formatShortDateBE2Digit(date);

  static String _dayLabel(int dow) => switch (dow) {
    0 => 'อาทิตย์',
    1 => 'จันทร์',
    2 => 'อังคาร',
    3 => 'พุธ',
    4 => 'พฤหัสบดี',
    5 => 'ศุกร์',
    6 => 'เสาร์',
    _ => '',
  };

  static String _unitLabel(String unit) => switch (unit) {
    'session' => 'รอบ',
    'match' => 'แมตช์',
    'day' => 'วัน',
    _ => 'ชม.',
  };
}
