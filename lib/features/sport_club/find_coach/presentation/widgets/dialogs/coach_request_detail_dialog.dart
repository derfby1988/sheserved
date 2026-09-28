import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../../data/coach_models.dart';
import '../coach_labels.dart';
import 'coach_enrollment_dialogs.dart';

/// Coach-side pending enrollment detail — approve performs a server-side
/// capacity recheck; reject requires a reason the learner can read.
class CoachEnrollmentDetailDialog extends StatefulWidget {
  final CoachEnrollment enrollment;

  /// 'approve' | 'reject' | null (just viewing).
  final Future<String?> Function(String decision, {String? reason})
  onDecision;

  const CoachEnrollmentDetailDialog({
    super.key,
    required this.enrollment,
    required this.onDecision,
  });

  /// Pops with 'approved' / 'rejected' after a successful decision.
  static Future<String?> show(
    BuildContext context, {
    required CoachEnrollment enrollment,
    required Future<String?> Function(String decision, {String? reason})
    onDecision,
  }) {
    return GlassDialog.show<String>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachEnrollmentDetailDialog(
        enrollment: enrollment,
        onDecision: onDecision,
      ),
    );
  }

  @override
  State<CoachEnrollmentDetailDialog> createState() =>
      _CoachEnrollmentDetailDialogState();
}

class _CoachEnrollmentDetailDialogState
    extends State<CoachEnrollmentDetailDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _decide(String decision) async {
    if (_busy) return;
    String? reason;
    if (decision == 'reject') {
      reason = await CoachReasonDialog.show(
        context,
        title: 'เหตุผลที่ปฏิเสธคำขอ',
        confirmLabel: 'ปฏิเสธคำขอ',
      );
      if (reason == null || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onDecision(decision, reason: reason);
      if (!mounted) return;
      if (result != null) {
        Navigator.of(context).pop(result);
      } else {
        setState(() {
          _busy = false;
          _error = 'ไม่สามารถดำเนินการได้ในสถานะนี้';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = CoachLabels.mapError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.enrollment;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.assignment_ind_outlined,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'คำขอสมัคร — ${e.learnerName ?? 'ผู้เรียน'}',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                            Text(
                              e.offeringTitle,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${CoachLabels.offeringType(e.offeringType)} · '
                              'ขอบเขต: ${e.scope == 'course' ? 'ทั้งหลักสูตร' : 'เลือกบางรอบ'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ยืนยันแล้ว ${e.confirmedCount} คน'
                              '${e.sessions.isNotEmpty && e.sessions.first.capacity != null ? ' / ที่นั่ง ${e.sessions.first.capacity}' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ราคา snapshot: ${CoachLabels.formatBaht(e.priceTotal)}'
                              '${e.pricingUnit != null ? ' ${CoachLabels.pricingUnit(e.pricingUnit!)}' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final s in e.sessions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: LitGlassSurface.frosted(
                          borderRadius: 12,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.event_rounded,
                                  size: 16,
                                  color: Color(0xFF475569),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'รอบ ${s.seq} · ${formatThaiSessionRange(s.startsAt.toLocal(), s.endsAt.toLocal())}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                if (s.capacity != null)
                                  Text(
                                    '${s.confirmedCount}/${s.capacity}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'คำขอ pending ยังไม่กันที่นั่ง — '
                        'เมื่ออนุมัติระบบจะตรวจความจุอีกครั้ง',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.6),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(fontSize: 12, color: Colors.red.shade300),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: 'ปฏิเสธ',
                    isFilled: true,
                    fillColor: const Color(0xFFC62828),
                    onTap: _busy ? null : () => _decide('reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GlassActionButton(
                    label: 'อนุมัติ',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: _busy ? null : () => _decide('approve'),
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
          ],
        ),
      ),
    );
  }
}

/// Coach-side 1:1 booking-request detail — same glass pattern; approve is
/// an atomic slot claim, reject needs a reason.
class CoachRequestDetailDialog extends StatefulWidget {
  final CoachBookingRequest request;
  final Future<String?> Function(String decision, {String? reason})
  onDecision;

  const CoachRequestDetailDialog({
    super.key,
    required this.request,
    required this.onDecision,
  });

  static Future<String?> show(
    BuildContext context, {
    required CoachBookingRequest request,
    required Future<String?> Function(String decision, {String? reason})
    onDecision,
  }) {
    return GlassDialog.show<String>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachRequestDetailDialog(
        request: request,
        onDecision: onDecision,
      ),
    );
  }

  @override
  State<CoachRequestDetailDialog> createState() =>
      _CoachRequestDetailDialogState();
}

class _CoachRequestDetailDialogState
    extends State<CoachRequestDetailDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _decide(String decision) async {
    if (_busy) return;
    String? reason;
    if (decision == 'reject') {
      reason = await CoachReasonDialog.show(
        context,
        title: 'เหตุผลที่ปฏิเสธคำขอนัด',
        confirmLabel: 'ปฏิเสธคำขอ',
      );
      if (reason == null || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onDecision(decision, reason: reason);
      if (!mounted) return;
      if (result != null) {
        Navigator.of(context).pop(result);
      } else {
        setState(() {
          _busy = false;
          _error = 'ไม่สามารถดำเนินการได้ในสถานะนี้';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = CoachLabels.mapError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'คำขอนัด 1:1 — ${r.requesterName ?? 'ผู้เรียน'}',
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            LitGlassSurface.frosted(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatThaiSessionRange(
                        r.startsAt.toLocal(),
                        r.endsAt.toLocal(),
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (r.teachingMode != null)
                          CoachLabels.mode(r.teachingMode!),
                        if (r.hourlyRate != null)
                          '${CoachLabels.formatBaht(r.hourlyRate)}/ชม.',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (r.message?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Text(
                        '"${r.message}"',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'คำขอ pending ไม่กัน slot — เมื่ออนุมัติรายการนี้ '
              'คำขออื่นที่ชนเวลาเดียวกันจะถูกปฏิเสธอัตโนมัติ',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
                height: 1.35,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(fontSize: 12, color: Colors.red.shade300),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: 'ปฏิเสธ',
                    isFilled: true,
                    fillColor: const Color(0xFFC62828),
                    onTap: _busy ? null : () => _decide('reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GlassActionButton(
                    label: 'อนุมัติ',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: _busy ? null : () => _decide('approve'),
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
          ],
        ),
      ),
    );
  }
}
