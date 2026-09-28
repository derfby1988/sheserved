import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/glass/glass_confirm_dialog.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/coach_models.dart';
import '../../data/find_coach_repository.dart';
import '../widgets/coach_labels.dart';
import '../widgets/dialogs/coach_editors.dart';
import '../widgets/dialogs/coach_enrollment_dialogs.dart';
import '../widgets/dialogs/coach_profile_dialogs.dart';
import '../widgets/dialogs/coach_request_detail_dialog.dart';

/// Coach self-service hub — profile lifecycle, contacts, certifications,
/// teaching locations, weekly availability, offerings/sessions, 1:1
/// slots, enrollment requests and roster.
///
/// Pushed from the Find Coach page (no new top-level route). The page
/// itself is Neumorphic; every editor runs inside a Glass dialog.
class CoachManagementPage extends StatefulWidget {
  final FindCoachRepository repo;
  final List<Map<String, dynamic>> sports;

  const CoachManagementPage({
    super.key,
    required this.repo,
    this.sports = const [],
  });

  @override
  State<CoachManagementPage> createState() => _CoachManagementPageState();
}

class _CoachManagementPageState extends State<CoachManagementPage> {
  bool _loading = true;
  bool _busy = false;
  String? _error;

  CoachSummary? _profile;
  CoachProfileCompleteness? _completeness;
  CoachContact? _contact;
  List<CoachCertification> _certs = const [];
  List<CoachTeachingLocation> _locations = const [];
  List<CoachAvailabilityWindow> _windows = const [];
  List<CoachSportRow> _sportRows = const [];
  List<CoachOffering> _offerings = const [];
  List<CoachSlot> _slots = const [];
  List<CoachEnrollment> _pendingEnrollments = const [];
  List<CoachEnrollment> _roster = const [];
  List<CoachBookingRequest> _requests = const [];

