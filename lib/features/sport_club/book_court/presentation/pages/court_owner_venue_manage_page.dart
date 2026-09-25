import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../../domain/venue_setup_progress.dart';
import '../widgets/owner_court_editor_sheet.dart';
import '../widgets/venue_amenities_editor_sheet.dart';
import '../widgets/venue_hours_editor_sheet.dart';
import '../widgets/venue_sports_editor_sheet.dart';
import '../widgets/venue_terms_editor_sheet.dart';
import 'court_owner_bookings_page.dart';

/// Per-venue management page (Phase 21.7.11): setup progress checklist for
/// the 8-step owner flow plus the editors for sports / hours / amenities /
/// terms and the court list. Reached from the "จัดการ" button on
/// [CourtOwnerDashboard].
class CourtOwnerVenueManagePage extends StatefulWidget {
  final BookCourtRepository repo;
  final VenueSummary venue;
  final bool ownerApproved;

  const CourtOwnerVenueManagePage({
    super.key,
    required this.repo,
    required this.venue,
    this.ownerApproved = true,
  });

  @override
  State<CourtOwnerVenueManagePage> createState() =>
      _CourtOwnerVenueManagePageState();
}

class _CourtOwnerVenueManagePageState extends State<CourtOwnerVenueManagePage> {
  String? get _userId => AuthService.instance.currentUser?.id;

  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _sportCatalog = [];
  bool _loading = true;
  bool _saving = false;

  late final FitnessBuddiesRepository _buddiesRepo = FitnessBuddiesRepository(
    Supabase.instance.client,
  );

  VenueSummary get _venue => widget.venue;

  List<VenueCourt> get _courts => [
    for (final raw in (_detail?['courts'] as List? ?? const []))
      VenueCourt.fromJson(Map<String, dynamic>.from(raw as Map)),
  ];

  List<VenueOperatingHours> get _hours => [
    for (final raw in (_detail?['hours'] as List? ?? const []))
      VenueOperatingHours.fromJson(Map<String, dynamic>.from(raw as Map)),
  ];

  List<Map<String, dynamic>> get _venueSports => [
    for (final raw in (_detail?['sports'] as List? ?? const []))
      Map<String, dynamic>.from(raw as Map),
  ];

  Set<String> get _amenities => {
    for (final raw in (_detail?['amenities'] as List? ?? const []))
      raw.toString(),
  };

  Map<String, dynamic>? get _terms => _detail?['terms'] == null
      ? null
      : Map<String, dynamic>.from(_detail!['terms'] as Map);

  VenueStatus? get _venueStatus => _detail == null
      ? _venue.status
      : venueStatusFrom((_detail!['venue'] as Map?)?['status']?.toString());

  /// venue_sport id → display name for the court editor's sport dropdown.
  Map<String, String> get _sportChoices {
    final names = {
      for (final s in _sportCatalog) s['id']?.toString() ?? '': _sportName(s),
    };
    return {
      for (final vs in _venueSports)
        vs['sport_id']?.toString() ?? '':
            names[vs['sport_id']?.toString()] ??
            vs['sport_id']?.toString() ??
            '',
    };
  }

  String _sportName(Map<String, dynamic> sport) =>
      sport['name_th']?.toString() ??
      sport['name_en']?.toString() ??
      sport['id']?.toString() ??
      '';

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
        widget.repo.getMyVenueDetail(userId, _venue.id),
        _buddiesRepo.getApprovedSports(userId: userId),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = results[0] as Map<String, dynamic>;
        _sportCatalog = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<VenueSetupStep> get _steps => computeVenueSetupSteps(
    ownerApproved: widget.ownerApproved,
    venueCreated: true,
    hasSports: _venueSports.isNotEmpty,
    hasHours: _hours.isNotEmpty,
    hasAmenities: _amenities.isNotEmpty,
    hasTerms: _terms != null,
    hasCourts: _courts.isNotEmpty,
    venueStatus: _venueStatus,
  );

