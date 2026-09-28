import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../../data/coach_models.dart';
import '../coach_labels.dart';
import 'coach_enrollment_dialogs.dart';

/// Learner-facing enrollment detail — custom-content GlassDialog.
///
/// Shows snapshot data, per-session status, open schedule-change
/// proposals with accept/decline, cancellation policy state and a review
/// CTA for completed sessions. Mutations are delegated to callbacks so
/// the page owns repository calls.
class LearnerEnrollmentDetailDialog extends StatefulWidget {
  final CoachEnrollment enrollment;

  /// Cancel the whole enrollment. Return true to close the dialog.
  final Future<bool> Function() onCancel;

  /// Respond to a schedule-change proposal (accept or decline).
  final Future<void> Function(String proposalId, bool accept)
  onRespondProposal;

  /// Open the review composer for a completed session, when eligible.
  final Future<void> Function(CoachEnrollmentSession session)? onReview;

  const LearnerEnrollmentDetailDialog({
    super.key,
    required this.enrollment,
    required this.onCancel,
    required this.onRespondProposal,
    this.onReview,
  });

  static Future<void> show(
    BuildContext context, {
    required CoachEnrollment enrollment,
    required Future<bool> Function() onCancel,
    required Future<void> Function(String proposalId, bool accept)
    onRespondProposal,
    Future<void> Function(CoachEnrollmentSession session)? onReview,
  }) {
    return GlassDialog.show<void>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => LearnerEnrollmentDetailDialog(
        enrollment: enrollment,
        onCancel: onCancel,
        onRespondProposal: onRespondProposal,
        onReview: onReview,
      ),
    );
  }

  @override
  State<LearnerEnrollmentDetailDialog> createState() =>
      _LearnerEnrollmentDetailDialogState();
}

