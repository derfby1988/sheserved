import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';

import '../../application/book_court_booking_service.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../widgets/court_booking_action_dialogs.dart';
import '../widgets/court_booking_sheet.dart';
import '../widgets/court_review_sheet.dart';

/// Booker-side booking list: upcoming/pending/confirmed plus history,
/// with cancel / change-slot / review actions.
class CourtMyBookingsPage extends StatefulWidget {
  final BookCourtRepository repo;

  const CourtMyBookingsPage({super.key, required this.repo});

  @override
  State<CourtMyBookingsPage> createState() => _CourtMyBookingsPageState();
}

class _CourtMyBookingsPageState extends State<CourtMyBookingsPage> {
  List<VenueBooking> _bookings = [];
  Set<String> _reviewedBookingIds = {};
  List<VenueReviewTag> _tagCatalog = const [];
  bool _loading = true;
  bool _showHistory = false;

  String? get _userId => AuthService.instance.currentUser?.id;

  late final BookCourtBookingService _booking = BookCourtBookingService(
    create: widget.repo.createBooking,
    cancel: widget.repo.cancelBooking,
    decide: widget.repo.decideBooking,
    changeSlot: widget.repo.changePendingBookingSlot,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.repo.listMyBookings(userId),
        widget.repo.listMyReviewedBookingIds(userId),
        widget.repo.listReviewTagCatalog(),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = results[0] as List<VenueBooking>;
        _reviewedBookingIds = results[1] as Set<String>;
        _tagCatalog = results[2] as List<VenueReviewTag>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(VenueBooking b) async {
    if (!b.cancellableByBooker) {
      await CourtBookingActionDialogs.showCutoffPassed(context);
      return;
    }
    final ok = await CourtBookingActionDialogs.confirmUserCancel(
      context,
      venueName: b.venueName ?? '',
      cutoffMinutes: b.cancellationCutoffMinutes,
    );
    if (!ok) return;
    try {
      await _booking.cancelBooking(userId: _userId, booking: b);
      _toast('ยกเลิกการจองแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _changeSlot(VenueBooking b) async {
    final court = VenueCourt(
      id: b.courtId,
      venueId: b.venueId,
      sportId: b.sportId,
      name: b.courtName ?? '',
      unitLabel: b.unitLabel,
      priceAmount: b.priceAmount,
      pricingUnit: b.pricingUnit ?? 'hour',
      approvalMode: b.approvalMode,
    );
    final slot = await CourtBookingSheet.show(
      context,
      court: court,
      venueName: b.venueName ?? '',
      initialDate: b.startsAt,
    );
    if (slot == null) return;
    try {
      await _booking.movePendingSlot(
        userId: _userId,
        booking: b,
        startsAt: slot.start,
        endsAt: slot.end,
        termsVersion: b.termsVersion,
      );
      _toast('เปลี่ยนเวลาแล้ว รอเจ้าของอนุมัติ');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _writeReview(VenueBooking b) async {
    final draft = await CourtReviewSheet.show(
      context,
      venueName: b.venueName ?? '',
      tagCatalog: _tagCatalog,
    );
    if (draft == null) return;
    try {
      await widget.repo.submitReview(
        userId: _userId!,
        bookingId: b.id,
        rating: draft.rating,
        comment: draft.comment,
        tagIds: draft.tagIds.toList(),
        customTags: draft.customTags,
      );
      _toast('ขอบคุณสำหรับรีวิว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final active = _bookings
        .where(
          (b) =>
              b.isPending ||
              b.isConfirmed ||
              b.status == VenueBookingStatus.completed,
        )
        .toList();
    final history = _bookings
        .where(
          (b) =>
              !b.isPending &&
              !b.isConfirmed &&
              b.status != VenueBookingStatus.completed,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('การจองสนามของฉัน'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _userId == null
          ? const Center(child: Text('กรุณาเข้าสู่ระบบเพื่อดูการจอง'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  if (active.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'ยังไม่มีการจอง',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else
                    for (final b in active) _buildBookingCard(b),
                  if (history.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _showHistory = !_showHistory),
                        icon: Icon(
                          _showHistory
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        label: Text(
                          _showHistory
                              ? 'ซ่อนประวัติ'
                              : 'ประวัติการจอง (${history.length})',
                        ),
                      ),
                    ),
                    if (_showHistory)
                      for (final b in history) _buildBookingCard(b),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildBookingCard(VenueBooking b) {
    final reviewable =
        b.isCompleted && !_reviewedBookingIds.contains(b.id);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    b.venueName ?? 'สนาม',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                _statusChip(b.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${b.unitLabel ?? 'สนาม'} ${b.courtName ?? ''}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            Text(
              _fmtRange(b.startsAt, b.endsAt),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            if (b.priceAmount != null)
              Text(
                '${b.priceAmount!.toStringAsFixed(0)} บาท/${_unitLabel(b.pricingUnit)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (b.rejectionReason?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'เหตุผลที่ถูกปฏิเสธ: ${b.rejectionReason}',
                  style: const TextStyle(fontSize: 12.5, color: Colors.red),
                ),
              ),
            if (b.cancellationReason?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'เหตุผลยกเลิก: ${b.cancellationReason}',
                  style: const TextStyle(fontSize: 12.5, color: Colors.red),
                ),
              ),
            if (b.isPending || b.isConfirmed || reviewable) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (b.isPending)
                    TextButton.icon(
                      onPressed: () => _changeSlot(b),
                      icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                      label: const Text('เปลี่ยนเวลา'),
                    ),
                  if (b.isPending || b.isConfirmed)
                    TextButton.icon(
                      onPressed: () => _cancel(b),
                      icon: const Icon(
                        Icons.cancel_outlined,
                        size: 16,
                        color: Colors.red,
                      ),
                      label: const Text(
                        'ยกเลิก',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  if (reviewable)
                    FilledButton.tonalIcon(
                      onPressed: () => _writeReview(b),
                      icon: const Icon(Icons.rate_review_outlined, size: 16),
                      label: const Text('เขียนรีวิว'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _statusChip(VenueBookingStatus status) {
    final (label, color) = switch (status) {
      VenueBookingStatus.pending => ('รออนุมัติ', Colors.orange),
      VenueBookingStatus.confirmed => ('ยืนยันแล้ว', Colors.green),
      VenueBookingStatus.cancelled => ('ยกเลิก', Colors.red),
      VenueBookingStatus.rejected => ('ปฏิเสธ', Colors.red),
      VenueBookingStatus.expired => ('หมดอายุ', Colors.grey),
      VenueBookingStatus.completed => ('เสร็จสิ้น', AppColors.primaryDark),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  static String _unitLabel(String? unit) => switch (unit) {
    'session' => 'รอบ',
    'match' => 'แมตช์',
    'day' => 'วัน',
    _ => 'ชม.',
  };

  static String _fmtRange(DateTime start, DateTime end) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${start.day}/${start.month}/${start.year + 543} '
        '${two(start.hour)}:${two(start.minute)}'
        '–${two(end.hour)}:${two(end.minute)}';
  }

  static String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('TERMS_VERSION_CHANGED')) {
      return 'เงื่อนไขสนามเปลี่ยนแล้ว กรุณาอ่านและยอมรับเวอร์ชันใหม่';
    }
    if (raw.contains('SLOT_TAKEN') || raw.contains('OVERLAP')) {
      return 'ช่วงเวลานี้ถูกจองแล้ว กรุณาเลือกเวลาอื่น';
    }
    if (raw.contains('CUTOFF_PASSED')) {
      return 'เลยเวลายกเลิกฟรีแล้ว กรุณาติดต่อสนามโดยตรง';
    }
    if (raw.contains('REVIEW_NOT_ALLOWED')) {
      return 'ยังรีวิวไม่ได้ — รีวิวได้หลังการจองเสร็จสิ้น';
    }
    if (raw.contains('UNAUTHORIZED')) return 'กรุณาเข้าสู่ระบบใหม่';
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
}