  Future<void> _run(VenueSetupStepId step) async {
    final userId = _userId;
    if (userId == null || _saving) return;
    switch (step) {
      case VenueSetupStepId.sports:
        final draft = await VenueSportsEditorSheet.show(
          context,
          sports: _sportCatalog,
          selectedUnits: {
            for (final vs in _venueSports)
              vs['sport_id']?.toString() ?? '':
                  vs['unit_label_override']?.toString() ?? '',
          },
        );
        if (draft == null) return;
        await _persist(
          () => widget.repo.setVenueSports(userId, _venue.id, draft),
          'บันทึกกีฬาของสนามแล้ว',
        );
      case VenueSetupStepId.hours:
        final draft = await VenueHoursEditorSheet.show(
          context,
          current: _hours,
        );
        if (draft == null) return;
        await _persist(
          () => widget.repo.setVenueOperatingHours(userId, _venue.id, draft),
          'บันทึกเวลาเปิด–ปิดแล้ว',
        );
      case VenueSetupStepId.amenities:
        final draft = await VenueAmenitiesEditorSheet.show(
          context,
          selected: _amenities,
        );
        if (draft == null) return;
        await _persist(
          () => widget.repo.setVenueAmenities(userId, _venue.id, draft),
          'บันทึกสิ่งอำนวยความสะดวกแล้ว',
        );
      case VenueSetupStepId.terms:
        final draft = await VenueTermsEditorSheet.show(
          context,
          currentText: _terms?['terms_text']?.toString(),
          currentCutoffMinutes: (_terms?['cancellation_cutoff_minutes'] as num?)
              ?.toInt(),
        );
        if (draft == null) return;
        await _persist(() async {
          final version = await widget.repo.publishVenueTerms(
            userId,
            _venue.id,
            draft.text,
            cancellationCutoffMinutes: draft.cutoffMinutes,
          );
          _toast('เผยแพร่เงื่อนไขเวอร์ชัน $version แล้ว');
        }, '');
      case VenueSetupStepId.courts:
        await _editCourt();
      default:
        break;
    }
  }

  Future<void> _editCourt([VenueCourt? court]) async {
    final userId = _userId;
    if (userId == null) return;
    if (_venueSports.isEmpty) {
      _toast('กรุณาตั้งค่ากีฬาของสนามก่อนเพิ่มคอร์ท');
      return;
    }
    final draft = await OwnerCourtEditorSheet.show(
      context,
      court: court,
      sportId: court?.sportId ?? _venueSports.first['sport_id'].toString(),
      sportChoices: _sportChoices,
    );
    if (draft == null) return;
    await _persist(
      () => widget.repo.upsertCourt(
        userId: userId,
        courtId: court?.id,
        venueId: _venue.id,
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
      ),
      court == null ? 'เพิ่มคอร์ทแล้ว' : 'บันทึกคอร์ทแล้ว',
    );
  }

