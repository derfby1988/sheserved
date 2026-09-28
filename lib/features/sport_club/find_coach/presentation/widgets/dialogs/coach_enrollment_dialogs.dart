import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/shared/widgets/glass/glass_confirm_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../../data/coach_models.dart';
import '../coach_labels.dart';

/// Enrollment confirmation — custom-content GlassDialog.
///
/// Shows the selected offering/sessions, price snapshot, approval mode and
/// the cancellation policy the learner must accept. Returns the confirmed
/// [sessionIds] selection, or null when dismissed.
typedef CoachEnrollmentSelection = ({List<String> sessionIds});

class CoachEnrollmentConfirmDialog extends StatefulWidget {
  final CoachSummary coach;
  final CoachOffering offering;
  final List<CoachOfferingSession> selectedSessions;

  /// Whole-course enrollments show a single summary; per-session
  /// enrollments list each session.
  final bool wholeCourse;

  const CoachEnrollmentConfirmDialog({
    super.key,
    required this.coach,
    required this.offering,
    required this.selectedSessions,
    required this.wholeCourse,
  });

  /// Pops with a non-null [CoachEnrollmentSelection] when confirmed.
  static Future<CoachEnrollmentSelection?> show(
    BuildContext context, {
    required CoachSummary coach,
    required CoachOffering offering,
    required List<CoachOfferingSession> selectedSessions,
    required bool wholeCourse,
  }) {
    return GlassDialog.show<CoachEnrollmentSelection>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachEnrollmentConfirmDialog(
        coach: coach,
        offering: offering,
        selectedSessions: selectedSessions,
        wholeCourse: wholeCourse,
      ),
    );
  }

  @override
  State<CoachEnrollmentConfirmDialog> createState() =>
      _CoachEnrollmentConfirmDialogState();
}