class _LearnerEnrollmentDetailDialogState
    extends State<LearnerEnrollmentDetailDialog> {
  bool _busy = false;

  Future<void> _respond(
    CoachScheduleProposal proposal,
    CoachEnrollmentSession session,
    bool accept,
  ) async {
    if (_busy) return;
    final confirmed =
        await CoachScheduleProposalDialogs.confirmRespond(
          context,
          proposal: proposal,
          oldStartsAt: session.originalStartsAt ?? session.startsAt,
          oldEndsAt: session.originalEndsAt ?? session.endsAt,
          timezone: session.timezone,
          accept: accept,
          onConfirm: () async {
            try {
              await widget.onRespondProposal(proposal.id, accept);
              return true;
            } catch (_) {
              return false;
            }
          },
        ) ??
        false;
    if (!confirmed || !mounted) return;
    // The page reloads and may pop this dialog via Navigator.
  }

  Future<void> _cancelEnrollment() async {
    if (_busy) return;
    setState(() => _busy = true);
    final confirmed =
        await CoachEnrollmentCancelDialog.show(
          context,
          enrollment: widget.enrollment,
          onConfirm: widget.onCancel,
        ) ??
        false;
    if (!mounted) return;
    setState(() => _busy = false);
    if (confirmed) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.enrollment;
    final statusColor = CoachLabels.enrollmentStatusColor(e.status);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 440,
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'โค้ช ${e.coachName} · '
                        '${CoachLabels.offeringType(e.offeringType)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    CoachLabels.enrollmentStatus(e.status),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: statusColor == const Color(0xFFC62828)
                          ? Colors.red.shade200
                          : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LitGlassSurface.frosted(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _row(
                              'ขอบเขต',
                              e.scope == 'course'
                                  ? 'ทั้งหลักสูตร'
                                  : '${e.sessions.length} รอบที่เลือก',
                            ),
                            _row(
                              'ราคา snapshot',
                              '${CoachLabels.formatBaht(e.priceTotal)}'
                              '${e.pricingUnit != null ? ' · ${CoachLabels.pricingUnit(e.pricingUnit!)}' : ''}',
                            ),
                            _row(
                              'นโยบายยกเลิก',
                              '${e.cancellationPolicyVersion ?? 'platform'} · '
                              'ถึง ${e.cancellationCutoffHours} ชม.ก่อนรอบแรก',
                            ),
                            if (e.autoConfirm)
                              _row('โหมดอนุมัติ', 'ยืนยันอัตโนมัติ')
                            else
                              _row(
                                'โหมดอนุมัติ',
                                'รอโค้ชอนุมัติ (คำขอยังไม่กันที่นั่ง)',
                              ),
                            if (e.minEnrollment > 0 &&
                                e.isLive &&
                                e.confirmedCount < e.minEnrollment)
                              _row(
                                'จำนวนขั้นต่ำ',
                                'ยืนยัน ${e.confirmedCount}/'
                                '${e.minEnrollment} คน — รอโค้ชตัดสินใจ',
                              ),
                            if (e.rejectionReason?.isNotEmpty == true)
                              _row(
                                'เหตุผลที่ถูกปฏิเสธ',
                                e.rejectionReason!,
                                color: const Color(0xFFC62828),
                              ),
                            if (e.cancellationReason?.isNotEmpty == true)
                              _row(
                                'เหตุผลที่ยกเลิก',
                                e.cancellationReason!,
                                color: const Color(0xFFC62828),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final s in e.sessions) _sessionTile(s),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (e.isLive)
              SizedBox(
                width: double.infinity,
                child: GlassActionButton(
                  label: e.canLearnerCancel
                      ? 'ยกเลิกการสมัคร'
                      : 'ยกเลิกการสมัคร (เลย cutoff)',
                  isFilled: true,
                  fillColor: const Color(0xFFC62828),
                  onTap: _busy ? null : _cancelEnrollment,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color ?? const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionTile(CoachEnrollmentSession s) {
    final proposal = s.proposal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LitGlassSurface.frosted(
        borderRadius: 14,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'รอบที่ ${s.seq} · ${formatThaiSessionRange(s.startsAt.toLocal(), s.endsAt.toLocal())}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  _miniStatus(s.status),
                ],
              ),
              Text(
                'เขตเวลา ${s.timezone}'
                '${s.locationLabel != null ? ' · ${s.locationLabel}' : ''}'
                '${s.price != null ? ' · ${CoachLabels.formatBaht(s.price)}' : ''}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              if (s.wasRescheduled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'เลื่อนจาก ${formatThaiSessionRange(s.originalStartsAt!.toLocal(), (s.originalEndsAt ?? s.endsAt).toLocal())}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              if (proposal != null && proposal.needsResponse) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'โค้ชเสนอเวลาใหม่: ${formatThaiSessionRange(proposal.newStartsAt.toLocal(), proposal.newEndsAt.toLocal())}'
                        '${proposal.newLocation != null ? ' · ${proposal.newLocation}' : ''}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      if (proposal.reason?.isNotEmpty == true)
                        Text(
                          'เหตุผล: ${proposal.reason}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(
                                  color: Colors.red.shade300,
                                ),
                                minimumSize: const Size(0, 34),
                              ),
                              onPressed: () =>
                                  _respond(proposal, s, false),
                              child: const Text(
                                'ปฏิเสธ',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primaryDark,
                                minimumSize: const Size(0, 34),
                              ),
                              onPressed: () =>
                                  _respond(proposal, s, true),
                              child: const Text(
                                'ยอมรับเวลาใหม่',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (s.isCompleted &&
                  !s.hasReview &&
                  widget.onReview != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 34),
                    ),
                    onPressed: () => widget.onReview!(s),
                    icon: const Icon(
                      Icons.rate_review_outlined,
                      size: 15,
                    ),
                    label: const Text(
                      'เขียนรีวิวรอบนี้',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              if (s.isCompleted && s.hasReview)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'รีวิวแล้ว',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStatus(String status) {
    final (label, color) = switch (status) {
      'confirmed' => ('ยืนยัน', const Color(0xFF2E7D32)),
      'pending' => ('รออนุมัติ', const Color(0xFFEF6C00)),
      'completed' => ('จบแล้ว', const Color(0xFF1565C0)),
      'cancelled' => ('ยกเลิก', const Color(0xFFC62828)),
      _ => (status, const Color(0xFF64748B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
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
    );
  }
}
