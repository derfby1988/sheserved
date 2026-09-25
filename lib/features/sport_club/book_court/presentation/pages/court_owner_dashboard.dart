import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';

import '../../application/court_owner_service.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../widgets/court_owner_register_sheet.dart';
import '../widgets/court_owner_venue_card.dart';
import '../widgets/owner_court_editor_sheet.dart';
import 'court_owner_bookings_page.dart';

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
  bool _loading = true;

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
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final profile = await widget.repo.getMyOwnerProfile(userId);
      final venues = profile?.status == VenueOwnerStatus.approved
          ? await widget.repo.listMyVenues(userId)
          : <VenueSummary>[];
      if (!mounted) return;
      setState(() {
        _ownerProfile = profile;
        _venues = venues;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
      _toast('สร้างสนามแล้ว — เพิ่มคอร์ทและรอการอนุมัติ');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<String?> _askVenueName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('สร้างสนามใหม่'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'ชื่อสนาม/สถานที่',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(c, text);
            },
            child: const Text('สร้าง'),
          ),
        ],
      ),
    );
  }

  Future<void> _addCourt(VenueSummary venue) async {
    final userId = _userId;
    if (userId == null) return;
    // Court sport: use the venue's first sport when known; the editor can
    // only be opened once the venue has at least one sport configured.
    final sportId = venue.sportIds.isNotEmpty ? venue.sportIds.first : null;
    if (sportId == null) {
      _toast('กรุณาตั้งค่ากีฬาของสนามก่อนเพิ่มคอร์ท');
      return;
    }
    final draft = await OwnerCourtEditorSheet.show(context, sportId: sportId);
    if (draft == null) return;
    try {
      await widget.repo.upsertCourt(
        userId: userId,
        venueId: venue.id,
        sportId: draft['sport_id'] as String,
        name: draft['name'] as String,
        capacity: draft['capacity'] as int,
        priceAmount: draft['price_amount'] as double?,
        pricingUnit: draft['pricing_unit'] as String,
        courtType: draft['court_type'] as String?,
        indoor: draft['indoor'] as bool?,
        approvalMode: draft['approval_mode'] as String,
        unitLabel: (draft['unit_label'] as String?)?.trim().isEmpty == true
            ? null
            : draft['unit_label'] as String?,
      );
      _toast('เพิ่มสนามแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
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
      appBar: AppBar(
        title: const Text('จัดการสนามของฉัน'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
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
                  if (_ownerProfile?.status == VenueOwnerStatus.approved) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'สนามของฉัน (${_venues.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _addVenue,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('เพิ่มสนาม'),
                          ),
                        ],
                      ),
                    ),
                    if (_venues.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'ยังไม่มีสนาม — สร้างสนามแรกของคุณ',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    else
                      for (final venue in _venues)
                        CourtOwnerVenueCard(
                          venue: venue,
                          onManage: () => _addCourt(venue),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: switch (status) {
          VenueOwnerStatus.approved => Row(
            children: [
              Icon(Icons.verified_rounded, color: Colors.green.shade700),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'คุณเป็นเจ้าของสนามที่อนุมัติแล้ว',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          VenueOwnerStatus.pending => Row(
            children: [
              Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'คำขอเป็นเจ้าของสนามกำลังรอตรวจสอบ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          VenueOwnerStatus.rejected || VenueOwnerStatus.suspended => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.block_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status == VenueOwnerStatus.rejected
                          ? 'คำขอไม่ผ่านการตรวจสอบ'
                          : 'บัญชีเจ้าของสนามถูกระงับ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (_ownerProfile?.rejectionReason?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _ownerProfile!.rejectionReason!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
            ],
          ),
          _ => Row(
            children: [
              const Expanded(
                child: Text(
                  'มีสนามกีฬา? ลงทะเบียนเป็นเจ้าของสนามเพื่อเปิดรับการจอง',
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                ),
                onPressed: _applyAsOwner,
                child: const Text('ลงทะเบียน'),
              ),
            ],
          ),
        },
      ),
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