  Future<void> _persist(Future<void> Function() action, String ok) async {
    setState(() => _saving = true);
    try {
      await action();
      if (ok.isNotEmpty) _toast(ok);
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openBookings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CourtOwnerBookingsPage(repo: widget.repo, venue: _venue),
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
    final steps = _steps;
    final doneCount = steps.where((s) => s.done).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_venue.name),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'การจอง',
            onPressed: _openBookings,
            icon: const Icon(Icons.event_note_rounded),
          ),
        ],
      ),
      body: _loading && _detail == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  _buildStatusCard(),
                  _buildChecklistCard(steps, doneCount),
                  _buildCourtsSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final status = _venueStatus;
    final (label, color) = switch (status) {
      VenueStatus.approved => ('เปิดรับการจองแล้ว', Colors.green.shade700),
      VenueStatus.pending => ('รอตรวจสอบ', Colors.orange.shade800),
      VenueStatus.rejected => ('ไม่ผ่านการตรวจสอบ', Colors.red.shade700),
      VenueStatus.suspended => ('ถูกระงับ', Colors.red.shade700),
      _ => ('ไม่ทราบสถานะ', Colors.grey.shade600),
    };
    final venueMap = (_detail?['venue'] as Map?) ?? const {};
    final reason =
        venueMap['rejection_reason']?.toString() ?? _venue.rejectionReason;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _venue.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      _venue.district,
                      _venue.province,
                    ].whereType<String>().join(', '),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (reason != null && reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        reason,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistCard(List<VenueSetupStep> steps, int doneCount) {
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
                    'ขั้นตอนการเปิดสนาม',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$doneCount/${steps.length}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: doneCount / steps.length,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < steps.length; i++)
              _buildStepRow(steps[i], i + 1),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(VenueSetupStep step, int order) {
    final enabled = step.done || step.actionable;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: step.actionable || step.done && _editable(step.id)
          ? () => _run(step.id)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          children: [
            _stepIcon(step, order),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                step.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: step.done ? FontWeight.w500 : FontWeight.w600,
                  color: enabled ? Colors.black87 : Colors.grey.shade500,
                ),
              ),
            ),
            if (step.id == VenueSetupStepId.venueApproved && !step.done)
              Icon(
                Icons.hourglass_top_rounded,
                size: 18,
                color: Colors.orange.shade700,
              )
            else if (enabled)
              Icon(
                step.done ? Icons.edit_outlined : Icons.chevron_right_rounded,
                size: 18,
                color: step.done ? Colors.grey.shade500 : AppColors.primaryDark,
              ),
          ],
        ),
      ),
    );
  }

  /// Steps the owner may reopen to adjust existing values.
  bool _editable(VenueSetupStepId id) => switch (id) {
    VenueSetupStepId.sports ||
    VenueSetupStepId.hours ||
    VenueSetupStepId.amenities ||
    VenueSetupStepId.terms => true,
    _ => false,
  };

  Widget _stepIcon(VenueSetupStep step, int order) {
    if (step.done) {
      return const Icon(
        Icons.check_circle_rounded,
        size: 20,
        color: Colors.green,
      );
    }
    final active = step.actionable;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.primaryDark : Colors.grey.shade300,
      ),
      child: Text(
        '$order',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildCourtsSection() {
    final courts = _courts;
    final canAdd = _venueSports.isNotEmpty;
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
                    'คอร์ท (${courts.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _saving || !canAdd ? null : () => _editCourt(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('เพิ่มคอร์ท'),
                ),
              ],
            ),
            if (!canAdd)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'ตั้งค่ากีฬาของสนามก่อนจึงจะเพิ่มคอร์ทได้',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ),
            if (courts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'ยังไม่มีคอร์ท',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              for (final court in courts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    court.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      _sportChoices[court.sportId] ?? '',
                      if (court.unitLabel != null) court.unitLabel!,
                      if (court.priceAmount != null)
                        '${court.priceAmount!.toStringAsFixed(0)} บาท/${court.pricingUnit}',
                      court.approvalMode == BookingApprovalMode.ownerApproval
                          ? 'รออนุมัติ'
                          : 'ยืนยันทันที',
                      if (!court.isActive) 'ปิดใช้งาน',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () => _editCourt(court),
                ),
          ],
        ),
      ),
    );
  }

  static String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('NOT_VENUE_MANAGER')) {
      return 'คุณไม่มีสิทธิ์จัดการสนามนี้';
    }
    if (raw.contains('SPORT_NOT_ON_VENUE')) {
      return 'กีฬานี้ยังไม่ได้ตั้งค่าในสนาม';
    }
    if (raw.contains('INVALID_TERMS')) {
      return 'กรุณากรอกเงื่อนไขการใช้สนาม';
    }
    if (raw.contains('INVALID_COURT')) {
      return 'กรุณากรอกชื่อคอร์ท';
    }
    return 'ทำรายการไม่สำเร็จ กรุณาลองใหม่';
  }
}
