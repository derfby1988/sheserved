import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../../domain/venue_local_time.dart';
import '../pages/court_reviews_page.dart';
import 'court_availability_picker.dart';
import 'court_review_rating_card.dart';

/// Venue detail bottom sheet: info, courts, operating hours, availability
/// and reviews. Booking entry points are delegated to [onBookCourt] so the
/// sheet itself never creates bookings.
///
/// Court rows keep the sheet calm by hiding their actions behind a left
/// swipe (same Slidable pattern as the group detail sheet); tapping a row
/// only selects it and loads its availability, so nothing is swipe-only.
class CourtDetailSheet extends StatefulWidget {
  final VenueSummary venue;
  final BookCourtRepository repo;
  final String? sharedSportId;
  final ScrollController? scrollController;
  final Future<void> Function(VenueCourt court)? onBookCourt;
  final Future<void> Function()? onWriteReview;

  const CourtDetailSheet({
    super.key,
    required this.venue,
    required this.repo,
    this.sharedSportId,
    this.scrollController,
    this.onBookCourt,
    this.onWriteReview,
  });

  static Future<void> show(
    BuildContext context, {
    required VenueSummary venue,
    required BookCourtRepository repo,
    String? sharedSportId,
    Future<void> Function(VenueCourt court)? onBookCourt,
    Future<void> Function()? onWriteReview,
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
          onBookCourt: onBookCourt,
          onWriteReview: onWriteReview,
        ),
      ),
    );
  }

  @override
  State<CourtDetailSheet> createState() => _CourtDetailSheetState();
}

class _CourtDetailSheetState extends State<CourtDetailSheet> {
  List<VenueCourt> _courts = [];
  List<VenueOperatingHours> _hours = [];
  List<VenueReview> _reviews = [];
  bool _loading = true;
  bool _availabilityLoading = false;
  String? _selectedCourtId;
  String? _availabilityError;
  CourtAvailability? _availability;
  late DateTime _availabilityDate;
  int _availabilityRequestId = 0;

