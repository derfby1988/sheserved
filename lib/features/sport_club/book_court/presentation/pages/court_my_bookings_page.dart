import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../application/book_court_booking_service.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../../domain/venue_local_time.dart';
import '../widgets/court_booking_action_dialogs.dart';
import '../widgets/court_booking_dialog.dart';
import '../widgets/court_review_sheet.dart';
import '../widgets/court_usage_terms_dialog.dart';

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
  List<VenueReviewCategory> _categoryCatalog = const [];
  bool _loading = true;
  // 0 = การจอง, 1 = ถูกปฏิเสธ/หมดอายุ, 2 = ยกเลิก, 3 = เสร็จสิ้น
  int _tab = 0;

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
        widget.repo.listReviewCategoryCatalog(),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = results[0] as List<VenueBooking>;
        _reviewedBookingIds = results[1] as Set<String>;
        _tagCatalog = results[2] as List<VenueReviewTag>;
        _categoryCatalog = results[3] as List<VenueReviewCategory>;
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
    final slots = await CourtBookingDialog.show(
      context,
      court: court,
      venueName: b.venueName ?? '',
      timezone: b.timezone,
      loadAvailability: widget.repo.getCourtAvailability,
      quotePrice: widget.repo.quoteCourtPrice,
      allowDisjoint: false,
      initialDate: VenueLocalTime.dateOfInstant(b.startsAt, b.timezone),
    );
    if (slots == null || slots.length != 1 || !mounted) return;
    final slot = slots.single;
    try {
      try {
        await _booking.movePendingSlot(
          userId: _userId,
          booking: b,
          startsAt: slot.start,
          endsAt: slot.end,
          termsVersion: b.termsVersion,
          priceScheduleVersion: slot.priceQuote.priceScheduleVersion,
        );
      } catch (error) {
        if (!error.toString().contains('TERMS_VERSION_CHANGED')) rethrow;
        final terms = await widget.repo.getActiveVenueTerms(b.venueId);
        if (!mounted) return;
        final accepted = await CourtUsageTermsDialog.show(
          context,
          terms: terms,
          venueName: b.venueName ?? '',
          acceptLabel: 'ยอมรับและเปลี่ยนเวลา',
        );
        if (accepted == null || !mounted) return;
        await _booking.movePendingSlot(
          userId: _userId,
          booking: b,
          startsAt: slot.start,
          endsAt: slot.end,
          termsVersion: accepted.version,
          priceScheduleVersion: slot.priceQuote.priceScheduleVersion,
        );
      }
      _toast('เปลี่ยนเวลาแล้ว รอเจ้าของอนุมัติ');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  /// Opens the review sheet and submits through the v2 RPC. When a
  /// submit fails transiently the sheet re-opens with the same draft so
  /// the reviewer loses nothing; one review per booking is enforced
  /// server-side, so retries can never create a duplicate.
  Future<void> _writeReview(VenueBooking b) async {
    CourtReviewDraft? draft;
    while (true) {
      if (!mounted) return;
      draft = await CourtReviewSheet.show(
        context,
        venueName: b.venueName ?? '',
        tagCatalog: _tagCatalog,
        categories: _categoryCatalog,
        initial: draft,
      );
      if (draft == null || !mounted) return;
      try {
        await widget.repo.submitReview(
          userId: _userId!,
          bookingId: b.id,
          rating10: draft.rating10,
          categoryScores: draft.categoryScores,
          comment: draft.comment,
          tagIds: draft.tagIds.toList(),
          customTags: draft.customTags,
        );
        _toast('ขอบคุณสำหรับรีวิว');
        await _load();
        return;
      } catch (e) {
        _toast(_mapError(e));
        if (_isFinalReviewError(e)) {
          await _load();
          return;
        }
      }
    }
  }

  /// Errors a retry cannot fix: eligibility and validation failures the
  /// form already guards against or the server will keep rejecting.
  static bool _isFinalReviewError(Object e) {
    final raw = e.toString();
    const codes = [
      'ALREADY_REVIEWED',
      'BOOKING_NOT_COMPLETED',
      'BOOKING_NOT_FOUND',
      'SELF_REVIEW_NOT_ALLOWED',
      'MISSING_CATEGORY_SCORES',
      'INVALID_CATEGORY',
      'INVALID_RATING',
      'COMMENT_TOO_LONG',
      'TOO_MANY_TAGS',
      'INVALID_TAG',
    ];
    return codes.any(raw.contains);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Active appointments: the nearest one leads.
    final now = DateTime.now();
    final active =
        _bookings
            .where((b) => b.isPending || b.isConfirmed)
            .toList()
          ..sort((a, b) {
            final aLive = a.endsAt.isAfter(now);
            final bLive = b.endsAt.isAfter(now);
            if (aLive != bLive) return aLive ? -1 : 1;
            return aLive
                ? a.startsAt.compareTo(b.startsAt)
                : b.startsAt.compareTo(a.startsAt);
          });
    // Rejections stay ahead of expired requests; rejected bookings sort by
    // decision time, and expired requests by their scheduled start time.
    final rejectedOrExpired =
        _bookings
            .where(
              (b) =>
                  b.status == VenueBookingStatus.rejected ||
                  b.status == VenueBookingStatus.expired,
            )
            .toList()
          ..sort((a, b) {
            final aRejected = a.status == VenueBookingStatus.rejected;
            final bRejected = b.status == VenueBookingStatus.rejected;
            if (aRejected != bRejected) return aRejected ? -1 : 1;
            return aRejected
                ? (b.decidedAt ?? b.createdAt ?? b.startsAt).compareTo(
                    a.decidedAt ?? a.createdAt ?? a.startsAt,
                  )
                : b.startsAt.compareTo(a.startsAt);
          });
    final cancelled = _bookings
        .where((b) => b.status == VenueBookingStatus.cancelled)
        .toList();
    final completed = _bookings
        .where((b) => b.isCompleted)
        .toList()
      ..sort((a, b) => b.endsAt.compareTo(a.endsAt));

    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor,
      appBar: AppBar(
        title: const Text(
          'การจองสนามของฉัน',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        backgroundColor: NeumorphicTheme.baseColor,
        elevation: 0,
        foregroundColor: NeumorphicTheme.textPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _userId == null
          ? const Center(
              child: Text(
                'กรุณาเข้าสู่ระบบเพื่อดูการจอง',
                style: TextStyle(color: NeumorphicTheme.textSecondary),
              ),
            )
          : Column(
              children: [
                _tabBar(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: switch (_tab) {
                      1 => _statusTab(
                        rejectedOrExpired,
                        'ไม่มีรายการที่ถูกปฏิเสธหรือหมดอายุ',
                        Icons.block_outlined,
                      ),
                      2 => _statusTab(
                        cancelled,
                        'ไม่มีรายการที่ยกเลิก',
                        Icons.cancel_outlined,
                      ),
                      3 => _statusTab(
                        completed,
                        'ไม่มีรายการที่เสร็จสิ้น',
                        Icons.event_available_rounded,
                      ),
                      _ => _bookingsTab(active),
                    },
                  ),
                ),
              ],
            ),
    );
  }

  /// Segmented tab bar — an inset track with a raised pill on the selected
  /// tab, same raised/sunken language as the sheet chips. Tab colours follow
  /// the status chips so the danger statuses stay red.
  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: NeumorphicInsetBox(
        height: 44,
        borderRadius: 22,
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _tabItem(0, 'การจอง', AppColors.primaryDark),
            _tabItem(1, 'ถูกปฏิเสธ', Colors.red),
            _tabItem(2, 'ยกเลิก', Colors.red),
            _tabItem(3, 'เสร็จสิ้น', AppColors.primaryDark),
          ],
        ),
      ),
    );
  }

  Widget _tabItem(int index, String label, Color activeColor) {
    final selected = _tab == index;
    final text = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? activeColor : NeumorphicTheme.textSecondary,
        ),
      ),
    );
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _tab = index),
          borderRadius: BorderRadius.circular(18),
          child: selected
              ? NeumorphicContainer(
                  height: 36,
                  borderRadius: 18,
                  depth: 3,
                  blur: 6,
                  child: Center(child: text),
                )
              : Center(child: text),
        ),
      ),
    );
  }

  Widget _emptyCard(IconData icon, String label) {
    return NeumorphicContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      borderRadius: 18,
      depth: 4,
      blur: 8,
      child: Column(
        children: [
          NeumorphicInsetBox(
            width: 56,
            height: 56,
            borderRadius: 28,
            padding: EdgeInsets.zero,
            child: Icon(
              icon,
              size: 26,
              color: NeumorphicTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: NeumorphicTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookingsTab(List<VenueBooking> active) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (active.isEmpty)
          _emptyCard(Icons.event_busy_rounded, 'ยังไม่มีการจอง')
        else
          for (final b in active) _buildBookingCard(b),
      ],
    );
  }

  /// One list per status tab — a shared empty card when there is nothing.
  Widget _statusTab(
    List<VenueBooking> bookings,
    String emptyLabel,
    IconData emptyIcon,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (bookings.isEmpty)
          _emptyCard(emptyIcon, emptyLabel)
        else
          for (final b in bookings) _buildBookingCard(b),
      ],
    );
  }

  Widget _buildBookingCard(VenueBooking b) {
    final reviewable = b.isCompleted && !_reviewedBookingIds.contains(b.id);
    return NeumorphicContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      depth: 4,
      blur: 8,
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
                    color: NeumorphicTheme.textPrimary,
                  ),
                ),
              ),
              _statusChip(b.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${b.unitLabel ?? 'สนาม'} ${b.courtName ?? ''}',
            style: const TextStyle(
              fontSize: 13,
              color: NeumorphicTheme.textSecondary,
            ),
          ),
          Text(
            _fmtRange(b),
            style: const TextStyle(
              fontSize: 13,
              color: NeumorphicTheme.textSecondary,
            ),
          ),
          if (b.priceTotal != null)
            Text(
              'ราคารวม ${b.priceTotal!.toStringAsFixed(2)} บาท',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: NeumorphicTheme.textPrimary,
              ),
            )
          else if (b.priceAmount != null)
            Text(
              '${b.priceAmount!.toStringAsFixed(0)} บาท/${_unitLabel(b.pricingUnit)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: NeumorphicTheme.textPrimary,
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
          if (b.status == VenueBookingStatus.expired)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'เหตุผลที่หมดอายุ: อนุมัติไม่ทัน',
                style: TextStyle(fontSize: 12.5, color: Colors.red),
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
              runSpacing: 8,
              children: [
                if (b.isPending)
                  _actionPill(
                    onPressed: () => _changeSlot(b),
                    icon: Icons.edit_calendar_rounded,
                    text: 'เปลี่ยนเวลา',
                    color: NeumorphicTheme.textSecondary,
                  ),
                if (b.isPending || b.isConfirmed)
                  _actionPill(
                    onPressed: () => _cancel(b),
                    icon: Icons.cancel_outlined,
                    text: 'ยกเลิก',
                    color: Colors.red,
                  ),
                if (reviewable)
                  _actionPill(
                    onPressed: () => _writeReview(b),
                    icon: Icons.rate_review_outlined,
                    text: 'เขียนรีวิว',
                    color: AppColors.primaryDark,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Compact raised pill for card actions — the same shape and shadow scale
  /// as [NeumorphicPillButton] (height 34, depth 3) but sized to its content
  /// and tintable, so the destructive cancel keeps its red cue and pills can
  /// sit inside a [Wrap]/[Center] without stretching full-width.
  Widget _actionPill({
    required IconData icon,
    required String text,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(17),
        child: NeumorphicContainer(
          height: 34,
          borderRadius: 17,
          depth: 3,
          blur: 6,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    text,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
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

  /// Booking instants are stored UTC — render them in the venue's timezone
  /// so the slot matches what the booker picked.
  static String _fmtRange(VenueBooking booking) {
    String two(int n) => n.toString().padLeft(2, '0');
    final start = VenueLocalTime.wallTimeOfInstant(
      booking.startsAt,
      booking.timezone,
    );
    final end = VenueLocalTime.wallTimeOfInstant(
      booking.endsAt,
      booking.timezone,
    );
    return '${start.day}/${start.month}/${start.year + 543} '
        '${two(start.hour)}:${two(start.minute)}'
        '–${two(end.hour)}:${two(end.minute)}';
  }

  static String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('PLATFORM_TERMS_NOT_CONFIGURED')) {
      return 'สนามยังไม่มีเงื่อนไขมาตรฐาน กรุณาติดต่อสนามหรือกลับมาลองใหม่ภายหลัง';
    }
    if (raw.contains('TERMS_VERSION_CHANGED')) {
      return 'เงื่อนไขสนามเปลี่ยนแล้ว กรุณาอ่านและยอมรับเวอร์ชันใหม่';
    }
    if (raw.contains('PRICE_CHANGED')) {
      return 'ราคาสนามเปลี่ยนแล้ว กรุณาเลือกเวลาใหม่และตรวจสอบราคา';
    }
    if (raw.contains('PRICE_VERSION_REQUIRED')) {
      return 'กรุณาอัปเดตแอปก่อนเปลี่ยนเวลาจองสนามนี้';
    }
    if (raw.contains('PRICE_NOT_CONFIGURED')) {
      return 'สนามยังไม่ได้กำหนดราคาในช่วงเวลานี้';
    }
    if (raw.contains('SLOT_TAKEN') || raw.contains('OVERLAP')) {
      return 'ช่วงเวลานี้ถูกจองแล้ว กรุณาเลือกเวลาอื่น';
    }
    if (raw.contains('CUTOFF_PASSED')) {
      return 'เลยเวลายกเลิกฟรีแล้ว กรุณาติดต่อสนามโดยตรง';
    }
    if (raw.contains('BOOKING_NOT_COMPLETED') ||
        raw.contains('REVIEW_NOT_ALLOWED')) {
      return 'ยังรีวิวไม่ได้ — รีวิวได้หลังการจองเสร็จสิ้น';
    }
    if (raw.contains('BOOKING_NOT_FOUND')) return 'ไม่พบการจองนี้แล้ว';
    if (raw.contains('ALREADY_REVIEWED')) return 'รีวิวการจองนี้ไปแล้ว';
    if (raw.contains('SELF_REVIEW_NOT_ALLOWED')) {
      return 'ไม่สามารถรีวิวสนามของตนเองได้';
    }
    if (raw.contains('TOO_MANY_TAGS')) {
      return 'เลือกแท็กรวมได้ไม่เกิน 5 รายการ';
    }
    if (raw.contains('COMMENT_TOO_LONG')) {
      return 'ความคิดเห็นยาวเกิน 500 ตัวอักษร';
    }
    if (raw.contains('MISSING_CATEGORY_SCORES') ||
        raw.contains('INVALID_CATEGORY') ||
        raw.contains('INVALID_RATING') ||
        raw.contains('INVALID_TAG')) {
      return 'กรุณาตรวจคะแนนและแท็กแล้วลองใหม่';
    }
    if (raw.contains('UNAUTHORIZED')) return 'กรุณาเข้าสู่ระบบใหม่';
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
}