class _CoachEnrollmentConfirmDialogState
    extends State<CoachEnrollmentConfirmDialog> {
  bool _policyAccepted = false;

  double get _totalPrice {
    final offering = widget.offering;
    if (offering.pricingUnit == CoachPricingUnit.package ||
        widget.wholeCourse) {
      return offering.price ?? 0;
    }
    return widget.selectedSessions.fold<double>(
      0,
      (sum, s) => sum + (s.price ?? offering.price ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offering = widget.offering;
    final maxHeight = MediaQuery.of(context).size.height * 0.82;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: maxHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.how_to_reg_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'ยืนยันการสมัคร',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
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
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              offering.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'โค้ช ${widget.coach.displayName} · '
                              '${CoachLabels.offeringType(offering.type)} · '
                              '${CoachLabels.mode(offering.teachingMode)}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (offering.locationLabel?.isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 4),
                              Text(
                                'สถานที่: ${offering.locationLabel} '
                                '(${offering.timezone})',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final s in widget.selectedSessions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: LitGlassSurface.frosted(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.event_rounded,
                                  size: 18,
                                  color: Color(0xFF475569),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'รอบที่ ${s.seq} · ${CoachLabels.sessionRange(s)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      Text(
                                        'เขตเวลา ${s.timezone}'
                                        '${s.locationLabel != null ? ' · ${s.locationLabel}' : ''}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (s.price != null && !widget.wholeCourse)
                                  Text(
                                    CoachLabels.formatBaht(s.price),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    LitGlassSurface.frosted(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'ราคารวม (${CoachLabels.pricingUnit(offering.pricingUnit)})',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                Text(
                                  CoachLabels.formatBaht(_totalPrice),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              offering.autoConfirm
                                  ? 'สมัครแล้วยืนยันที่นั่งทันทีเมื่อยังมีที่ว่าง'
                                  : 'ส่งคำขอแล้วรอโค้ชอนุมัติ — คำขอที่รออนุมัติยังไม่กันที่นั่ง',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'นโยบายยกเลิก (${offering.cancellationPolicyVersion}): '
                              'ยกเลิกได้ถึง ${offering.cancellationCutoffHours} ชั่วโมงก่อนรอบแรกเริ่ม '
                              '· ไม่มีการเรียกเก็บเงินหรือคืนเงินในแอป',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => setState(
                        () => _policyAccepted = !_policyAccepted,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _policyAccepted
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 22,
                            color: _policyAccepted
                                ? AppColors.primary
                                : Colors.white.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'ฉันอ่านและยอมรับนโยบายการยกเลิกของรายการนี้',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.85),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: 'ยกเลิก',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GlassActionButton(
                    label: offering.autoConfirm
                        ? 'ยืนยันการสมัคร'
                        : 'ส่งคำขอสมัคร',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: _policyAccepted
                        ? () => Navigator.of(context).pop((
                            sessionIds: widget.selectedSessions
                                .map((s) => s.id)
                                .toList(),
                          ))
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

/// Mandatory free-text reason dialog (reject / coach cancel / learner
/// cancel where a reason is required). Returns the entered reason or null.
class CoachReasonDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String confirmLabel;
  final Color accentColor;

  const CoachReasonDialog({
    super.key,
    required this.title,
    this.hint = 'ระบุเหตุผล (ผู้เรียนจะเห็นข้อความนี้)',
    this.confirmLabel = 'ยืนยัน',
    this.accentColor = const Color(0xFFC62828),
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    String hint = 'ระบุเหตุผล (ผู้เรียนจะเห็นข้อความนี้)',
    String confirmLabel = 'ยืนยัน',
    Color accentColor = const Color(0xFFC62828),
  }) {
    return GlassDialog.show<String>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      panelAccentColor: accentColor,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachReasonDialog(
        title: title,
        hint: hint,
        confirmLabel: confirmLabel,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<CoachReasonDialog> createState() => _CoachReasonDialogState();
}

class _CoachReasonDialogState extends State<CoachReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _controller.text.trim().isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            LitGlassSurface.frosted(
              borderRadius: 12,
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 300,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                  border: InputBorder.none,
                  counterStyle: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF1E293B),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: 'ยกเลิก',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassActionButton(
                    label: widget.confirmLabel,
                    isFilled: true,
                    fillColor: widget.accentColor,
                    onTap: valid
                        ? () => Navigator.of(
                            context,
                          ).pop(_controller.text.trim())
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

/// Coach-side minimum-enrollment decision: proceed (optionally reopening
/// intake until a new cutoff) or cancel the offering.
class CoachMinimumDecisionDialog extends StatefulWidget {
  final CoachOffering offering;

  const CoachMinimumDecisionDialog({super.key, required this.offering});

  /// Pops with `({'proceed': bool, 'reopenUntil': DateTime?})` or null.
  static Future<({bool proceed, DateTime? reopenUntil})?> show(
    BuildContext context, {
    required CoachOffering offering,
  }) {
    return GlassDialog.show<({bool proceed, DateTime? reopenUntil})>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachMinimumDecisionDialog(offering: offering),
    );
  }

  @override
  State<CoachMinimumDecisionDialog> createState() =>
      _CoachMinimumDecisionDialogState();
}

class _CoachMinimumDecisionDialogState
    extends State<CoachMinimumDecisionDialog> {
  bool _reopen = false;
  int _reopenHours = 12;

  @override
  Widget build(BuildContext context) {
    final offering = widget.offering;
    final first = offering.firstSessionStart;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ผู้เรียนยังไม่ถึงจำนวนขั้นต่ำ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              LitGlassSurface.frosted(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offering.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ยืนยันแล้ว ${offering.confirmedCount} / '
                        'ขั้นต่ำ ${offering.minEnrollment} คน',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (first != null)
                        Text(
                          'รอบแรกเริ่ม ${formatThaiBuddhistDateTime(first.toLocal())}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _reopen = !_reopen),
                child: Row(
                  children: [
                    Icon(
                      _reopen
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: _reopen
                          ? AppColors.primary
                          : Colors.white.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ดำเนินการต่อและเปิดรับสมัครอีกครั้ง',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_reopen) ...[
                const SizedBox(height: 8),
                Text(
                  'ปิดรับใหม่ในอีก (ชั่วโมงก่อนรอบแรก)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final h in const [6, 12, 24])
                      ChoiceChip(
                        label: Text('$h ชม.'),
                        selected: _reopenHours == h,
                        onSelected: (sel) =>
                            setState(() => _reopenHours = sel ? h : _reopenHours),
                        selectedColor: AppColors.primary.withValues(
                          alpha: 0.25,
                        ),
                        labelStyle: TextStyle(
                          color: _reopenHours == h
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GlassActionButton(
                      label: 'ยกเลิกรายการ',
                      isFilled: true,
                      fillColor: const Color(0xFFC62828),
                      onTap: () => Navigator.of(
                        context,
                      ).pop((proceed: false, reopenUntil: null)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassActionButton(
                      label: 'ดำเนินการต่อ',
                      isFilled: true,
                      fillColor: AppColors.primary,
                      onTap: () {
                        DateTime? reopen;
                        if (_reopen && first != null) {
                          reopen = first.subtract(
                            Duration(hours: _reopenHours),
                          );
                          if (reopen.isAfter(first)) reopen = first;
                        }
                        Navigator.of(context).pop((
                          proceed: true,
                          reopenUntil: reopen,
                        ));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'หากไม่ตัดสินใจ ระบบจะยกเลิกอัตโนมัติเมื่อถึงเวลาเริ่มรอบแรก '
                'และแจ้งผู้เรียน',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.55),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Learner cancel confirmation — shows the accepted policy snapshot and
/// effect before submitting. Thin wrapper over [GlassConfirmDialog].
class CoachEnrollmentCancelDialog {
  static Future<bool?> show(
    BuildContext context, {
    required CoachEnrollment enrollment,
    required Future<bool> Function() onConfirm,
  }) {
    final first = enrollment.firstLiveSessionStart;
    final cutoffPassed = !enrollment.canLearnerCancel;
    return GlassConfirmDialog.show(
      context,
      icon: Icons.cancel_outlined,
      title: cutoffPassed ? 'เลยเวลายกเลิกแล้ว' : 'ยืนยันการยกเลิก',
      accentColor: const Color(0xFFC62828),
      cancelLabel: 'กลับ',
      confirmLabel: 'ยืนยันยกเลิก',
      maxWidth: 360,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            enrollment.offeringTitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'นโยบาย ${enrollment.cancellationPolicyVersion ?? 'platform'}: '
            'ยกเลิกได้ถึง ${enrollment.cancellationCutoffHours} ชั่วโมง'
            'ก่อนรอบแรกเริ่ม'
            '${first != null ? '\nรอบแรก: ${formatThaiBuddhistDateTime(first.toLocal())}' : ''}',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.4,
            ),
          ),
          if (cutoffPassed) ...[
            const SizedBox(height: 8),
            Text(
              'ตามนโยบายที่คุณยอมรับตอนสมัคร เลยเวลายกเลิกแล้ว '
              'การยกเลิกจะยังดำเนินการแต่อาจไม่มีสิทธิ์ได้รับเงื่อนไขคืน '
              '(ไม่มีการเรียกเก็บเงินในแอป)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade200,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
      onConfirm: onConfirm,
    );
  }
}

/// Schedule-change proposal accept/decline — GlassConfirmDialog pair.
class CoachScheduleProposalDialogs {
  static Future<bool?> confirmRespond(
    BuildContext context, {
    required CoachScheduleProposal proposal,
    required DateTime oldStartsAt,
    required DateTime oldEndsAt,
    required String timezone,
    required bool accept,
    required Future<bool> Function() onConfirm,
  }) {
    return GlassConfirmDialog.show(
      context,
      icon: accept
          ? Icons.check_circle_outline_rounded
          : Icons.highlight_off_rounded,
      title: accept ? 'ยอมรับตารางใหม่' : 'ปฏิเสธตารางใหม่',
      accentColor: accept ? AppColors.primary : const Color(0xFFC62828),
      cancelLabel: 'กลับ',
      confirmLabel: accept ? 'ยอมรับ' : 'ปฏิเสธ',
      maxWidth: 360,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'เดิม: ${formatThaiSessionRange(oldStartsAt.toLocal(), oldEndsAt.toLocal())} ($timezone)',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ใหม่: ${formatThaiSessionRange(proposal.newStartsAt.toLocal(), proposal.newEndsAt.toLocal())}'
            '${proposal.newLocation != null ? ' · ${proposal.newLocation}' : ''}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (proposal.reason?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              'เหตุผล: ${proposal.reason}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
          if (!accept) ...[
            const SizedBox(height: 8),
            Text(
              'หากปฏิเสธหรือไม่ตอบ จะใช้นโยบายที่ตั้งไว้ในรายการ '
              '(อาจยกเลิก session นี้ตามนโยบาย)',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.orange.shade200,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
      onConfirm: onConfirm,
    );
  }
}
