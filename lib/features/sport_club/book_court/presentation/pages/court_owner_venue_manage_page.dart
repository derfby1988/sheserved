import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/consultation/presentation/pages/health_program_request_dashboard.dart'
    show dashboardRouteObserver;
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';
import 'package:sheserved/shared/widgets/tlz_app_top_bar.dart';
import 'package:sheserved/shared/widgets/tlz_drawer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../../domain/venue_setup_progress.dart';
import '../widgets/owner_court_editor_dialog.dart';
import '../widgets/venue_amenities_editor_dialog.dart';
import '../widgets/venue_hours_editor_dialog.dart';
import '../widgets/venue_profile_editor_sheet.dart';
import '../widgets/venue_setup_checklist_card.dart';
import '../widgets/venue_sports_editor_dialog.dart';
import '../widgets/venue_terms_editor_dialog.dart';
import 'court_owner_bookings_page.dart';

/// Per-venue management page (Phase 21.7.11): setup progress checklist for
/// the 8-step owner flow plus the editors for sports / hours / amenities /
/// terms / venue profile and the court list. Reached from the "จัดการ"
/// button on [CourtOwnerDashboard].
///
/// Review lifecycle: draft → (ส่งตรวจสอบ) → pending → approved/rejected;
/// suspended is terminal for self-serve resubmission. All status shown
/// here comes from `get_my_sports_venue_detail`, and save success is only
/// reported after the post-mutation reload succeeds.
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