  @override
  void initState() {
    super.initState();
    _availabilityDate = VenueLocalTime.today(widget.venue.timezone);
    _load();
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
      ]);
      if (!mounted) return;
      setState(() {
        _courts = results[0] as List<VenueCourt>;
        _hours = results[1] as List<VenueOperatingHours>;
        _reviews = results[2] as List<VenueReview>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _loadAvailability(VenueCourt court) async {
    final requestId = ++_availabilityRequestId;
    setState(() {
      _selectedCourtId = court.id;
      _availability = null;
      _availabilityError = null;
      _availabilityLoading = true;
    });
    try {
      final nextDate = VenueLocalTime.addCalendarDays(_availabilityDate, 1);
      final availability = await widget.repo.getCourtAvailability(
        court.id,
        VenueLocalTime.atWallTime(_availabilityDate, widget.venue.timezone, 0),
        VenueLocalTime.atWallTime(nextDate, widget.venue.timezone, 0),
      );
      if (!mounted ||
          requestId != _availabilityRequestId ||
          _selectedCourtId != court.id) {
        return;
      }
      setState(() {
        _availability = availability;
        _availabilityLoading = false;
      });
    } catch (_) {
      if (mounted &&
          requestId == _availabilityRequestId &&
          _selectedCourtId == court.id) {
        setState(() {
          _availabilityError = 'โหลดตารางว่างไม่สำเร็จ';
          _availabilityLoading = false;
        });
      }
    }
  }

  Future<void> _pickAvailabilityDate() async {
    final courtId = _selectedCourtId;
    final today = VenueLocalTime.today(widget.venue.timezone);
    final picked = await showDatePicker(
      context: context,
      initialDate: _availabilityDate.isBefore(today)
          ? today
          : _availabilityDate,
      firstDate: today,
      lastDate: VenueLocalTime.addCalendarDays(today, 90),
    );
    if (picked == null || courtId == null || !mounted) return;
    final court = _courts.where((c) => c.id == courtId).firstOrNull;
    if (court == null) return;
    setState(() => _availabilityDate = picked);
    await _loadAvailability(court);
  }

  Widget _buildAvailabilityLoading() => _frostedCard(
    child: const Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text('กำลังโหลดตารางว่าง'),
      ],
    ),
  );

  Widget _buildAvailabilityError(VenueCourt court) => _frostedCard(
    child: Row(
      children: [
        Icon(Icons.error_outline_rounded, color: Colors.red.shade600),
        const SizedBox(width: 8),
        const Expanded(child: Text('โหลดตารางว่างไม่สำเร็จ')),
        TextButton.icon(
          onPressed: () => _loadAvailability(court),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('ลองใหม่'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final venue = widget.venue;
    final selectedCourt = _courts
        .where((court) => court.id == _selectedCourtId)
        .firstOrNull;
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
            : ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          venue.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: NeumorphicTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (widget.onWriteReview != null) ...[
                        const SizedBox(width: 8),
                        _reviewButton(),
                      ],
                    ],
                  ),
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
                    _frostedCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader(
                            icon: Icons.schedule_rounded,
                            title: 'เวลาเปิด-ปิด',
                          ),
                          const SizedBox(height: 10),
                          for (final h in _hours) _hoursRow(h),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _sectionHeader(
                    icon: Icons.sports_tennis_rounded,
                    title: 'สนาม/คอร์ท',
                    badge: _courts.isEmpty ? null : '${_courts.length}',
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
                      padding: const EdgeInsets.symmetric(vertical: 18),
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
                            'ยังไม่มีสนามที่เปิดจอง',
                            style: const TextStyle(
                              fontSize: 13,
                              color: NeumorphicTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final court in _courts) _buildCourtTile(court),
                  if (_availabilityLoading) ...[
                    const SizedBox(height: 4),
                    _buildAvailabilityLoading(),
                  ],
                  if (_availabilityError != null && selectedCourt != null) ...[
                    const SizedBox(height: 4),
                    _buildAvailabilityError(selectedCourt),
                  ],
                  if (_availability != null) ...[
                    const SizedBox(height: 4),
                    _buildAvailabilityCard(_availability!),
                  ],
                  const SizedBox(height: 16),
                  _frostedCard(
                    child: CourtReviewRatingCard(
                      averageRating: venue.averageRating,
                      reviewCount: venue.reviewCount,
                      reviews: _reviews,
                      onSeeAll: _openReviewsPage,
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
                  'รีวิว',
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

  Widget _hoursRow(VenueOperatingHours h) {
    final closed = h.isClosed;
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
            child: Text(
              closed ? 'ปิด' : '${h.openTime ?? ''}–${h.closeTime ?? ''}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: closed
                    ? Colors.red.shade400
                    : NeumorphicTheme.textPrimary,
              ),
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
                  ? 'ปัดการ์ดสนามไปทางซ้ายเพื่อดูตารางว่างหรือจอง'
                  : 'ปัดการ์ดสนามไปทางซ้ายเพื่อดูตารางว่าง',
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

  Widget _buildAvailabilityCard(CourtAvailability availability) {
    final court = _courts
        .where((c) => c.id == availability.courtId)
        .firstOrNull;
    return _frostedCard(
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
              Expanded(
                child: Text(
                  court == null
                      ? 'ตารางว่าง'
                      : '${court.unitLabel ?? 'สนาม'} ${court.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
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
          const SizedBox(height: 4),
          Text(
            'เวลาท้องถิ่นของสนาม (${widget.venue.timezone})',
            style: const TextStyle(
              fontSize: 11,
              color: NeumorphicTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          CourtAvailabilityPicker(
            availability: availability,
            date: _availabilityDate,
            timezone: widget.venue.timezone,
          ),
        ],
      ),
    );
  }

  Widget _buildCourtTile(VenueCourt court) {
    final selected = _selectedCourtId == court.id;
    final isInstant = court.approvalMode == BookingApprovalMode.instant;

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
          onPressed: (_) => widget.onBookCourt!(court),
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          icon: isInstant ? Icons.flash_on_rounded : Icons.send_rounded,
          label: isInstant ? 'จองเลย' : 'ขอจอง',
        ),
    ];

    final tile = NeumorphicContainer(
      borderRadius: 16,
      depth: 4,
      blur: 8,
      border: Border.all(
        color: selected
            ? AppColors.primaryDark
            : Colors.white.withValues(alpha: 0.7),
        width: selected ? 1.6 : 1,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _loadAvailability(court),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${court.unitLabel ?? 'สนาม'} ${court.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: NeumorphicTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (court.priceAmount != null)
                      Text(
                        '${court.priceAmount!.toStringAsFixed(0)} ฿/${_unitLabel(court.pricingUnit)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                  ],
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
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
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
      '${date.day}/${date.month}/${date.year + 543}';

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
