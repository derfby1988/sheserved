import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/glass/glass_confirm_dialog.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/coach_models.dart';
import '../../data/find_coach_repository.dart';
import '../widgets/coach_labels.dart';
import '../widgets/dialogs/coach_review_dialogs.dart';
import '../widgets/dialogs/learner_enrollment_detail_dialog.dart';

/// Learner's enrollment hub — pending requests, upcoming sessions and
/// history across class/course offerings. Pushed from the Find Coach
/// trailing action `การสมัครของฉัน` (no new route).
class MyCoachEnrollmentsPage extends StatefulWidget {
  final FindCoachRepository repo;

  const MyCoachEnrollmentsPage({super.key, required this.repo});

  @override
  State<MyCoachEnrollmentsPage> createState() =>
      _MyCoachEnrollmentsPageState();
}

class _MyCoachEnrollmentsPageState extends State<MyCoachEnrollmentsPage> {
  bool _loading = true;
  String? _error;
  List<CoachEnrollment> _items = const [];
  List<CoachBookingRequest> _requests = const [];
  ({Set<String> bookingIds, Set<String> sessionIds}) _reviewable =
      (bookingIds: const {}, sessionIds: const {});
  List<CoachReviewCategory> _categories = const [];
  List<CoachReviewTag> _tagCatalog = const [];

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
      final results = await Future.wait<Object?>([
        widget.repo.listMyEnrollments(userId),
        widget.repo.listMyBookingRequests(userId),
        widget.repo.listMyReviewableIds(userId),
        widget.repo.listReviewCategories(),
        widget.repo.listReviewTags(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<CoachEnrollment>;
        _requests = results[1] as List<CoachBookingRequest>;
        _reviewable =
            results[2] as ({Set<String> bookingIds, Set<String> sessionIds});
        _categories = results[3] as List<CoachReviewCategory>;
        _tagCatalog = results[4] as List<CoachReviewTag>;
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

  // =============== Enrollment actions ===============

  Future<void> _openEnrollment(CoachEnrollment e) async {
    final userId = _userId;
    if (userId == null) return;
    await LearnerEnrollmentDetailDialog.show(
      context,
      enrollment: e,
      onCancel: () async {
        try {
          await widget.repo.cancelEnrollment(userId, e.id);
          return true;
        } catch (err) {
          _toast(CoachLabels.mapError(err));
          return false;
        }
      },
      onRespondProposal: (proposalId, accept) async {
        try {
          await widget.repo.respondScheduleChange(
            userId,
            proposalId,
            accept: accept,
          );
          _toast(accept ? 'ยอมรับตารางใหม่แล้ว' : 'ปฏิเสธตารางใหม่แล้ว');
        } catch (err) {
          _toast(CoachLabels.mapError(err));
        }
      },
      onReview: (session) => _writeReview(e, session),
    );
    await _load();
  }

  Future<void> _writeReview(
    CoachEnrollment enrollment,
    CoachEnrollmentSession session,
  ) async {
    final userId = _userId;
    if (userId == null) return;
    CoachReviewDraft? draft;
    while (mounted) {
      if (!mounted) return;
      draft = await CoachReviewDialog.show(
        context,
        coachName: enrollment.coachName,
        categories: _categories,
        tagCatalog: _tagCatalog,
        initial: draft,
      );
      if (draft == null) return;
      try {
        await widget.repo.submitReviewV2(
          userId: userId,
          categoryScores: draft.categoryScores,
          comment: draft.comment,
          tagIds: draft.tagIds.toList(),
          customTags: draft.customTags,
          enrollmentId: enrollment.id,
          sessionId: session.sessionId,
        );
        _toast('ส่งรีวิวแล้ว ขอบคุณ');
        return;
      } catch (e) {
        if (!mounted) return;
        _toast(CoachLabels.mapError(e));
        // Retryable errors keep the draft and reopen the composer.
        final raw = e.toString();
        if (raw.contains('ALREADY_REVIEWED') ||
            raw.contains('NOT_REVIEWABLE') ||
            raw.contains('MISSING_CATEGORY_SCORES')) {
          return;
        }
      }
    }
  }

  Future<void> _cancelBookingRequest(CoachBookingRequest r) async {
    final userId = _userId;
    if (userId == null) return;
    final confirmed = await GlassConfirmDialog.show(
      context,
      icon: Icons.cancel_outlined,
      title: 'ยกเลิกคำขอนัดนี้?',
      accentColor: const Color(0xFFC62828),
      cancelLabel: 'กลับ',
      confirmLabel: 'ยกเลิกคำขอ',
      maxWidth: 340,
      content: Text(
        'คำขอที่รอตอบยังไม่กันที่นั่ง — ยกเลิกแล้วส่งใหม่ได้ทุกเมื่อที่ยังเปิดรับ',
        style: TextStyle(
          fontSize: 12.5,
          color: Colors.white.withValues(alpha: 0.75),
          height: 1.4,
        ),
      ),
      onConfirm: () async => true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repo.cancelBookingRequest(userId, r.id);
      _toast('ยกเลิกคำขอแล้ว');
      await _load();
    } catch (e) {
      _toast(CoachLabels.mapError(e));
    }
  }

  Future<void> _reviewBookingRequest(CoachBookingRequest r) async {
    final userId = _userId;
    if (userId == null) return;
    CoachReviewDraft? draft;
    while (mounted) {
      if (!mounted) return;
      draft = await CoachReviewDialog.show(
        context,
        coachName: r.coachName ?? 'โค้ช',
        categories: _categories,
        tagCatalog: _tagCatalog,
        initial: draft,
      );
      if (draft == null) return;
      try {
        await widget.repo.submitReviewV2(
          userId: userId,
          categoryScores: draft.categoryScores,
          comment: draft.comment,
          tagIds: draft.tagIds.toList(),
          customTags: draft.customTags,
          bookingId: r.id,
        );
        _toast('ส่งรีวิวแล้ว ขอบคุณ');
        return;
      } catch (e) {
        if (!mounted) return;
        _toast(CoachLabels.mapError(e));
        final raw = e.toString();
        if (raw.contains('ALREADY_REVIEWED') ||
            raw.contains('NOT_REVIEWABLE') ||
            raw.contains('MISSING_CATEGORY_SCORES')) {
          return;
        }
      }
    }
  }

  // =============== Build ===============

  List<CoachEnrollment> get _pending =>
      _items.where((e) => e.isPending).toList();

  List<CoachEnrollment> get _upcoming => _items
      .where(
        (e) =>
            e.isConfirmed &&
            e.sessions.any(
              (s) =>
                  s.isLive && s.startsAt.isAfter(DateTime.now()),
            ),
      )
      .toList();

  List<CoachEnrollment> get _history => _items
      .where(
        (e) =>
            !e.isPending &&
            !(e.isConfirmed &&
                e.sessions.any(
                  (s) =>
                      s.isLive &&
                      s.startsAt.isAfter(DateTime.now()),
                )),
      )
      .toList();

  List<CoachBookingRequest> get _pendingRequests =>
      _requests.where((r) => r.isPending).toList();

  List<CoachBookingRequest> get _reviewableRequests => _requests
      .where(
        (r) =>
            r.isCompleted && _reviewable.bookingIds.contains(r.id),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor,
      appBar: AppBar(
        backgroundColor: NeumorphicTheme.baseColor,
        elevation: 0,
        foregroundColor: NeumorphicTheme.textPrimary,
        title: const Text(
          'การสมัครของฉัน',
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
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _section(
                    'รอโค้ชอนุมัติ',
                    _pending.length + _pendingRequests.length,
                  ),
                  if (_pending.isEmpty && _pendingRequests.isEmpty)
                    _empty('ไม่มีคำขอที่รออนุมัติ — คำขอยังไม่กันที่นั่ง')
                  else ...[
                    for (final e in _pending) _enrollmentCard(e),
                    for (final r in _pendingRequests) _requestCard(r),
                  ],
                  _section('กำลังจะเรียน', _upcoming.length),
                  if (_upcoming.isEmpty)
                    _empty('ยังไม่มีคลาสที่กำลังจะเรียน')
                  else
                    for (final e in _upcoming) _enrollmentCard(e),
                  _section(
                    'รอเขียนรีวิว',
                    _reviewableRequests.length +
                        _reviewable.sessionIds.length,
                  ),
                  if (_reviewableRequests.isEmpty &&
                      _reviewable.sessionIds.isEmpty)
                    _empty('รีวิวได้หลังเรียนจบแต่ละรอบ')
                  else
                    for (final r in _reviewableRequests)
                      _reviewCard(r),
                  _section('ประวัติ', _history.length),
                  if (_history.isEmpty)
                    _empty('ยังไม่มีประวัติ')
                  else
                    for (final e in _history) _enrollmentCard(e),
                ],
              ),
            ),
    );
  }

  Widget _section(String title, int count) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: NeumorphicTheme.textPrimary,
            ),
          ),
        ),
        if (count > 0)
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
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: NeumorphicTheme.textSecondary),
    ),
  );

  Widget _enrollmentCard(CoachEnrollment e) {
    final statusColor = CoachLabels.enrollmentStatusColor(e.status);
    final next = e.sessions
        .where((s) => s.isLive && s.startsAt.isAfter(DateTime.now()))
        .fold<DateTime?>(null, (a, s) {
          if (a == null || s.startsAt.isBefore(a)) return s.startsAt;
          return a;
        });
    final pendingProposals = e.sessions
        .where((s) => s.proposal?.needsResponse == true)
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NeumorphicContainer(
        padding: const EdgeInsets.all(14),
        borderRadius: 18,
        depth: 4,
        blur: 8,
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        child: InkWell(
          onTap: () => _openEnrollment(e),
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
                          e.offeringTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: NeumorphicTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'โค้ช ${e.coachName} · '
                          '${CoachLabels.offeringType(e.offeringType)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: NeumorphicTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      CoachLabels.enrollmentStatus(e.status),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        '${e.sessions.length} รอบ',
                        if (next != null)
                          'ถัดไป ${formatThaiBuddhistDateTime(next.toLocal())}',
                        if (e.priceTotal != null)
                          CoachLabels.formatBaht(e.priceTotal),
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: NeumorphicTheme.textSecondary,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF94A3B8),
                    size: 20,
                  ),
                ],
              ),
              if (pendingProposals > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_calendar_outlined,
                        size: 13,
                        color: Colors.orange.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'มี $pendingProposals ข้อเสนอเปลี่ยนตารางรอตอบ',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestCard(CoachBookingRequest r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NeumorphicContainer(
        padding: const EdgeInsets.all(14),
        borderRadius: 18,
        depth: 4,
        blur: 8,
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'นัด 1:1 · ${r.coachName ?? 'โค้ช'}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: NeumorphicTheme.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF6C00).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    CoachLabels.requestStatus(r.status),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEF6C00),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              formatThaiSessionRange(
                r.startsAt.toLocal(),
                r.endsAt.toLocal(),
              ),
              style: TextStyle(
                fontSize: 12,
                color: NeumorphicTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _cancelBookingRequest(r),
                icon: const Icon(Icons.cancel_outlined, size: 15),
                label: const Text(
                  'ยกเลิกคำขอ',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(CoachBookingRequest r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NeumorphicContainer(
        padding: const EdgeInsets.all(14),
        borderRadius: 18,
        depth: 4,
        blur: 8,
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        child: Row(
          children: [
            const Icon(
              Icons.rate_review_outlined,
              size: 20,
              color: AppColors.primaryDark,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'เรียนกับ ${r.coachName ?? 'โค้ช'}',
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
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
              ),
              onPressed: () => _reviewBookingRequest(r),
              child: const Text('รีวิว', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
