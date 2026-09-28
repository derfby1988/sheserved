import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/glass/glass_confirm_dialog.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../application/coach_request_service.dart';
import '../../data/coach_models.dart';
import '../../data/find_coach_repository.dart';
import '../widgets/coach_labels.dart';
import '../widgets/dialogs/coach_review_dialogs.dart';

/// Requester-side coach request list: pending/confirmed plus history, with
/// cancel and post-completion review actions. Reviews use the 10-point v2
/// flow (`CoachReviewDialog` + `submit_coach_review_v2`) — the legacy 1–5
/// path is never called from here.
class MyCoachRequestsPage extends StatefulWidget {
  final FindCoachRepository repo;

  const MyCoachRequestsPage({super.key, required this.repo});

  @override
  State<MyCoachRequestsPage> createState() => _MyCoachRequestsPageState();
}

class _MyCoachRequestsPageState extends State<MyCoachRequestsPage> {
  List<CoachBookingRequest> _requests = [];
  List<CoachReviewCategory> _categories = const [];
  List<CoachReviewTag> _tagCatalog = const [];
  ({Set<String> bookingIds, Set<String> sessionIds}) _reviewable =
      (bookingIds: const {}, sessionIds: const {});
  bool _loading = true;
  bool _showHistory = false;

  String? get _userId => AuthService.instance.currentUser?.id;

  late final CoachRequestService _service = CoachRequestService(
    createRequest: widget.repo.createBookingRequest,
    decideRequest: widget.repo.decideBookingRequest,
    cancelRequest: widget.repo.cancelBookingRequest,
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
      final results = await Future.wait<Object?>([
        widget.repo.listMyBookingRequests(userId),
        widget.repo.listMyReviewableIds(userId),
        widget.repo.listReviewCategories(),
        widget.repo.listReviewTags(),
      ]);
      if (!mounted) return;
      setState(() {
        _requests = results[0] as List<CoachBookingRequest>;
        _reviewable = results[1]
            as ({Set<String> bookingIds, Set<String> sessionIds});
        _categories = results[2] as List<CoachReviewCategory>;
        _tagCatalog = results[3] as List<CoachReviewTag>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(CoachBookingRequest r) async {
    final ok = await GlassConfirmDialog.show(
      context,
      icon: Icons.cancel_outlined,
      title: 'ยกเลิกคำขอนัดนี้?',
      accentColor: const Color(0xFFC62828),
      cancelLabel: 'กลับ',
      confirmLabel: 'ยกเลิกคำขอ',
      maxWidth: 340,
      content: Text(
        'ยืนยันยกเลิกนัดกับ ${r.coachName ?? 'โค้ช'}? '
        'คำขอที่รอตอบยังไม่กันที่นั่ง — ยกเลิกแล้วส่งใหม่ได้ทุกเมื่อที่ยังเปิดรับ',
        style: TextStyle(
          fontSize: 12.5,
          color: Colors.white.withValues(alpha: 0.75),
          height: 1.4,
        ),
      ),
      onConfirm: () async => true,
    );
    if (ok != true || !mounted) return;
    try {
      await _service.cancel(userId: _userId, request: r);
      _toast('ยกเลิกคำขอแล้ว');
      await _load();
    } catch (e) {
      _toast(CoachLabels.mapError(e));
    }
  }

  /// 10-point review with draft retention: a failed submit reopens the
  /// composer with the draft intact (same contract as court reviews).
  Future<void> _writeReview(CoachBookingRequest r) async {
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
        _toast('ขอบคุณสำหรับรีวิว');
        await _load();
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final active = _requests
        .where((r) => r.isPending || r.isConfirmed)
        .toList();
    final completed = _requests.where((r) => r.isCompleted).toList();
    final history = _requests
        .where(
          (r) => !r.isPending && !r.isConfirmed && !r.isCompleted,
        )
        .toList();

    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor,
      appBar: AppBar(
        backgroundColor: NeumorphicTheme.baseColor,
        elevation: 0,
        foregroundColor: NeumorphicTheme.textPrimary,
        title: const Text(
          'คำขอนัดโค้ชของฉัน',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _userId == null
          ? const Center(child: Text('กรุณาเข้าสู่ระบบ'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (active.isEmpty && completed.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'ยังไม่มีคำขอนัดโค้ช',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else ...[
                    for (final r in active) _buildCard(r),
                    if (completed.isNotEmpty) ...[
                      _sectionHeader('เสร็จสิ้น — เขียนรีวิวได้'),
                      for (final r in completed) _buildCard(r),
                    ],
                  ],
                  if (history.isNotEmpty) ...[
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
                      for (final r in history) _buildCard(r),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildCard(CoachBookingRequest r) {
    final reviewable =
        r.isCompleted && _reviewable.bookingIds.contains(r.id);
    return NeumorphicContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      depth: 4,
      blur: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.coachName ?? 'โค้ช',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: NeumorphicTheme.textPrimary,
                  ),
                ),
              ),
              _statusChip(r.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _fmtRange(r.startsAt, r.endsAt),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          if (r.teachingMode != null || r.hourlyRate != null)
            Text(
              [
                if (r.teachingMode != null)
                  r.teachingMode == TeachingMode.online
                      ? 'ออนไลน์'
                      : 'ออนไซต์',
                if (r.hourlyRate != null)
                  '${CoachLabels.formatBaht(r.hourlyRate)}/ชม.',
              ].join(' • '),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          if (r.rejectionReason?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'เหตุผลที่ถูกปฏิเสธ: ${r.rejectionReason}',
                style: const TextStyle(fontSize: 12.5, color: Colors.red),
              ),
            ),
          if (r.isPending || r.isConfirmed || r.isCompleted) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (r.isPending || r.isConfirmed)
                  TextButton.icon(
                    onPressed: () => _cancel(r),
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
                if (r.isCompleted)
                  reviewable
                      ? FilledButton.tonalIcon(
                          onPressed: () => _writeReview(r),
                          icon: const Icon(
                            Icons.rate_review_outlined,
                            size: 16,
                          ),
                          label: const Text('เขียนรีวิว'),
                        )
                      : Text(
                          'รีวิวแล้ว/ไม่ได้อยู่ในเงื่อนไขรีวิว',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade500,
                          ),
                        ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
    child: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: NeumorphicTheme.textPrimary,
      ),
    ),
  );

  static Widget _statusChip(CoachRequestStatus status) {
    final (label, color) = switch (status) {
      CoachRequestStatus.pending => ('รอโค้ชตอบรับ', Colors.orange),
      CoachRequestStatus.confirmed => ('ยืนยันแล้ว', Colors.green),
      CoachRequestStatus.cancelled => ('ยกเลิก', Colors.red),
      CoachRequestStatus.rejected => ('ปฏิเสธ', Colors.red),
      CoachRequestStatus.expired => ('หมดอายุ', Colors.grey),
      CoachRequestStatus.completed => ('เสร็จสิ้น', AppColors.primaryDark),
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

  static String _fmtRange(DateTime start, DateTime end) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${start.day}/${start.month}/${start.year + 543} '
        '${two(start.hour)}:${two(start.minute)}'
        '–${two(end.hour)}:${two(end.minute)}';
  }
}
