import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/services/websocket_service.dart';
import 'package:sheserved/shared/widgets/glass/glass_text_prompt_dialog.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../application/court_owner_service.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../widgets/court_owner_register_sheet.dart';
import '../widgets/court_owner_venue_card.dart';
import 'court_owner_bookings_page.dart';
import 'court_owner_venue_manage_page.dart';

/// Owner dashboard: owner profile status, managed venues, and the entry
/// points to register as an owner, create a venue, add courts, and manage
/// booking queues.
class CourtOwnerDashboard extends StatefulWidget {
  final BookCourtRepository repo;

  const CourtOwnerDashboard({super.key, required this.repo});

  @override
  State<CourtOwnerDashboard> createState() => _CourtOwnerDashboardState();
}

class _CourtOwnerDashboardState extends State<CourtOwnerDashboard> {
  VenueOwnerProfile? _ownerProfile;
  List<VenueSummary> _venues = [];
  Map<String, int> _pendingCounts = {};
  bool _loading = true;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;

  String? get _userId => AuthService.instance.currentUser?.id;

  late final CourtOwnerService _ownerService = CourtOwnerService(
    submitApplication: widget.repo.submitOwnerApplication,
    getMyOwnerProfile: widget.repo.getMyOwnerProfile,
    listMyVenues: widget.repo.listMyVenues,
    upsertVenue: widget.repo.upsertVenue,
    listApplications: widget.repo.listOwnerApplications,
    reviewApplication: widget.repo.reviewOwnerApplication,
  );