class _CourtOwnerVenueManagePageState extends State<CourtOwnerVenueManagePage>
    with RouteAware {
  String? get _userId => AuthService.instance.currentUser?.id;

  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _sportCatalog = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late final FitnessBuddiesRepository _buddiesRepo = FitnessBuddiesRepository(
    Supabase.instance.client,
  );

  VenueSummary get _venue => widget.venue;

  Map<String, dynamic> get _venueMap =>
      Map<String, dynamic>.from(_detail?['venue'] as Map? ?? const {});

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

  /// The venue's owner-profile status (managers see the venue's truth,
  /// not their own profile).
  bool get _ownerApproved {
    final status = _detail?['owner_status']?.toString();
    if (status != null) return status == 'approved';
    return widget.ownerApproved;
  }

  String? get _memberRole => _detail?['member_role']?.toString();

  bool get _amenitiesConfirmed => _venueMap['amenities_confirmed'] == true;

  bool get _usesPlatformTerms => _venueMap['uses_platform_terms'] == true;

  bool get _hoursComplete => _hours.map((h) => h.dayOfWeek).toSet().length == 7;

  bool get _hasActiveCourts => _courts.any((c) => c.isActive);

  /// Server-computed missing setup items (same source the review gate
  /// uses); falls back to a local mirror when the field is absent.
  List<String> get _setupMissing {
    final raw = _detail?['setup_missing'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return _computeMissingLocally();
  }

  List<String> _computeMissingLocally() {
    final missing = <String>[];
    if (!_ownerApproved) missing.add('owner_not_approved');
    if ((_venueMap['name']?.toString() ?? _venue.name).trim().isEmpty) {
      missing.add('name');
    }
    if ((_venueMap['province']?.toString() ?? '').trim().isEmpty) {
      missing.add('province');
    }
    if ((_venueMap['district']?.toString() ?? '').trim().isEmpty) {
      missing.add('district');
    }
    if ((_venueMap['address']?.toString() ?? '').trim().isEmpty) {
      missing.add('address');
    }
    if (_venueMap['lat'] == null || _venueMap['lng'] == null) {
      missing.add('location');
    }
    if ((_venueMap['timezone']?.toString() ?? '').trim().isEmpty) {
      missing.add('timezone');
    }
    if (_venueSports.isEmpty) missing.add('sports');
    if (!_hoursComplete) missing.add('hours');
    if (!(_amenities.isNotEmpty || _amenitiesConfirmed)) {
      missing.add('amenities');
    }
    if (!(_terms != null || _usesPlatformTerms)) missing.add('terms');
    if (!_hasActiveCourts) missing.add('courts');
    return missing;
  }

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

  bool get _readyForReview => _setupMissing.isEmpty;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    dashboardRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    dashboardRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// Returning from a pushed page (bookings, notification route, etc.)
  /// always refreshes so review/setup status is current.
  @override
  void didPopNext() => _load();

  /// Returns true on success — callers must not claim a save succeeded
  /// when the state reload after the mutation failed.
  Future<bool> _load() async {
    final userId = _userId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'กรุณาเข้าสู่ระบบ';
      });
      return false;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.repo.getMyVenueDetail(userId, _venue.id),
        _buddiesRepo.getApprovedSports(userId: userId),
      ]);
      if (!mounted) return false;
      setState(() {
        _detail = results[0] as Map<String, dynamic>;
        _sportCatalog = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _mapError(e);
        });
      }
      return false;
    }
  }

  List<VenueSetupStep> get _steps => computeVenueSetupSteps(
    ownerApproved: _ownerApproved,
    venueCreated: true,
    hasSports: _venueSports.isNotEmpty,
    hoursComplete: _hoursComplete,
    amenitiesDone: _amenities.isNotEmpty || _amenitiesConfirmed,
    termsDone: !_setupMissing.contains('terms'),
    hasActiveCourts: _hasActiveCourts,
    venueStatus: _venueStatus,
  );

  Future<void> _run(VenueSetupStepId step) async {
    final userId = _userId;
    if (userId == null || _saving) return;
    switch (step) {
      case VenueSetupStepId.sports:
        final draft = await VenueSportsEditorDialog.show(
          context,
          sports: _sportCatalog,
          selectedUnits: {
            for (final vs in _venueSports)
              vs['sport_id']?.toString() ?? '':
                  vs['unit_label_override']?.toString() ?? '',
          },
        );
        if (draft == null) return;
        if (!_confirmSportRemoval(draft)) return;
        await _persist(
          () => widget.repo.setVenueSports(userId, _venue.id, draft),
          'บันทึกกีฬาของสนามแล้ว',
        );
      case VenueSetupStepId.hours:
        final draft = await VenueHoursEditorDialog.show(
          context,
          current: _hours,
        );
        if (draft == null) return;
        await _persist(
          () => widget.repo.setVenueOperatingHours(userId, _venue.id, draft),
          'บันทึกเวลาเปิด–ปิดแล้ว',
        );
      case VenueSetupStepId.amenities:
        final draft = await VenueAmenitiesEditorDialog.show(
          context,
          selected: _amenities,
        );
        if (draft == null) return;
        await _persist(
          () => widget.repo.setVenueAmenities(userId, _venue.id, draft),
          'บันทึกสิ่งอำนวยความสะดวกแล้ว',
        );
      case VenueSetupStepId.terms:
        await _editTerms(userId);
      case VenueSetupStepId.courts:
        await _editCourt();
      default:
        break;
    }
  }

  /// Terms choice: platform-managed terms are an explicit selection; custom
  /// terms publish a new active version.
  Future<void> _editTerms(String userId) async {
    final hasCustom = _terms != null;
    if (!hasCustom) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (c) => SafeArea(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Container(
              color: NeumorphicTheme.baseColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('ใช้เงื่อนไขมาตรฐานของแพลตฟอร์ม'),
                    subtitle: const Text('เหมาะสำหรับสนามทั่วไป'),
                    onTap: () => Navigator.pop(c, 'platform'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_note_rounded),
                    title: const Text('เขียนเงื่อนไขของสนามเอง'),
                    subtitle: const Text('ระบุ cutoff และเงื่อนไขเฉพาะสนาม'),
                    onTap: () => Navigator.pop(c, 'custom'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (choice == null) return;
      if (choice == 'platform') {
        await _persist(
          () => widget.repo.confirmPlatformTerms(userId, _venue.id),
          'ใช้เงื่อนไขมาตรฐานของแพลตฟอร์มแล้ว',
        );
        return;
      }
    }
    if (!mounted) return;
    final draft = await VenueTermsEditorDialog.show(
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
  }

  /// Blocks the save early when the draft drops a sport that still has
  /// active courts bound to it (the server enforces the same rule via
  /// SPORT_IN_USE — this just explains it before the round trip).
  bool _confirmSportRemoval(List<Map<String, dynamic>> draft) {
    final draftIds = {
      for (final item in draft) item['sport_id']?.toString() ?? '',
    };
    final removedIds = {
      for (final vs in _venueSports)
        if (!draftIds.contains(vs['sport_id']?.toString()))
          vs['sport_id']?.toString() ?? '',
    };
    if (removedIds.isEmpty) return true;
    final blocked = _courts
        .where((c) => c.isActive && removedIds.contains(c.sportId))
        .length;
    if (blocked == 0) return true;
    if (!mounted) return false;
    unawaited(
      GlassDialog.show<void>(
        context: context,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        contentPadding: EdgeInsets.zero,
        builder: (dialogContext) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ยังเอากีฬาออกไม่ได้',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'มี $blocked คอร์ทที่เปิดใช้งานผูกกับกีฬานี้ '
                  '— ปิดการใช้งานหรือย้ายคอร์ทไปกีฬาอื่นก่อน',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.75),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                GlassActionButton(
                  label: 'เข้าใจแล้ว',
                  isFilled: true,
                  fillColor: AppColors.primaryDark,
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return false;
  }

  Future<void> _editVenueProfile() async {
    final userId = _userId;
    if (userId == null || _saving) return;
    final v = _venueMap;
    final draft = await VenueProfileEditorSheet.show(
      context,
      name: v['name']?.toString() ?? _venue.name,
      description: v['description']?.toString(),
      province: v['province']?.toString(),
      district: v['district']?.toString(),
      address: v['address']?.toString(),
      lat: (v['lat'] as num?)?.toDouble(),
      lng: (v['lng'] as num?)?.toDouble(),
      timezone: v['timezone']?.toString(),
    );
    if (draft == null) return;
    await _persist(
      () async => widget.repo.upsertVenue(
        userId: userId,
        venueId: _venue.id,
        name: draft['name'] as String,
        description: draft['description'] as String?,
        province: draft['province'] as String?,
        district: draft['district'] as String?,
        address: draft['address'] as String?,
        lat: draft['lat'] as double?,
        lng: draft['lng'] as double?,
        timezone: draft['timezone'] as String?,
      ),
      'บันทึกข้อมูลสนามแล้ว',
    );
  }

  Future<void> _submitForReview() async {
    final userId = _userId;
    if (userId == null || _saving || !_readyForReview) return;
    await _persist(
      () => widget.repo.submitVenueForReview(userId, _venue.id),
      'ส่งตรวจสอบแล้ว — รอทีมงานอนุมัติ',
    );
  }

  Future<void> _editCourt([VenueCourt? court]) async {
    final userId = _userId;
    if (userId == null) return;
    if (_venueSports.isEmpty) {
      _toast('กรุณาตั้งค่ากีฬาของสนามก่อนเพิ่มคอร์ท');
      return;
    }
    var priceRules = const <VenueCourtPriceRule>[];
    if (court != null) {
      try {
        priceRules = await widget.repo.listMyCourtPriceRules(userId, court.id);
      } catch (e) {
        _toast(
          e.toString().contains('PGRST202')
              ? _mapError(e)
              : 'โหลดช่วงราคาของคอร์ทไม่สำเร็จ กรุณาลองใหม่',
        );
        return;
      }
    }
    if (!mounted) return;
    final draft = await OwnerCourtEditorDialog.show(
      context,
      court: court,
      priceRules: priceRules,
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
        isActive: draft['is_active'] as bool? ?? court?.isActive ?? true,
        priceRules: (draft['price_rules'] as List)
            .map(
              (rule) => VenueCourtPriceRule.fromJson(
                Map<String, dynamic>.from(rule as Map),
              ),
            )
            .toList(),
      ),
      court == null ? 'เพิ่มคอร์ทแล้ว' : 'บันทึกคอร์ทแล้ว',
    );
  }

  Future<void> _persist(Future<void> Function() action, String ok) async {
    setState(() => _saving = true);
    try {
      await action();
      final reloaded = await _load();
      // Never claim success when the post-mutation state failed to load.
      if (reloaded && ok.isNotEmpty) _toast(ok);
    } catch (e) {
      debugPrint('CourtOwnerVenueManagePage._persist failed: $e');
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
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor,
      drawer: const TlzDrawer(),
      body: Column(
        children: [
          // Same gradient header + TlzAppTopBar as the Sports Hub shell.
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: TlzAppTopBar.onPrimary(
                  middle: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _venue.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'การจอง',
                      onPressed: _openBookings,
                      icon: const Icon(
                        Icons.event_note_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: NeumorphicIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: 'ย้อนกลับ',
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ),
                ),
                Expanded(
                  child: _loading && _detail == null
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null && _detail == null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            children: [
                              _buildStatusCard(),
                              _buildVenueInfoCard(),
                              VenueSetupChecklistCard(
                                steps: steps,
                                venueStatus: _venueStatus,
                                saving: _saving,
                                onRun: _run,
                              ),
                              _buildCourtsSection(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'โหลดข้อมูลไม่สำเร็จ',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final status = _venueStatus;
    final (label, color) = switch (status) {
      VenueStatus.draft => ('แบบร่าง — ยังไม่ส่งตรวจ', Colors.blueGrey),
      VenueStatus.approved => ('เปิดรับการจองแล้ว', Colors.green.shade700),
      VenueStatus.pending => ('รอตรวจสอบ', Colors.orange.shade800),
      VenueStatus.rejected => ('ไม่ผ่านการตรวจสอบ', Colors.red.shade700),
      VenueStatus.suspended => ('ถูกระงับ', Colors.red.shade700),
      _ => ('ไม่ทราบสถานะ', Colors.grey.shade600),
    };
    final reason =
        _venueMap['rejection_reason']?.toString() ?? _venue.rejectionReason;
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
                    if (_memberRole == 'manager')
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'คุณเป็นผู้จัดการของสนามนี้',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
          if (reason != null &&
              reason.isNotEmpty &&
              status != VenueStatus.approved)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'เหตุผล: $reason',
                style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
              ),
            ),
          const SizedBox(height: 8),
          _buildReviewAction(status),
        ],
      ),
    );
  }

  Widget _buildReviewAction(VenueStatus? status) {
    switch (status) {
      case VenueStatus.draft:
      case VenueStatus.rejected:
        final missing = _setupMissing;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'ยังขาด: ${missing.map((m) => _missingLabels[m] ?? m).join(', ')}',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                ),
                onPressed: _saving || missing.isNotEmpty
                    ? null
                    : _submitForReview,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  status == VenueStatus.rejected
                      ? 'ส่งตรวจสอบอีกครั้ง'
                      : 'ส่งตรวจสอบ',
                ),
              ),
            ),
          ],
        );
      case VenueStatus.pending:
        return Text(
          'ทีมงานกำลังตรวจสอบข้อมูลสนามของคุณ',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        );
      case VenueStatus.suspended:
        return Text(
          'สนามถูกระงับ — หากต้องการอุทธรณ์ กรุณาติดต่อทีมงาน Sheserved',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        );
      case VenueStatus.approved:
        return Text(
          'สนามแสดงในรายการสาธารณะและเปิดรับการจองแล้ว',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildVenueInfoCard() {
    final v = _venueMap;
    String orNA(String? s) =>
        (s == null || s.trim().isEmpty) ? 'ยังไม่ได้ระบุ' : s;
    final location = v['lat'] != null && v['lng'] != null
        ? '${(v['lat'] as num).toStringAsFixed(4)}, ${(v['lng'] as num).toStringAsFixed(4)}'
        : 'ยังไม่ได้ระบุ';
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
              const Expanded(
                child: Text(
                  'ข้อมูลสนาม',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _saving ? null : _editVenueProfile,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('แก้ไข'),
              ),
            ],
          ),
          _infoLine(
            Icons.location_on_outlined,
            [
              v['district']?.toString(),
              v['province']?.toString(),
            ].whereType<String>().join(', '),
          ),
          _infoLine(Icons.map_outlined, orNA(v['address']?.toString())),
          _infoLine(Icons.my_location_rounded, 'พิกัด: $location'),
          _infoLine(
            Icons.schedule_rounded,
            'เขตเวลา: ${orNA(v['timezone']?.toString())}',
          ),
          if ((v['description']?.toString() ?? '').isNotEmpty)
            _infoLine(Icons.notes_rounded, v['description'].toString()),
          const SizedBox(height: 4),
          Text(
            'รูปภาพสนาม: ไม่บังคับสำหรับการอนุมัติ',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.isEmpty ? 'ยังไม่ได้ระบุ' : text,
              style: TextStyle(
                fontSize: 12.5,
                color: text.isEmpty ? Colors.orange.shade800 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourtsSection() {
    final courts = _courts;
    final canAdd = _venueSports.isNotEmpty;
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
                    if (court.startingPriceAmount != null)
                      'เริ่มต้น ${_formatPrice(court.startingPriceAmount!)} บาท/ชม.',
                    if (court.startingPriceAmount == null &&
                        court.priceAmount != null)
                      '${_formatPrice(court.priceAmount!)} บาท/${court.pricingUnit}',
                    court.approvalMode == BookingApprovalMode.ownerApproval
                        ? 'รออนุมัติ'
                        : 'ยืนยันทันที',
                    if (!court.isActive) 'ปิดใช้งาน',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: _saving ? null : () => _editCourt(court),
              ),
        ],
      ),
    );
  }

  static String _formatPrice(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);

  static String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('PLATFORM_TERMS_NOT_CONFIGURED')) {
      return 'ทีมงานยังไม่ได้ตั้งเงื่อนไขมาตรฐานสนาม กรุณาลองใหม่ภายหลัง';
    }
    if (raw.contains('PGRST202')) {
      return 'ระบบฐานข้อมูลยังไม่พร้อม กรุณาอัปเดต Supabase migrations แล้วลองใหม่';
    }
    if (raw.contains('UNAUTHORIZED')) return 'กรุณาเข้าสู่ระบบใหม่';
    if (raw.contains('INVALID_CUTOFF')) {
      return 'กรุณาระบุเวลายกเลิกเป็นจำนวนนาทีที่ไม่ติดลบ';
    }
    if (raw.contains('NOT_VENUE_MANAGER')) {
      return 'คุณไม่มีสิทธิ์จัดการสนามนี้';
    }
    if (raw.contains('SPORT_NOT_ON_VENUE')) {
      return 'กีฬานี้ยังไม่ได้ตั้งค่าในสนาม';
    }
    if (raw.contains('SPORT_IN_USE')) {
      return 'เอากีฬาออกไม่ได้ — ยังมีคอร์ทที่เปิดใช้งานผูกกับกีฬานี้';
    }
    if (raw.contains('INVALID_TERMS')) {
      return 'กรุณากรอกเงื่อนไขการใช้สนาม';
    }
    if (raw.contains('INVALID_COURT')) {
      return 'กรุณากรอกชื่อคอร์ท';
    }
    if (raw.contains('OVERLAPPING_PRICE_RULES')) {
      return 'ช่วงเวลาราคาซ้อนกัน กรุณาแก้ช่วงเวลา';
    }
    if (raw.contains('PRICE_RULES_REQUIRE_HOURLY')) {
      return 'กรุณาเลือกคิดราคาต่อชั่วโมงก่อนกำหนดช่วงราคา';
    }
    if (raw.contains('INVALID_PRICE_RULE')) {
      return 'ข้อมูลช่วงราคาหรือราคา/ชั่วโมงไม่ถูกต้อง';
    }
    if (raw.contains('INCOMPLETE_HOURS')) {
      return 'กรุณาระบุเวลาเปิด–ปิดให้ครบทั้ง 7 วัน';
    }
    if (raw.contains('INVALID_HOURS')) {
      return 'รูปแบบเวลาเปิด–ปิดไม่ถูกต้อง (ไม่รองรับข้ามเที่ยงคืน)';
    }
    if (raw.contains('VENUE_NOT_READY')) {
      return 'ตั้งค่าสนามยังไม่ครบตามเงื่อนไขการตรวจสอบ';
    }
    if (raw.contains('INVALID_STATUS')) {
      return 'สถานะสนามไม่อนุญาตให้ทำรายการนี้';
    }
    if (raw.contains('OWNER_NOT_APPROVED')) {
      return 'บัญชีเจ้าของสนามยังไม่ได้รับการอนุมัติ';
    }
    return 'ทำรายการไม่สำเร็จ กรุณาลองใหม่';
  }
}