  String? get _userId => AuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'กรุณาเข้าสู่ระบบ';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.repo.getMyCoachProfile(userId);
      if (!mounted) return;
      if (profile == null) {
        setState(() {
          _profile = null;
          _loading = false;
        });
        return;
      }
      final results = await Future.wait<Object?>([
        widget.repo.getProfileCompleteness(userId),
        widget.repo.getMyCoachContacts(userId),
        widget.repo.listMyCredentials(userId),
        widget.repo.listMyLocations(userId),
        widget.repo.listCoachAvailability(profile.id),
        widget.repo.listMyCoachSports(userId),
        widget.repo.listMyOfferings(userId),
        widget.repo.listMySlots(userId),
        widget.repo.listEnrollmentsForCoach(
          userId,
          statuses: const ['pending'],
        ),
        widget.repo.listEnrollmentsForCoach(
          userId,
          statuses: const ['confirmed', 'completed'],
        ),
        widget.repo.listCoachBookingRequestsForCoach(userId),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _completeness = results[0] as CoachProfileCompleteness;
        _contact = results[1] as CoachContact?;
        _certs = results[2] as List<CoachCertification>;
        _locations = results[3] as List<CoachTeachingLocation>;
        _windows = results[4] as List<CoachAvailabilityWindow>;
        _sportRows = results[5] as List<CoachSportRow>;
        _offerings = results[6] as List<CoachOffering>;
        _slots = results[7] as List<CoachSlot>;
        _pendingEnrollments = results[8] as List<CoachEnrollment>;
        _roster = results[9] as List<CoachEnrollment>;
        _requests = results[10] as List<CoachBookingRequest>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = CoachLabels.mapError(e);
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? success,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) _toast(success);
      await _load();
    } catch (e) {
      _toast(CoachLabels.mapError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =============== Profile lifecycle ===============

  Future<void> _editProfile() async {
    final userId = _userId;
    if (userId == null) return;
    final draft = await CoachProfileEditorDialog.show(
      context,
      existing: _profile,
    );
    if (draft == null || !mounted) return;
    await _run(
      () => widget.repo.upsertCoachProfile(
        userId: userId,
        displayName: draft.displayName,
        bio: draft.bio,
        experience: draft.experience,
        hourlyRate: draft.hourlyRate,
        teachingMode: draft.teachingMode,
        acceptingStudents: draft.acceptingStudents,
      ),
      success: _profile == null ? 'สร้างโปรไฟล์แล้ว' : 'บันทึกโปรไฟล์แล้ว',
    );
  }

  Future<void> _submitForReview() async {
    final userId = _userId;
    if (userId == null) return;
    final completeness = _completeness;
    final ok = await GlassConfirmDialog.show(
      context,
      icon: Icons.verified_user_outlined,
      title: 'ส่งโปรไฟล์ให้ทีมงานตรวจ',
      accentColor: AppColors.primary,
      cancelLabel: 'กลับ',
      confirmLabel: 'ส่งตรวจ',
      content: Text(
        _profile?.status == CoachStatus.rejected
            ? 'โปรไฟล์จะส่งตรวจใหม่หลังแก้ตามเหตุผลที่ถูกปฏิเสธ'
            : 'ทีมงานจะตรวจข้อมูลและแจ้งผลในแจ้งเตือนของคุณ',
        style: const TextStyle(fontSize: 13, color: Colors.white70),
      ),
      onConfirm: () async {
        try {
          await widget.repo.submitProfileForReview(userId);
          return true;
        } catch (_) {
          return false;
        }
      },
    );
    if (ok == true && mounted) {
      _toast('ส่งตรวจแล้ว รอทีมงานแจ้งผล');
      await _load();
    } else if (completeness != null && !completeness.isComplete) {
      _toast('กรุณากรอกข้อมูลให้ครบทุกข้อก่อนส่งตรวจ');
    }
  }

  // =============== Section editors ===============

  Future<void> _editContacts() async {
    final userId = _userId;
    if (userId == null) return;
    final result = await CoachContactsEditorDialog.show(
      context,
      contact: _contact,
    );
    if (result == null || !mounted) return;
    await _run(
      () => widget.repo.setCoachContacts(
        userId,
        phone: result.phone,
        lineId: result.lineId,
        facebookUrl: result.facebookUrl,
      ),
      success: 'บันทึกช่องทางติดต่อแล้ว',
    );
  }

  Future<void> _editCertifications() async {
    final userId = _userId;
    if (userId == null) return;
    final result = await CoachCertificationsEditorDialog.show(
      context,
      items: _certs,
    );
    if (result == null || !mounted) return;
    await _run(
      () => widget.repo.setCoachCertifications(userId, result),
      success: 'บันทึกใบรับรองแล้ว — รายการที่แก้จะรอตรวจใหม่',
    );
  }

  Future<void> _editLocations() async {
    final userId = _userId;
    if (userId == null) return;
    final result = await CoachLocationsEditorDialog.show(
      context,
      locations: _locations,
    );
    if (result == null || !mounted) return;
    await _run(
      () => widget.repo.setCoachTeachingLocations(userId, result),
      success: 'บันทึกสถานที่สอนแล้ว',
    );
  }

  Future<void> _editAvailability() async {
    final userId = _userId;
    if (userId == null) return;
    final result = await CoachAvailabilityEditorDialog.show(
      context,
      windows: _windows,
    );
    if (result == null || !mounted) return;
    await _run(
      () => widget.repo.setCoachAvailability(userId, result),
      success: 'บันทึกเวลาว่างแล้ว',
    );
  }

  Future<void> _editSports() async {
    final userId = _userId;
    if (userId == null) return;
    final result = await CoachSportsEditorDialog.show(
      context,
      items: _sportRows,
      sports: widget.sports,
    );
    if (result == null || !mounted) return;
    await _run(
      () => widget.repo.setCoachSports(
        userId,
        result.map((e) => e.toJson()).toList(),
      ),
      success: 'บันทึกกีฬาที่สอนแล้ว',
    );
  }

  // =============== Offerings ===============

  Future<void> _editOffering({CoachOffering? existing}) async {
    final userId = _userId;
    if (userId == null) return;
    final draft = await CoachOfferingEditorDialog.show(
      context,
      existing: existing,
      locations: _locations,
      sports: [
        for (final s in widget.sports)
          (
            id: s['id']?.toString() ?? '',
            name:
                s['name_th']?.toString() ?? s['name']?.toString() ?? 'กีฬา',
          ),
      ],
    );
    if (draft == null || !mounted) return;
    await _run(() async {
      final offeringId = await widget.repo.upsertOffering(
        userId,
        offeringId: draft.id,
        offeringType: draft.offeringType,
        title: draft.title,
        description: draft.description,
        sportId: draft.sportId,
        learnerLevels: draft.learnerLevels,
        teachingMode: draft.teachingMode,
        locationId: draft.locationId,
        locationLabel: draft.locationLabel,
        price: draft.price,
        pricingUnit: draft.pricingUnit,
        capacity: draft.capacity,
        minEnrollment: draft.minEnrollment,
        enrollmentCutoffHours: draft.enrollmentCutoffHours,
        cancellationCutoffHours: draft.cancellationCutoffHours,
        scheduleNoResponse: draft.scheduleNoResponse,
        autoConfirm: draft.autoConfirm,
        allowPartialEnrollment: draft.allowPartialEnrollment,
      );
      if (existing == null) {
        await _editSessionsFor(offeringId);
      }
    }, success: 'บันทึกรายการแล้ว');
  }

  Future<void> _editSessionsFor(String offeringId) async {
    final offering = _offerings.firstWhere(
      (o) => o.id == offeringId,
      orElse: () => CoachOffering(
        id: offeringId,
        type: CoachOfferingType.groupClass,
        title: '',
      ),
    );
    final drafts = await CoachSessionsEditorDialog.show(
      context,
      offering: offering,
    );
    if (drafts == null || !mounted) return;
    await _run(
      () => widget.repo.setOfferingSessions(
        _userId!,
        offeringId,
        drafts.map((d) => d.toJson()).toList(),
      ),
      success: 'บันทึกรอบการสอนแล้ว',
    );
  }

  Future<void> _offeringAction(
    CoachOffering o,
    _OfferingAction action,
  ) async {
    final userId = _userId;
    if (userId == null) return;
    switch (action) {
      case _OfferingAction.edit:
        await _editOffering(existing: o);
      case _OfferingAction.sessions:
        await _editSessionsFor(o.id);
      case _OfferingAction.publish:
        await _run(
          () => widget.repo.publishOffering(userId, o.id),
          success: 'เปิดรับสมัครแล้ว',
        );
      case _OfferingAction.close:
        await _run(
          () => widget.repo.closeOffering(userId, o.id),
          success: 'ปิดรับสมัครแล้ว',
        );
      case _OfferingAction.cancel:
        final reason = await CoachReasonDialog.show(
          context,
          title: 'ยกเลิกรายการนี้',
          hint: 'เหตุผลจะแจ้งผู้เรียนที่ยืนยันแล้วทั้งหมด',
          confirmLabel: 'ยืนยันยกเลิก',
        );
        if (reason == null || !mounted) return;
        await _run(
          () => widget.repo.cancelOffering(userId, o.id, reason),
          success: 'ยกเลิกรายการแล้ว',
        );
      case _OfferingAction.minimum:
        final decision = await CoachMinimumDecisionDialog.show(
          context,
          offering: o,
        );
        if (decision == null || !mounted) return;
        await _run(
          () => widget.repo.resolveMinimum(
            userId,
            o.id,
            proceed: decision.proceed,
            reopenUntil: decision.reopenUntil,
          ),
          success: decision.proceed
              ? 'ดำเนินการตามจำนวนผู้เรียนปัจจุบัน'
              : 'ยกเลิกรายการแล้ว',
        );
    }
  }

  // =============== Slots ===============

  CoachOffering? get _oneOnOneOffering {
    for (final o in _offerings) {
      if (o.isOneOnOne) return o;
    }
    return null;
  }

  Future<void> _createSlot() async {
    final userId = _userId;
    if (userId == null) return;
    var offering = _oneOnOneOffering;
    if (offering == null) {
      // 1:1 slots hang off a one_on_one offering — ask the coach to
      // create it first.
      _toast('สร้างรายการ "สอนตัวต่อตัว" ก่อนเพิ่มช่วงเวลา');
      return;
    }
    final draft = await CoachSlotEditorDialog.show(
      context,
      timezone: _profile?.timezone ?? 'Asia/Bangkok',
    );
    if (draft == null || !mounted) return;
    offering = _oneOnOneOffering;
    if (offering == null) return;
    await _run(
      () => widget.repo.createSlot(
        userId,
        offering!.id,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
        publish: draft.publish,
      ),
      success: draft.publish ? 'เปิดช่วงเวลาให้จองแล้ว' : 'บันทึกแบบร่างแล้ว',
    );
  }

  Future<void> _slotAction(CoachSlot s, _SlotAction action) async {
    final userId = _userId;
    if (userId == null) return;
    switch (action) {
      case _SlotAction.edit:
        final draft = await CoachSlotEditorDialog.show(
          context,
          existing: s,
          timezone: _profile?.timezone ?? 'Asia/Bangkok',
        );
        if (draft == null || !mounted) return;
        await _run(
          () => widget.repo.updateSlot(
            userId,
            s.id,
            startsAt: draft.startsAt,
            endsAt: draft.endsAt,
          ),
          success: 'ย้ายเวลาแล้ว',
        );
      case _SlotAction.publish:
        await _run(
          () => widget.repo.publishSlot(userId, s.id),
          success: 'เปิดจองแล้ว',
        );
      case _SlotAction.cancel:
        final reason = s.status == CoachSlotStatus.booked
            ? await CoachReasonDialog.show(
                context,
                title: 'ยกเลิก slot ที่มีการจอง',
                hint: 'เหตุผลจะแจ้งผู้เรียน',
                confirmLabel: 'ยืนยันยกเลิก',
              )
            : '';
        if (reason == null || !mounted) return;
        await _run(
          () => widget.repo.cancelSlot(userId, s.id, reason: reason),
          success: 'ยกเลิกช่วงเวลาแล้ว',
        );
    }
  }

  // =============== Requests / roster ===============

  Future<void> _openEnrollment(CoachEnrollment e) async {
    final result = await CoachEnrollmentDetailDialog.show(
      context,
      enrollment: e,
      onDecision: (decision, {reason}) async {
        try {
          await widget.repo.decideEnrollment(
            _userId!,
            e.id,
            decision == 'approve' ? 'approve' : 'reject',
            reason: reason,
          );
          return decision;
        } catch (err) {
          _toast(CoachLabels.mapError(err));
          return null;
        }
      },
    );
    if (result != null && mounted) {
      _toast(result == 'approve' ? 'อนุมัติแล้ว' : 'ปฏิเสธคำขอแล้ว');
      await _load();
    }
  }

  Future<void> _openBookingRequest(CoachBookingRequest r) async {
    final result = await CoachRequestDetailDialog.show(
      context,
      request: r,
      onDecision: (decision, {reason}) async {
        try {
          await widget.repo.decideBookingRequest(
            _userId!,
            r.id,
            decision == 'approve' ? 'approve' : 'reject',
            reason: reason,
          );
          return decision;
        } catch (err) {
          _toast(CoachLabels.mapError(err));
          return null;
        }
      },
    );
    if (result != null && mounted) {
      _toast(result == 'approve' ? 'ตอบรับนัดแล้ว' : 'ปฏิเสธคำขอแล้ว');
      await _load();
    }
  }

  Future<void> _proposeChange(
    CoachEnrollment enrollment,
    CoachEnrollmentSession session,
  ) async {
    final userId = _userId;
    if (userId == null) return;
    final draft = await CoachProposeScheduleChangeDialog.show(
      context,
      session: CoachOfferingSession(
        id: session.sessionId,
        startsAt: session.startsAt,
        endsAt: session.endsAt,
        timezone: session.timezone,
        locationLabel: session.locationLabel,
        confirmedCount: session.confirmedCount,
      ),
      timezone: _profile?.timezone ?? 'Asia/Bangkok',
    );
    if (draft == null || !mounted) return;
    await _run(
      () => widget.repo.proposeSessionChange(
        userId,
        session.sessionId,
        newStartsAt: draft.newStartsAt,
        newEndsAt: draft.newEndsAt,
        newLocation: draft.location,
        reason: draft.reason,
      ),
      success: 'ส่งข้อเสนอเปลี่ยนตารางแล้ว',
    );
  }

  Future<void> _cancelEnrollment(CoachEnrollment e) async {
    final userId = _userId;
    if (userId == null) return;
    final reason = await CoachReasonDialog.show(
      context,
      title: 'ยกเลิกการสมัครของ ${e.learnerName ?? 'ผู้เรียน'}',
      hint: 'เหตุผลจะแจ้งผู้เรียน',
      confirmLabel: 'ยืนยันยกเลิก',
    );
    if (reason == null || !mounted) return;
    await _run(
      () => widget.repo.cancelEnrollment(userId, e.id, reason: reason),
      success: 'ยกเลิกการสมัครแล้ว',
    );
  }

  // =============== Build ===============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor,
      appBar: AppBar(
        backgroundColor: NeumorphicTheme.baseColor,
        elevation: 0,
        foregroundColor: NeumorphicTheme.textPrimary,
        title: const Text(
          'จัดการโค้ช',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _load, child: const Text('ลองใหม่')),
                ],
              ),
            )
          : _profile == null
          ? _buildOnboarding()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _buildProfileCard(),
                  _buildContactsCard(),
                  _buildCertsCard(),
                  _buildLocationsCard(),
                  _buildSportsCard(),
                  _buildAvailabilityCard(),
                  _buildOfferingsSection(),
                  _buildSlotsSection(),
                  _buildRequestsSection(),
                  _buildRosterSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildOnboarding() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.school_rounded,
                size: 48,
                color: AppColors.primaryDark,
              ),
              const SizedBox(height: 12),
              const Text(
                'สมัครเป็นโค้ช',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: NeumorphicTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'กรอกโปรไฟล์และส่งให้ทีมงานตรวจ '
                '— โปรไฟล์จะแสดงในหน้าค้นหาหลังอนุมัติ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: NeumorphicTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _busy ? null : _editProfile,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('เริ่มกรอกโปรไฟล์'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry margin = const EdgeInsets.only(bottom: 14),
  }) {
    return NeumorphicContainer(
      margin: margin,
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      depth: 4,
      blur: 8,
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.7),
      ),
      child: child,
    );
  }

  Widget _sectionHeader(
    IconData icon,
    String title, {
    String? badge,
    Widget? trailing,
    Color iconColor = AppColors.primaryDark,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: NeumorphicTheme.baseColor,
            boxShadow: NeumorphicTheme.smallShadows(distance: 2, blur: 4),
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: NeumorphicTheme.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 3,
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
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: iconColor,
              ),
            ),
          ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  Widget _miniAction(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    Color color = AppColors.primaryDark,
  }) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final p = _profile!;
    final completeness = _completeness;
    final statusColor = switch (p.status) {
      CoachStatus.approved => const Color(0xFF2E7D32),
      CoachStatus.rejected => const Color(0xFFC62828),
      CoachStatus.suspended => const Color(0xFF6A1B9A),
      _ => const Color(0xFFEF6C00),
    };
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.badge_outlined,
            'โปรไฟล์โค้ช',
            badge: p.status != null
                ? CoachLabels.coachStatus(p.status!)
                : null,
            iconColor: statusColor,
            trailing: _miniAction(
              'แก้ไข',
              Icons.edit_outlined,
              _editProfile,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: p.avatarUrl?.isNotEmpty == true
                    ? NetworkImage(p.avatarUrl!)
                    : null,
                child: p.avatarUrl?.isNotEmpty == true
                    ? null
                    : const Icon(Icons.person, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.displayName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: NeumorphicTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (p.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: Color(0xFF1E88E5),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      [
                        CoachLabels.mode(p.teachingMode),
                        if (p.hourlyRate != null)
                          '${CoachLabels.formatBaht(p.hourlyRate)}/ชม.',
                        p.acceptingStudents
                            ? 'เปิดรับผู้เรียน'
                            : 'ปิดรับชั่วคราว',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: NeumorphicTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (p.status == CoachStatus.rejected &&
              p.rejectionReason?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'เหตุผลที่ถูกปฏิเสธ: ${p.rejectionReason}',
                style: TextStyle(fontSize: 12, color: Colors.red.shade800),
              ),
            ),
          ],
          if (p.status == CoachStatus.suspended) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'โปรไฟล์ถูกระงับการแสดง — ติดต่อทีมงานเพื่อสอบถาม',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.purple.shade800,
                ),
              ),
            ),
          ],
          if (completeness != null &&
              (p.status == CoachStatus.pending ||
                  p.status == CoachStatus.rejected)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final check in completeness.checks)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: check.done
                          ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${check.done ? '✓' : '○'} ${check.key}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: check.done
                            ? const Color(0xFF2E7D32)
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: completeness.isComplete
                      ? AppColors.primaryDark
                      : Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onPressed: _busy || !completeness.isComplete
                    ? null
                    : _submitForReview,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: Text(
                  p.status == CoachStatus.rejected
                      ? 'ส่งตรวจใหม่'
                      : 'ส่งให้ทีมงานตรวจ',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactsCard() {
    final c = _contact;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.contact_phone_outlined,
            'ช่องทางติดต่อ (ส่วนตัว)',
            trailing: _miniAction(
              'แก้ไข',
              Icons.edit_outlined,
              _editContacts,
            ),
          ),
          const SizedBox(height: 8),
          if (c == null || c.isEmpty)
            Text(
              'ยังไม่มี — ผู้เรียนที่ยืนยันแล้วเท่านั้นที่เห็น',
              style: TextStyle(
                fontSize: 12,
                color: NeumorphicTheme.textSecondary,
              ),
            )
          else
            Text(
              [
                if (c.phone?.isNotEmpty == true) 'โทร ${c.phone}',
                if (c.lineId?.isNotEmpty == true) 'LINE ${c.lineId}',
                if (c.facebookUrl?.isNotEmpty == true) 'Facebook',
              ].join(' · '),
              style: const TextStyle(
                fontSize: 12.5,
                color: NeumorphicTheme.textPrimary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCertsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.workspace_premium_outlined,
            'ใบรับรอง',
            badge: _certs.isEmpty ? null : '${_certs.length}',
            trailing: _miniAction(
              'จัดการ',
              Icons.edit_outlined,
              _editCertifications,
            ),
          ),
          if (_certs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'เพิ่มใบรับรองอย่างน้อย 1 รายการเพื่อส่งตรวจ',
                style: TextStyle(
                  fontSize: 12,
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
            )
          else
            for (final c in _certs.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      switch (c.status) {
                        CoachCertStatus.approved =>
                          Icons.check_circle_rounded,
                        CoachCertStatus.rejected => Icons.cancel_rounded,
                        _ => Icons.hourglass_top_rounded,
                      },
                      size: 15,
                      color: switch (c.status) {
                        CoachCertStatus.approved =>
                          const Color(0xFF2E7D32),
                        CoachCertStatus.rejected =>
                          const Color(0xFFC62828),
                        _ => const Color(0xFFEF6C00),
                      },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${c.name}${c.issuer != null ? ' · ${c.issuer}' : ''}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: NeumorphicTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          if (_certs.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'และอีก ${_certs.length - 3} รายการ',
                style: TextStyle(
                  fontSize: 11,
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.place_outlined,
            'สถานที่สอน',
            badge:
                _locations.isEmpty ? null : '${_locations.length}',
            trailing: _miniAction(
              'จัดการ',
              Icons.edit_outlined,
              _editLocations,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _locations.isEmpty
                  ? 'ยังไม่มีสถานที่ — เพิ่มสถานที่ที่สอนประจำ'
                  : _locations.map((l) => l.name).join(', '),
              style: TextStyle(
                fontSize: 12.5,
                color: _locations.isEmpty
                    ? NeumorphicTheme.textSecondary
                    : NeumorphicTheme.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSportsCard() {
    String sportName(String id) {
      for (final s in widget.sports) {
        if (s['id']?.toString() == id) {
          return s['name_th']?.toString() ??
              s['name']?.toString() ??
              'กีฬา';
        }
      }
      return 'กีฬา';
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.sports_rounded,
            'กีฬาที่สอน',
            badge: _sportRows.isEmpty ? null : '${_sportRows.length}',
            trailing: _miniAction(
              'จัดการ',
              Icons.edit_outlined,
              _editSports,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _sportRows.isEmpty
                  ? 'เลือกกีฬาและระดับผู้เรียนที่คุณสอน'
                  : _sportRows
                        .map(
                          (r) =>
                              '${sportName(r.sportId)} '
                              '(${r.skillLevels.map(CoachLabels.level).join(', ')})',
                        )
                        .join('\n'),
              style: TextStyle(
                fontSize: 12.5,
                color: _sportRows.isEmpty
                    ? NeumorphicTheme.textSecondary
                    : NeumorphicTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.event_available_outlined,
            'เวลาว่างประจำสัปดาห์',
            badge: _windows.isEmpty ? null : '${_windows.length}',
            trailing: _miniAction(
              'จัดการ',
              Icons.edit_outlined,
              _editAvailability,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _windows.isEmpty
                  ? 'กำหนดช่วงเวลาที่สอนได้ในแต่ละสัปดาห์'
                  : _windows
                        .map(
                          (w) =>
                              '${CoachLabels.dayOfWeek(w.dayOfWeek)} '
                              '${w.startTime}–${w.endTime}',
                        )
                        .join('  ·  '),
              style: TextStyle(
                fontSize: 12.5,
                color: _windows.isEmpty
                    ? NeumorphicTheme.textSecondary
                    : NeumorphicTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferingsSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.class_outlined,
            'คลาสและหลักสูตร',
            badge:
                _offerings.isEmpty ? null : '${_offerings.length}',
            trailing: _miniAction(
              'สร้างใหม่',
              Icons.add_rounded,
              () => _editOffering(),
            ),
          ),
          const SizedBox(height: 10),
          if (_offerings.isEmpty)
            Text(
              'สร้างคลาสครั้งเดียว หลักสูตรหลายรอบ หรือรายการ 1:1',
              style: TextStyle(
                fontSize: 12,
                color: NeumorphicTheme.textSecondary,
              ),
            )
          else
            for (final o in _offerings) _offeringTile(o),
        ],
      ),
    );
  }

  Widget _offeringTile(CoachOffering o) {
    final statusColor = CoachLabels.offeringStatusColor(o.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        key: ValueKey('offering_${o.id}'),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: o.isDone ? 0.25 : 0.75,
          children: [
            if (!o.isDone)
              _slidableAction(
                label: 'แก้ไข',
                icon: Icons.edit_outlined,
                color: const Color(0xFF1565C0),
                onTap: () => _offeringAction(o, _OfferingAction.edit),
              ),
            if (!o.isDone)
              _slidableAction(
                label: 'รอบ',
                icon: Icons.event_note_rounded,
                color: const Color(0xFF6A1B9A),
                onTap: () =>
                    _offeringAction(o, _OfferingAction.sessions),
              ),
            if (o.status == CoachOfferingStatus.draft)
              _slidableAction(
                label: 'เปิดรับ',
                icon: Icons.publish_rounded,
                color: const Color(0xFF2E7D32),
                onTap: () =>
                    _offeringAction(o, _OfferingAction.publish),
              ),
            if (o.status == CoachOfferingStatus.published)
              _slidableAction(
                label: 'ปิดรับ',
                icon: Icons.pause_circle_outline_rounded,
                color: const Color(0xFFEF6C00),
                onTap: () => _offeringAction(o, _OfferingAction.close),
              ),
            if (o.isMinimumDecisionDue)
              _slidableAction(
                label: 'ตัดสินใจ',
                icon: Icons.how_to_vote_outlined,
                color: AppColors.alertGold,
                onTap: () =>
                    _offeringAction(o, _OfferingAction.minimum),
              ),
            if (!o.isDone)
              _slidableAction(
                label: 'ยกเลิก',
                icon: Icons.cancel_outlined,
                color: const Color(0xFFC62828),
                onTap: () =>
                    _offeringAction(o, _OfferingAction.cancel),
              ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      o.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: NeumorphicTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      CoachLabels.offeringStatus(o.status),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  CoachLabels.offeringType(o.type),
                  if (o.price != null)
                    '${CoachLabels.formatBaht(o.price)} ${CoachLabels.pricingUnit(o.pricingUnit)}',
                  '${o.sessions.length} รอบ',
                  'ยืนยัน ${o.confirmedCount} คน',
                  if (o.minEnrollment > 0) 'ขั้นต่ำ ${o.minEnrollment}',
                ].join(' · '),
                style: TextStyle(
                  fontSize: 11.5,
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
              if (!o.isDone && o.sessions.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final s in o.sessions.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_rounded,
                          size: 13,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'รอบ ${s.seq} · ${formatThaiSessionRange(s.startsAt.toLocal(), s.endsAt.toLocal())} '
                            '· ยืนยัน ${s.confirmedCount}${s.capacity != null ? '/${s.capacity}' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: NeumorphicTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (!o.isDone)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'ปัดซ้ายเพื่อจัดการ',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlotsSection() {
    final slots = _slots
        .where((s) => s.status != CoachSlotStatus.expired)
        .toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.schedule_rounded,
            'ช่วงเวลา 1:1',
            badge: slots.isEmpty ? null : '${slots.length}',
            trailing: _miniAction(
              'เพิ่มช่วงเวลา',
              Icons.add_rounded,
              _createSlot,
            ),
          ),
          const SizedBox(height: 10),
          if (slots.isEmpty)
            Text(
              'เผยแพร่ช่วงเวลาที่เปิดให้ผู้เรียนขอนัด 1:1',
              style: TextStyle(
                fontSize: 12,
                color: NeumorphicTheme.textSecondary,
              ),
            )
          else
            for (final s in slots.take(12)) _slotTile(s),
        ],
      ),
    );
  }

  Widget _slotTile(CoachSlot s) {
    final (color, label) = switch (s.status) {
      CoachSlotStatus.published => (
        const Color(0xFF2E7D32),
        'เปิดจอง',
      ),
      CoachSlotStatus.booked => (const Color(0xFF1565C0), 'จองแล้ว'),
      CoachSlotStatus.cancelled => (const Color(0xFFC62828), 'ยกเลิก'),
      CoachSlotStatus.expired => (const Color(0xFF64748B), 'หมดอายุ'),
      _ => (const Color(0xFF64748B), 'แบบร่าง'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Slidable(
        key: ValueKey('slot_${s.id}'),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: s.status == CoachSlotStatus.booked ? 0.25 : 0.55,
          children: [
            if (s.status == CoachSlotStatus.draft ||
                s.status == CoachSlotStatus.published)
              _slidableAction(
                label: 'ย้ายเวลา',
                icon: Icons.edit_calendar_outlined,
                color: const Color(0xFF1565C0),
                onTap: () => _slotAction(s, _SlotAction.edit),
              ),
            if (s.status == CoachSlotStatus.draft)
              _slidableAction(
                label: 'เปิดจอง',
                icon: Icons.publish_rounded,
                color: const Color(0xFF2E7D32),
                onTap: () => _slotAction(s, _SlotAction.publish),
              ),
            if (s.status != CoachSlotStatus.cancelled &&
                s.status != CoachSlotStatus.expired)
              _slidableAction(
                label: 'ยกเลิก',
                icon: Icons.cancel_outlined,
                color: const Color(0xFFC62828),
                onTap: () => _slotAction(s, _SlotAction.cancel),
              ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatThaiSessionRange(
                        s.startsAt.toLocal(),
                        s.endsAt.toLocal(),
                      ),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: NeumorphicTheme.textPrimary,
                      ),
                    ),
                    if (s.pendingRequests > 0)
                      Text(
                        'คำขอรอตอบ ${s.pendingRequests} รายการ',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.orange.shade800,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestsSection() {
    final pendingEnrollments = _pendingEnrollments;
    final pendingRequests = _requests
        .where((r) => r.isPending)
        .toList();
    final confirmedRequests = _requests
        .where((r) => r.isConfirmed)
        .toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.inbox_rounded,
            'คำขอที่รอตอบ',
            badge:
                pendingEnrollments.length + pendingRequests.length == 0
                ? null
                : '${pendingEnrollments.length + pendingRequests.length}',
          ),
          const SizedBox(height: 10),
          if (pendingEnrollments.isEmpty &&
              pendingRequests.isEmpty &&
              confirmedRequests.isEmpty)
            Text(
              'คำขอสมัครคลาสและคำขอนัด 1:1 จะขึ้นที่นี่',
              style: TextStyle(
                fontSize: 12,
                color: NeumorphicTheme.textSecondary,
              ),
            )
          else ...[
            for (final e in pendingEnrollments)
              _pendingEnrollmentTile(e),
            for (final r in pendingRequests) _requestTile(r),
            if (confirmedRequests.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'นัด 1:1 ที่ยืนยันแล้ว (${confirmedRequests.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: NeumorphicTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              for (final r in confirmedRequests.take(5))
                _confirmedRequestTile(r),
            ],
          ],
        ],
      ),
    );
  }

  Widget _pendingEnrollmentTile(CoachEnrollment e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : () => _openEnrollment(e),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.orange.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.assignment_ind_outlined,
                size: 18,
                color: Color(0xFFEF6C00),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.learnerName ?? 'ผู้เรียน',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: NeumorphicTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '${e.offeringTitle} · ${e.sessions.length} รอบ',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: NeumorphicTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestTile(CoachBookingRequest r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : () => _openBookingRequest(r),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.orange.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 18,
                color: Color(0xFFEF6C00),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1:1 · ${r.requesterName ?? 'ผู้เรียน'}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: NeumorphicTheme.textPrimary,
                      ),
                    ),
                    Text(
                      formatThaiSessionRange(
                        r.startsAt.toLocal(),
                        r.endsAt.toLocal(),
                      ),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: NeumorphicTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmedRequestTile(CoachBookingRequest r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Slidable(
        key: ValueKey('req_${r.id}'),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.3,
          children: [
            _slidableAction(
              label: 'ยกเลิกนัด',
              icon: Icons.cancel_outlined,
              color: const Color(0xFFC62828),
              onTap: () async {
                final reason = await CoachReasonDialog.show(
                  context,
                  title: 'ยกเลิกนัดที่ยืนยันแล้ว',
                  hint: 'เหตุผลจะแจ้งผู้เรียน',
                  confirmLabel: 'ยืนยันยกเลิก',
                );
                if (reason == null || !mounted) return;
                await _run(
                  () => widget.repo.cancelBookingRequest(
                    _userId!,
                    r.id,
                    reason: reason,
                  ),
                  success: 'ยกเลิกนัดแล้ว',
                );
              },
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 18,
                color: Color(0xFF2E7D32),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.requesterName ?? 'ผู้เรียน',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: NeumorphicTheme.textPrimary,
                      ),
                    ),
                    Text(
                      formatThaiSessionRange(
                        r.startsAt.toLocal(),
                        r.endsAt.toLocal(),
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: NeumorphicTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRosterSection() {
    final active = _roster
        .where((e) => e.status == CoachEnrollmentStatus.confirmed)
        .toList();
    if (active.isEmpty) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.groups_2_outlined, 'ผู้เรียนของฉัน'),
            const SizedBox(height: 8),
            Text(
              'ผู้เรียนที่ยืนยันการสมัครจะแสดงที่นี่พร้อมตารางรอบ',
              style: TextStyle(
                fontSize: 12,
                color: NeumorphicTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.groups_2_outlined,
            'ผู้เรียนของฉัน',
            badge: '${active.length}',
          ),
          const SizedBox(height: 10),
          for (final e in active) _rosterTile(e),
        ],
      ),
    );
  }

  Widget _rosterTile(CoachEnrollment e) {
    final upcoming = e.sessions
        .where(
          (s) => s.isLive && s.startsAt.isAfter(DateTime.now()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        key: ValueKey('roster_${e.id}'),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.3,
          children: [
            _slidableAction(
              label: 'ยกเลิก',
              icon: Icons.cancel_outlined,
              color: const Color(0xFFC62828),
              onTap: () => _cancelEnrollment(e),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${e.learnerName ?? 'ผู้เรียน'} — ${e.offeringTitle}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: NeumorphicTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${e.sessions.length} รอบ · ขอบเขต '
                '${e.scope == 'course' ? 'ทั้งหลักสูตร' : 'บางรอบ'}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
              if (upcoming.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final s in upcoming.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'รอบ ${s.seq} · ${formatThaiSessionRange(s.startsAt.toLocal(), s.endsAt.toLocal())}',
                            style: TextStyle(
                              fontSize: 11,
                              color: NeumorphicTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: _busy
                              ? null
                              : () => _proposeChange(e, s),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_calendar_outlined,
                                size: 13,
                                color: AppColors.primaryDark,
                              ),
                              const SizedBox(width: 3),
                              const Text(
                                'เสนอเลื่อน',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'ปัดซ้ายเพื่อยกเลิกการสมัคร',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slidableAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return CustomSlidableAction(
      onPressed: (_) => onTap(),
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _OfferingAction { edit, sessions, publish, close, cancel, minimum }

enum _SlotAction { edit, publish, cancel }
