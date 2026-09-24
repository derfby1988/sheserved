import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import 'court_availability_picker.dart';
import 'court_review_rating_card.dart';

/// Venue detail bottom sheet: info, courts, operating hours, availability
/// and reviews. Booking entry points are delegated to [onBookCourt] so the
/// sheet itself never creates bookings.
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
  String? _selectedCourtId;
  CourtAvailability? _availability;
  DateTime _availabilityDate = DateTime.now();

  @override
  void initState() {
    super.initState();
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
        widget.repo.listVenueReviews(widget.venue.id),
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

  Future<void> _loadAvailability(VenueCourt court) async {
    setState(() {
      _selectedCourtId = court.id;
      _availability = null;
    });
    try {
      final dayStart = DateTime(
        _availabilityDate.year,
        _availabilityDate.month,
        _availabilityDate.day,
      );
      final availability = await widget.repo.getCourtAvailability(
        court.id,
        dayStart,
        dayStart.add(const Duration(days: 1)),
      );
      if (!mounted || _selectedCourtId != court.id) return;
      setState(() => _availability = availability);
    } catch (_) {
      if (mounted && _selectedCourtId == court.id) {
        setState(() => _availability = CourtAvailability(courtId: court.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final venue = widget.venue;
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            )
          : ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        venue.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (widget.onWriteReview != null)
                      TextButton.icon(
                        onPressed: widget.onWriteReview,
                        icon: const Icon(Icons.rate_review_outlined, size: 18),
                        label: const Text('รีวิว'),
                      ),
                  ],
                ),
                if (venue.address?.isNotEmpty == true ||
                    venue.district != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            venue.address,
                            venue.district,
                            venue.province,
                          ].whereType<String>().join(', '),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
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
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
                if (_hours.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'เวลาเปิด-ปิด',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  for (final h in _hours)
                    Text(
                      '${_dayLabel(h.dayOfWeek)}: ${h.isClosed ? 'ปิด' : '${h.openTime ?? ''}–${h.closeTime ?? ''}'}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'สนาม/คอร์ท',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (_courts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'ยังไม่มีสนามที่เปิดจอง',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                else
                  for (final court in _courts) _buildCourtTile(court),
                if (_availability != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CourtAvailabilityPicker(
                          availability: _availability!,
                          date: _availabilityDate,
                        ),
                      ),
                      IconButton(
                        tooltip: 'เลือกวัน',
                        icon: const Icon(Icons.calendar_month_rounded),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _availabilityDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 90),
                            ),
                          );
                          if (picked != null && _selectedCourtId != null) {
                            setState(() => _availabilityDate = picked);
                            final court = _courts
                                .where((c) => c.id == _selectedCourtId)
                                .firstOrNull;
                            if (court != null) _loadAvailability(court);
                          }
                        },
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                CourtReviewRatingCard(
                  averageRating: venue.averageRating,
                  reviewCount: venue.reviewCount,
                  reviews: _reviews,
                ),
              ],
            ),
    );
  }

  Widget _buildCourtTile(VenueCourt court) {
    final selected = _selectedCourtId == court.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.primaryDark : Colors.grey.shade200,
          width: selected ? 1.6 : 1,
        ),
      ),
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
                    ),
                  ),
                ),
                if (court.priceAmount != null)
                  Text(
                    '${court.priceAmount!.toStringAsFixed(0)} ฿/${_unitLabel(court.pricingUnit)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                if (court.indoor != null)
                  _tag(court.indoor! ? 'ในร่ม' : 'กลางแจ้ง'),
                if (court.courtType != null) _tag(court.courtType!),
                _tag(
                  court.approvalMode == BookingApprovalMode.instant
                      ? 'จองได้ทันที'
                      : 'รอเจ้าของอนุมัติ',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _loadAvailability(court),
                  icon: const Icon(Icons.schedule_rounded, size: 16),
                  label: const Text('ดูตารางว่าง'),
                ),
                const Spacer(),
                if (widget.onBookCourt != null)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                    ),
                    onPressed: () => widget.onBookCourt!(court),
                    child: Text(
                      court.approvalMode == BookingApprovalMode.instant
                          ? 'จองเลย'
                          : 'ขอจอง',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11)),
  );

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
