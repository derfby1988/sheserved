import 'package:flutter/material.dart';
import 'package:sheserved/config/app_config.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_text_prompt_dialog.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../../domain/venue_local_time.dart';

/// Owner/manager queue for evidence-gated booking groups (Phase 21.7.21.5).
///
/// Three sections: groups needing attention (pre-approval decisions +
/// per-evidence review), open payment claims (owner only), and active
/// refund cases (owner only). Money decisions are enforced owner-only
/// server-side; the UI surfaces `OWNER_DECISION_REQUIRED` as a toast.
class CourtOwnerEvidenceQueue extends StatefulWidget {
  final BookCourtRepository repo;
  final String userId;
  final VenueSummary venue;
  final VoidCallback? onChanged;

  const CourtOwnerEvidenceQueue({
    super.key,
    required this.repo,
    required this.userId,
    required this.venue,
    this.onChanged,
  });

  @override
  State<CourtOwnerEvidenceQueue> createState() =>
      _CourtOwnerEvidenceQueueState();
}

class _CourtOwnerEvidenceQueueState
    extends State<CourtOwnerEvidenceQueue> {
  OwnerEvidenceQueue? _queue;
  bool _loading = true;
  bool _busy = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final queue = await widget.repo.listEvidenceQueue(
        widget.userId,
        widget.venue.id,
      );
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  String _money(double amount) =>
      amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('OWNER_DECISION_REQUIRED')) {
      return 'การตัดสินเรื่องเงินทำได้เฉพาะเจ้าของสถานที่';
    }
    if (raw.contains('REASON_REQUIRED')) return 'กรุณาระบุเหตุผล';
    if (raw.contains('GROUP_NOT_OPEN') || raw.contains('GROUP_FINAL')) {
      return 'กลุ่มนี้ถูกตัดสินแล้ว กรุณารีเฟรช';
    }
    if (raw.contains('EVIDENCE_NOT_FOUND') ||
        raw.contains('EVIDENCE_NOT_REVIEWABLE')) {
      return 'หลักฐานนี้ถูกตัดสินแล้ว กรุณารีเฟรช';
    }
    if (raw.contains('REFUND_EXCEEDS_RECEIVED')) {
      return 'ยอดคืนเกินกว่ายอดที่รับจริง';
    }
    if (raw.contains('INVALID_REFUND_AMOUNT')) {
      return 'ยอดคืนไม่ถูกต้อง';
    }
    if (raw.contains('CLAIM_NOT_OPEN')) {
      return 'รายการแจ้งโอนนี้ถูกตัดสินแล้ว';
    }
    if (raw.contains('NOT_VENUE_MANAGER') || raw.contains('UNAUTHORIZED')) {
      return 'คุณไม่มีสิทธิ์จัดการสถานที่นี้';
    }
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่';
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _toast(ok);
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      _toast(_mapError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =============== Group decisions =====================================

  Future<void> _decideGroup(OwnerQueueGroup g, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await GlassTextPromptDialog.show(
        context,
        title: 'เหตุผลที่ปฏิเสธการจอง',
        hint: 'เช่น เอกสารไม่ครบ / เวลาไม่ว่าง',
      );
      if (reason == null || reason.trim().isEmpty || !mounted) return;
    }
    await _run(
      () => widget.repo.decideBookingGroup(
        userId: widget.userId,
        groupId: g.id,
        decision: approve ? 'approve' : 'reject',
        reason: reason,
      ),
      approve ? 'อนุมัติแล้ว' : 'ปฏิเสธกลุ่มแล้ว',
    );
  }

  Future<void> _decideEvidence(
    OwnerQueueGroup g,
    GroupEvidenceItem item,
    bool approve,
  ) async {
    String? reason;
    if (!approve) {
      reason = await GlassTextPromptDialog.show(
        context,
        title: 'เหตุผลที่ปฏิเสธหลักฐาน',
        hint: 'เช่น สลิปไม่ชัด / ยอดไม่ตรง',
      );
      if (reason == null || reason.trim().isEmpty || !mounted) return;
    }
    await _run(
      () => widget.repo.decideBookingGroup(
        userId: widget.userId,
        groupId: g.id,
        decision: approve ? 'approve' : 'reject',
        reason: reason,
        requirementKey: item.requirementKey,
      ),
      approve ? 'อนุมัติหลักฐานแล้ว' : 'ปฏิเสธหลักฐานแล้ว',
    );
  }

  /// Private evidence renders through the Node endpoint with a minted
  /// read token — never a public storage URL.
  Future<void> _viewEvidence(GroupEvidenceItem item) async {
    final path = item.storagePath;
    if (path == null || path.isEmpty) return;
    try {
      final token = await widget.repo.mintEvidenceReadToken(
        widget.userId,
        path,
      );
      if (!mounted || token.isEmpty) return;
      final url =
          '${AppConfig.backendApiUrl}/api/sports/evidence?token=$token';
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (c, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 240,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                errorBuilder: (c, e, s) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('เปิดรูปไม่สำเร็จ'),
                ),
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      _toast('เปิดหลักฐานไม่สำเร็จ');
    }
  }

  // =============== Payment claims ======================================

  Future<void> _decideClaim(GroupPaymentClaim claim, bool received) async {
    if (received) {
      final controller = TextEditingController(
        text: claim.reportedAmount == null
            ? ''
            : _money(claim.reportedAmount!),
      );
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ยืนยันยอดเงินที่รับจริง'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(labelText: 'ยอดที่รับ (บาท)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ยืนยัน'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final amount = double.tryParse(controller.text.trim());
      if (amount == null || amount <= 0) {
        _toast('กรุณากรอกยอดเงินที่รับจริง');
        return;
      }
      await _run(
        () => widget.repo.decidePaymentClaim(
          userId: widget.userId,
          claimId: claim.id,
          decision: 'received',
          receivedAmount: amount,
        ),
        'บันทึกยอดรับแล้ว',
      );
    } else {
      await _run(
        () => widget.repo.decidePaymentClaim(
          userId: widget.userId,
          claimId: claim.id,
          decision: 'not_received',
        ),
        'บันทึกว่ายังไม่ได้รับเงิน',
      );
    }
  }

  // =============== Refund cases ========================================

  Future<void> _actOnRefund(
    GroupRefundCase rc,
    String action,
  ) async {
    double? amount;
    String? reason;
    String? ref;
    if (action == 'approve') {
      amount = await _promptAmount(
        'อนุมัติคืนเงิน',
        rc.allocatedAmount ?? rc.refundAmount,
      );
      if (amount == null || !mounted) return;
    } else if (action == 'complete') {
      ref = await GlassTextPromptDialog.show(
        context,
        title: 'เลขอ้างอิงการโอนคืน',
        hint: 'เช่น เลขรายการโอน / เวลาโอน',
      );
      if (ref == null || ref.trim().isEmpty || !mounted) return;
    } else {
      reason = await GlassTextPromptDialog.show(
        context,
        title: action == 'fail' ? 'เหตุผลที่โอนคืนไม่สำเร็จ' : 'เหตุผลที่ไม่คืนเงิน',
        hint: 'ระบุเหตุผล',
      );
      if (reason == null || reason.trim().isEmpty || !mounted) return;
    }
    await _run(
      () => widget.repo.decideRefundCase(
        userId: widget.userId,
        caseId: rc.id,
        action: action,
        refundAmount: amount,
        reason: reason,
        externalRef: ref,
      ),
      switch (action) {
        'approve' => 'อนุมัติคืนเงินแล้ว',
        'complete' => 'บันทึกการโอนคืนแล้ว',
        'fail' => 'บันทึกว่าโอนคืนไม่สำเร็จ',
        _ => 'บันทึกว่าไม่คืนเงิน',
      },
    );
  }

  Future<double?> _promptAmount(String title, double? initial) async {
    final controller = TextEditingController(
      text: initial == null ? '' : _money(initial),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'ยอดเงิน (บาท)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return double.tryParse(controller.text.trim());
  }

  // =============== Rendering ===========================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final queue = _queue;
    if (_loadFailed || queue == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('โหลดคิวหลักฐานอีกครั้ง'),
          ),
        ),
      );
    }
    if (queue.groups.isEmpty &&
        queue.claims.isEmpty &&
        queue.refundCases.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (queue.groups.isNotEmpty) ...[
          _header('หลักฐานรอตรวจ (${queue.groups.length})'),
          for (final g in queue.groups) _groupCard(g),
        ],
        if (queue.claims.isNotEmpty) ...[
          _header('แจ้งโอนเงินรอตรวจ (${queue.claims.length})'),
          for (final claim in queue.claims) _claimCard(claim),
        ],
        if (queue.refundCases.isNotEmpty) ...[
          _header('การคืนเงิน (${queue.refundCases.length})'),
          for (final rc in queue.refundCases) _refundCard(rc),
        ],
      ],
    );
  }

  Widget _header(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: NeumorphicTheme.textPrimary,
      ),
    ),
  );

  Widget _groupCard(OwnerQueueGroup g) {
    final due = g.evidenceDueAt;
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
                  g.bookerName ?? 'ผู้จอง',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
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
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  g.isPending
                      ? 'รออนุมัติเบื้องต้น'
                      : g.isAwaitingEvidence
                      ? 'รอหลักฐาน'
                      : g.status.name,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final child in g.bookings)
            Text(
              '${child.unitLabel ?? 'สนาม'} ${child.courtName} — '
              '${VenueLocalTime.formatInstantWall(child.startsAt, g.timezone)}'
              '${child.priceTotal != null ? ' · ${_money(child.priceTotal!)}฿' : ''}',
              style: const TextStyle(
                fontSize: 12.5,
                color: NeumorphicTheme.textSecondary,
              ),
            ),
          if (g.totalAmount != null)
            Text(
              'ยอดรวม ${_money(g.totalAmount!)} บาท',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (due != null)
            Text(
              'หลักฐานภายใน ${VenueLocalTime.formatInstantWall(due, g.timezone)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          for (final item in g.evidence) _evidenceRow(g, item),
          if (g.isPending &&
              g.approvalMode == BookingApprovalMode.ownerApproval) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _decideGroup(g, false),
                    child: const Text('ปฏิเสธ'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _decideGroup(g, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: const Text('อนุมัติ'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _evidenceRow(OwnerQueueGroup g, GroupEvidenceItem item) {
    final reviewable =
        item.verificationStatus == GroupEvidenceVerification.pending ||
        item.verificationStatus == GroupEvidenceVerification.verifying;
    final label = switch (item.verificationStatus) {
      GroupEvidenceVerification.pending => 'รอตรวจ',
      GroupEvidenceVerification.verifying => 'ระบบกำลังตรวจ',
      GroupEvidenceVerification.verified => 'ระบบยืนยัน',
      GroupEvidenceVerification.approved => 'อนุมัติแล้ว',
      GroupEvidenceVerification.rejected => 'ปฏิเสธแล้ว',
      GroupEvidenceVerification.failed => 'ตรวจไม่ผ่าน',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.kind == 'payment_slip'
                      ? Icons.receipt_rounded
                      : Icons.description_outlined,
                  size: 16,
                  color: Colors.grey.shade700,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${item.requirementKey} · $label'
                    '${item.revision > 1 ? ' · ครั้งที่ ${item.revision}' : ''}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (item.storagePath?.isNotEmpty == true)
                  TextButton(
                    onPressed: () => _viewEvidence(item),
                    child: const Text('ดูไฟล์', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            if (reviewable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _decideEvidence(g, item, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Text(
                          'ปฏิเสธ',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _decideEvidence(g, item, true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          backgroundColor: AppColors.primary,
                        ),
                        child: const Text(
                          'อนุมัติ',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _claimCard(GroupPaymentClaim claim) {
    return NeumorphicContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      depth: 4,
      blur: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ผู้จองแจ้งโอน ${_money(claim.reportedAmount ?? 0)} บาท'
            '${claim.transferReference?.isNotEmpty == true ? ' — อ้างอิง ${claim.transferReference}' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _decideClaim(claim, false),
                  child: const Text('ยังไม่ได้รับ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _decideClaim(claim, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: const Text('ได้รับแล้ว'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _refundCard(GroupRefundCase rc) {
    final statusLabel = switch (rc.status) {
      'open' => 'รอพิจารณา',
      'approved' => 'อนุมัติแล้ว รอโอน',
      'processing' => 'กำลังโอน',
      _ => rc.status,
    };
    return NeumorphicContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      depth: 4,
      blur: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'คืนเงิน ${_money(rc.refundAmount ?? rc.allocatedAmount ?? 0)} บาท — $statusLabel',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          if (rc.reason?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                rc.reason!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (rc.status == 'open') ...[
                _smallAction(
                  'อนุมัติคืน',
                  () => _actOnRefund(rc, 'approve'),
                  filled: true,
                ),
                _smallAction(
                  'ไม่คืนเงิน',
                  () => _actOnRefund(rc, 'not_refundable'),
                ),
              ],
              if (rc.status == 'approved' || rc.status == 'processing') ...[
                _smallAction(
                  'บันทึกโอนคืนสำเร็จ',
                  () => _actOnRefund(rc, 'complete'),
                  filled: true,
                ),
                _smallAction(
                  'โอนไม่สำเร็จ',
                  () => _actOnRefund(rc, 'fail'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallAction(String label, VoidCallback onTap, {bool filled = false}) {
    return filled
        ? FilledButton(
            onPressed: _busy ? null : onTap,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              backgroundColor: AppColors.primary,
            ),
            child: Text(label, style: const TextStyle(fontSize: 12.5)),
          )
        : OutlinedButton(
            onPressed: _busy ? null : onTap,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)),
            child: Text(label, style: const TextStyle(fontSize: 12.5)),
          );
  }
}
