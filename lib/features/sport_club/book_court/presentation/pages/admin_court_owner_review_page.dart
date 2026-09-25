import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';

import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';

/// Admin review page for venue owner applications and pending venues.
///
/// Both lists are loaded through admin RPCs (`list_sports_venue_owner_
/// applications`, `list_sports_venues_for_review`) that validate the caller
/// is an admin server-side, so a non-admin sees an empty state.
class AdminCourtOwnerReviewPage extends StatelessWidget {
  final BookCourtRepository repo;

  const AdminCourtOwnerReviewPage({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ตรวจสอบเจ้าของสนาม'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: AdminCourtOwnerReviewPanel(repo: repo),
    );
  }
}

/// Body-only review surface — same data and actions as the standalone page
/// but without its own Scaffold/AppBar, so it can be embedded as a tab in
/// the "จัดการกีฬา" admin page.
class AdminCourtOwnerReviewPanel extends StatefulWidget {
  final BookCourtRepository repo;

  const AdminCourtOwnerReviewPanel({super.key, required this.repo});

  @override
  State<AdminCourtOwnerReviewPanel> createState() =>
      _AdminCourtOwnerReviewPanelState();
}

class _AdminCourtOwnerReviewPanelState
    extends State<AdminCourtOwnerReviewPanel> {
  List<VenueOwnerProfile> _applications = [];
  List<VenueSummary> _venues = [];
  bool _loading = true;

  /// Lazily loaded readiness details per venue id.
  final Map<String, Map<String, dynamic>> _venueDetails = {};
  final Set<String> _detailLoading = {};
  final Set<String> _detailErrors = {};

  String? get _adminId => AuthService.instance.currentUser?.id;

  static const _missingLabels = {
    'owner_not_approved': 'บัญชีเจ้าของยังไม่อนุมัติ',
    'name': 'ชื่อสนาม',
    'province': 'จังหวัด',
    'district': 'อำเภอ/เขต',
    'address': 'ที่อยู่',
    'location': 'พิกัดละติจูด/ลองจิจูด',
    'timezone': 'เขตเวลา',
    'sports': 'กีฬาของสนาม',
    'hours': 'เวลาเปิด–ปิดครบ 7 วัน',
    'amenities': 'ยืนยันสิ่งอำนวยความสะดวก',
    'terms': 'เลือกเงื่อนไขการใช้สนาม',
    'courts': 'คอร์ทที่เปิดใช้งาน',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final adminId = _adminId;
    if (adminId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.repo.listOwnerApplications(adminId),
        widget.repo.listVenuesForReview(adminId),
      ]);
      if (!mounted) return;
      setState(() {
        _applications = results[0] as List<VenueOwnerProfile>;
        _venues = results[1] as List<VenueSummary>;
        _venueDetails.clear();
        _detailErrors.clear();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reviewApplication(VenueOwnerProfile app, bool approve) async {
    final adminId = _adminId;
    if (adminId == null) return;
    final reason = approve ? null : await _askReason('เหตุผลที่ไม่อนุมัติ');
    if (!approve && reason == null) return;
    try {
      await widget.repo.reviewOwnerApplication(
        adminId,
        app.id,
        approve ? 'approved' : 'rejected',
        reason: reason,
      );
      _toast(approve ? 'อนุมัติเจ้าของสนามแล้ว' : 'ปฏิเสธคำขอแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _reviewVenue(VenueSummary venue, bool approve) async {
    final adminId = _adminId;
    if (adminId == null) return;
    final reason = approve ? null : await _askReason('เหตุผลที่ไม่อนุมัติ');
    if (!approve && reason == null) return;
    try {
      await widget.repo.reviewVenue(
        adminId,
        venue.id,
        approve ? 'approved' : 'rejected',
        reason: reason,
      );
      _toast(approve ? 'อนุมัติสนามแล้ว' : 'ปฏิเสธสนามแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _loadVenueDetail(String venueId) async {
    final adminId = _adminId;
    if (adminId == null || _detailLoading.contains(venueId)) return;
    setState(() {
      _detailLoading.add(venueId);
      _detailErrors.remove(venueId);
    });
    try {
      final detail = await widget.repo.getVenueAdminReviewDetail(
        adminId,
        venueId,
      );
      if (!mounted) return;
      setState(() => _venueDetails[venueId] = detail);
    } catch (_) {
      if (mounted) setState(() => _detailErrors.add(venueId));
    } finally {
      if (mounted) setState(() => _detailLoading.remove(venueId));
    }
  }

  Future<String?> _askReason(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          decoration: const InputDecoration(border: OutlineInputBorder()),
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
            child: const Text('ยืนยัน'),
          ),
        ],
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
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _sectionHeader('คำขอเป็นเจ้าของสนาม (${_applications.length})'),
                if (_applications.isEmpty)
                  _empty('ไม่มีคำขอรอตรวจสอบ')
                else
                  for (final app in _applications) _buildAppCard(app),
                _sectionHeader('สนามรออนุมัติ (${_venues.length})'),
                if (_venues.isEmpty)
                  _empty('ไม่มีสนามรออนุมัติ')
                else
                  for (final venue in _venues) _buildVenueCard(venue),
              ],
            ),
          );
  }

  Widget _buildAppCard(VenueOwnerProfile app) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              app.businessName.isNotEmpty ? app.businessName : app.contactName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'ผู้ติดต่อ: ${[app.contactName, if (app.contactPhone.isNotEmpty) app.contactPhone].join(' • ')}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            if (app.contactEmail?.isNotEmpty == true)
              Text(
                app.contactEmail!,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => _reviewApplication(app, false),
                  child: const Text(
                    'ปฏิเสธ',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                  ),
                  onPressed: () => _reviewApplication(app, true),
                  child: const Text('อนุมัติ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueCard(VenueSummary venue) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              venue.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              [venue.district, venue.province].whereType<String>().join(', '),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                dense: true,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text(
                  'ความพร้อมก่อนอนุมัติ',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onExpansionChanged: (expanded) {
                  if (expanded &&
                      !_venueDetails.containsKey(venue.id) &&
                      !_detailErrors.contains(venue.id)) {
                    _loadVenueDetail(venue.id);
                  }
                },
                children: [_buildVenueReadiness(venue)],
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => _reviewVenue(venue, false),
                  child: const Text(
                    'ปฏิเสธ',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                  ),
                  onPressed: () => _reviewVenue(venue, true),
                  child: const Text('อนุมัติ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueReadiness(VenueSummary venue) {
    if (_detailLoading.contains(venue.id)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_detailErrors.contains(venue.id)) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'โหลดความพร้อมไม่สำเร็จ',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),
          TextButton(
            onPressed: () => _loadVenueDetail(venue.id),
            child: const Text('ลองใหม่'),
          ),
        ],
      );
    }
    final detail = _venueDetails[venue.id];
    if (detail == null) return const SizedBox.shrink();

    final missing = (detail['setup_missing'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final business = detail['owner_business_name']?.toString() ?? '';
    final courtCount = (detail['court_count'] as num?)?.toInt() ?? 0;
    final activeCourts = (detail['active_court_count'] as num?)?.toInt() ?? 0;
    final hoursCount = (detail['hours_count'] as num?)?.toInt() ?? 0;
    final amenitiesConfirmed = detail['amenities_confirmed'] == true;
    final platformTerms = detail['uses_platform_terms'] == true;
    final termsVersion = (detail['terms_version'] as num?)?.toInt();
    final sportsCount = (detail['sports'] as List? ?? const []).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (business.isNotEmpty)
          Text(
            'เจ้าของ: $business',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        const SizedBox(height: 4),
        Text(
          'กีฬา $sportsCount · คอร์ท $activeCourts/$courtCount เปิดใช้งาน · '
          'เวลา $hoursCount/7 วัน · '
          'สิ่งอำนวยความสะดวก${amenitiesConfirmed ? 'ยืนยันแล้ว' : 'ยังไม่ยืนยัน'} · '
          'เงื่อนไข${termsVersion != null
              ? ' v$termsVersion'
              : platformTerms
              ? 'แพลตฟอร์ม'
              : '-'}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 4),
        if (missing.isEmpty)
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                'ตั้งค่าครบ พร้อมอนุมัติ',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          )
        else
          Text(
            'ยังขาด: ${missing.map((m) => _missingLabels[m] ?? m).join(', ')}',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
          ),
      ],
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
    if (raw.contains('UNAUTHORIZED') || raw.contains('NOT_ADMIN')) {
      return 'เฉพาะผู้ดูแลระบบเท่านั้น';
    }
    if (raw.contains('VENUE_NOT_READY')) {
      return 'สนามยังตั้งค่าไม่ครบ — ตรวจรายการความพร้อมก่อนอนุมัติ';
    }
    if (raw.contains('REASON_REQUIRED')) {
      return 'กรุณาระบุเหตุผล';
    }
    if (raw.contains('INVALID_STATUS')) {
      return 'สถานะสนามไม่อนุญาตให้ทำรายการนี้';
    }
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
}
