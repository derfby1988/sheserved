import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';

import '../../application/book_court_booking_service.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../widgets/court_owner_booking_manager.dart';

/// Owner/manager booking queue for one venue: pending approvals plus
/// upcoming confirmed bookings and history.
class CourtOwnerBookingsPage extends StatefulWidget {
  final BookCourtRepository repo;
  final VenueSummary venue;

  const CourtOwnerBookingsPage({
    super.key,
    required this.repo,
    required this.venue,
  });

  @override
  State<CourtOwnerBookingsPage> createState() =>
      _CourtOwnerBookingsPageState();
}

class _CourtOwnerBookingsPageState extends State<CourtOwnerBookingsPage> {
  List<VenueBooking> _bookings = [];
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
      final bookings = await widget.repo.listVenueBookingsForManager(
        userId,
        widget.venue.id,
      );
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(VenueBooking b) async {
    try {
      final result = await _booking.decideBooking(
        userId: _userId,
        booking: b,
        approve: true,
      );
      if (result == 'conflict') {
        _toast('ช่วงเวลานี้มีการจองยืนยันแล้ว — คำขอยังคงรออนุมัติ');
      } else {
        _toast('อนุมัติการจองแล้ว');
      }
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _reject(VenueBooking b, String reason) async {
    try {
      await _booking.decideBooking(
        userId: _userId,
        booking: b,
        approve: false,
        reason: reason,
      );
      _toast('ปฏิเสธคำขอแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _cancelConfirmed(VenueBooking b, String reason) async {
    try {
      await _booking.cancelBooking(
        userId: _userId,
        booking: b,
        reason: reason,
      );
      _toast('ยกเลิกการจองแล้ว');
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
    final pending = _bookings.where((b) => b.isPending).toList();
    final confirmed = _bookings.where((b) => b.isConfirmed).toList();
    final history = _bookings
        .where((b) => !b.isPending && !b.isConfirmed)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('การจอง — ${widget.venue.name}'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  _sectionHeader('รออนุมัติ (${pending.length})'),
                  if (pending.isEmpty)
                    _empty('ไม่มีคำขอรออนุมัติ')
                  else
                    for (final b in pending)
                      CourtOwnerBookingManager(
                        booking: b,
                        onApprove: () => _approve(b),
                        onReject: (reason) => _reject(b, reason),
                      ),
                  _sectionHeader('ยืนยันแล้ว (${confirmed.length})'),
                  if (confirmed.isEmpty)
                    _empty('ไม่มีการจองที่ยืนยัน')
                  else
                    for (final b in confirmed)
                      CourtOwnerBookingManager(
                        booking: b,
                        onCancel: (reason) => _cancelConfirmed(b, reason),
                      ),
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
                              : 'ประวัติ (${history.length})',
                        ),
                      ),
                    ),
                    if (_showHistory)
                      for (final b in history)
                        CourtOwnerBookingManager(booking: b),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
    ),
  );

  static String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('SLOT_TAKEN') || raw.contains('OVERLAP')) {
      return 'ช่วงเวลานี้ถูกจองแล้ว';
    }
    if (raw.contains('UNAUTHORIZED') || raw.contains('NOT_VENUE_MANAGER')) {
      return 'คุณไม่มีสิทธิ์จัดการสนามนี้';
    }
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
}