  @override
  void initState() {
    super.initState();
    _load();
    // Same contract as the group-join flow: a fresh venue_booking
    // notification means a manager-visible queue changed — refresh the
    // pending badges without waiting for a manual pull.
    _notificationSub = WebSocketService().applicationNotificationStream
        .listen((data) {
          if (data['category']?.toString() == 'venue_booking') _load();
        });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      // listMyVenues already scopes to venues the user manages — including
      // assigned venue managers who have no owner profile of their own.
      final results = await Future.wait([
        widget.repo.getMyOwnerProfile(userId),
        widget.repo.listMyVenues(userId),
      ]);
      final venues = results[1] as List<VenueSummary>;
      final pendingCounts = await _loadPendingCounts(userId, venues);
      if (!mounted) return;
      setState(() {
        _ownerProfile = results[0] as VenueOwnerProfile?;
        _venues = venues;
        _pendingCounts = pendingCounts;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pending approval requests per managed venue — the same "คำขอรออนุมัติ"
  /// surface the group sheet shows managers, so pending bookings stay
  /// discoverable even when realtime delivery is down.
  Future<Map<String, int>> _loadPendingCounts(
    String userId,
    List<VenueSummary> venues,
  ) async {
    final counts = <String, int>{};
    await Future.wait(
      venues.map((venue) async {
        try {
          final pending = await widget.repo.listVenueBookingsForManager(
            userId,
            venue.id,
            statuses: const ['pending'],
          );
          counts[venue.id] = pending.length;
        } catch (_) {
          counts[venue.id] = 0;
        }
      }),
    );
    return counts;
  }

  Future<void> _applyAsOwner() async {
    final userId = _userId;
    if (userId == null) return;
    final draft = await CourtOwnerRegisterSheet.show(context);
    if (draft == null) return;
    try {
      await _ownerService.applyAsOwner(
        userId: userId,
        businessName: draft.businessName ?? draft.legalName,
        contactName: draft.legalName,
        contactPhone: draft.contactPhone,
        contactEmail: draft.contactEmail,
      );
      _toast('ส่งคำขอแล้ว รอทีมงานตรวจสอบ');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _addVenue() async {
    final userId = _userId;
    if (userId == null) return;
    final name = await _askVenueName();
    if (name == null) return;
    try {
      await _ownerService.upsertVenue(userId: userId, name: name);
      _toast('สร้างสนามแล้ว — ตั้งค่าให้ครบแล้วกดส่งตรวจสอบ');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<String?> _askVenueName() {
    return GlassTextPromptDialog.show(
      context,
      title: 'สร้างสนามใหม่',
      hint: 'ชื่อสนาม/สถานที่',
      label: 'ชื่อสนาม/สถานที่',
      confirmLabel: 'สร้าง',
      accentColor: AppColors.primaryDark,
      maxLength: 120,
      maxLines: 1,
    );
  }

  void _openManage(VenueSummary venue) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourtOwnerVenueManagePage(
          repo: widget.repo,
          venue: venue,
          ownerApproved: _ownerProfile?.status == VenueOwnerStatus.approved,
        ),
      ),
    ).then((_) => _load());
  }

  void _openBookings(VenueSummary venue) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourtOwnerBookingsPage(repo: widget.repo, venue: venue),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final userId = _userId;
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor,
      appBar: AppBar(
        title: const Text(
          'จัดการสนามของฉัน',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        backgroundColor: NeumorphicTheme.baseColor,
        elevation: 0,
        foregroundColor: NeumorphicTheme.textPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : userId == null
          ? const Center(child: Text('กรุณาเข้าสู่ระบบ'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  _buildOwnerStatusCard(),
                  const SizedBox(height: 8),
                  // Venues the user manages are always listed — assigned
                  // managers see their scope without owning a profile, but
                  // only an approved owner may create a new venue.
                  if (_venues.isNotEmpty ||
                      _ownerProfile?.status == VenueOwnerStatus.approved) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'สนามที่จัดการ (${_venues.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: NeumorphicTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (_ownerProfile?.status ==
                              VenueOwnerStatus.approved)
                            NeumorphicPillButton(
                              onPressed: _addVenue,
                              icon: Icons.add_rounded,
                              text: 'เพิ่มสนาม',
                              height: 34,
                              fontSize: 13,
                              iconSize: 16,
                              depth: 3,
                              blur: 6,
                            ),
                        ],
                      ),
                    ),
                    if (_venues.isEmpty)
                      NeumorphicContainer(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 24,
                        ),
                        borderRadius: 18,
                        depth: 4,
                        blur: 8,
                        child: Column(
                          children: [
                            const NeumorphicInsetBox(
                              width: 56,
                              height: 56,
                              borderRadius: 28,
                              padding: EdgeInsets.zero,
                              child: Icon(
                                Icons.stadium_outlined,
                                size: 26,
                                color: NeumorphicTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'ยังไม่มีสนาม — สร้างสนามแรกของคุณ',
                              style: TextStyle(
                                fontSize: 13,
                                color: NeumorphicTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final venue in _venues)
                        CourtOwnerVenueCard(
                          venue: venue,
                          pendingCount: _pendingCounts[venue.id] ?? 0,
                          onManage: () => _openManage(venue),
                          onViewBookings: () => _openBookings(venue),
                        ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildOwnerStatusCard() {
    final status = _ownerProfile?.status;
    final submitted = _formatDate(
      _ownerProfile?.submittedAt ?? _ownerProfile?.createdAt,
    );
    final reviewed = _formatDate(_ownerProfile?.reviewedAt);
    final submittedLine =
        submitted == null ? null : 'ส่งคำขอเมื่อ $submitted';
    final approvedSubtitle = [
      if (submitted != null) 'ส่งคำขอ $submitted',
      if (reviewed != null) 'อนุมัติ $reviewed',
    ].join('\n');
    return NeumorphicContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      depth: 4,
      blur: 8,
      child: switch (status) {
          VenueOwnerStatus.approved => _statusTile(
            icon: Icons.verified_rounded,
            color: Colors.green.shade700,
            title: 'คุณเป็นเจ้าของสนามที่อนุมัติแล้ว',
            subtitle: approvedSubtitle,
          ),
          VenueOwnerStatus.pending => _statusTile(
            icon: Icons.hourglass_top_rounded,
            color: Colors.orange.shade800,
            title: 'คำขอเป็นเจ้าของสนามกำลังรอตรวจสอบ',
            subtitle: submittedLine,
          ),
          VenueOwnerStatus.rejected || VenueOwnerStatus.suspended => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusTile(
                icon: Icons.block_rounded,
                color: Colors.red,
                title: status == VenueOwnerStatus.rejected
                    ? 'คำขอไม่ผ่านการตรวจสอบ'
                    : 'บัญชีเจ้าของสนามถูกระงับ',
                subtitle: submittedLine,
              ),
              if (_ownerProfile?.rejectionReason?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 48),
                  child: Text(
                    _ownerProfile!.rejectionReason!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                ),
              if (status == VenueOwnerStatus.rejected)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: NeumorphicPillButton(
                    onPressed: _applyAsOwner,
                    icon: Icons.refresh_rounded,
                    text: 'แก้ไขและส่งคำขอใหม่',
                    height: 40,
                    fontSize: 13.5,
                    depth: 4,
                    blur: 8,
                  ),
                ),
              if (status == VenueOwnerStatus.suspended)
                const Padding(
                  padding: EdgeInsets.only(top: 8, left: 48),
                  child: Text(
                    'หากต้องการอุทธรณ์ กรุณาติดต่อทีมงาน Sheserved',
                    style: TextStyle(
                      fontSize: 12,
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusTile(
                icon: Icons.stadium_outlined,
                color: NeumorphicTheme.primaryBlue,
                title:
                    'มีสนามกีฬา? ลงทะเบียนเป็นเจ้าของสนามเพื่อเปิดรับการจอง',
              ),
              const SizedBox(height: 12),
              NeumorphicVerifyButton(
                onPressed: _applyAsOwner,
                text: 'ลงทะเบียนเจ้าของสนาม',
                height: 46,
                fitTextToWidth: true,
              ),
            ],
          ),
        },
    );
  }

  static String? _formatDate(DateTime? d) =>
      d == null ? null : formatThaiBuddhistDateTime(d.toLocal());

  Widget _statusTile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
  }) {
    return Row(
      children: [
        NeumorphicContainer(
          width: 38,
          height: 38,
          shape: BoxShape.circle,
          depth: 3,
          blur: 6,
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: NeumorphicTheme.textPrimary,
                ),
              ),
              if (subtitle?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('UNAUTHORIZED')) return 'กรุณาเข้าสู่ระบบใหม่';
    if (raw.contains('OWNER_NOT_APPROVED')) {
      return 'บัญชีเจ้าของสนามยังไม่ได้รับการอนุมัติ';
    }
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
}
