import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:sheserved/core/utils/file_ops.dart';
import 'package:sheserved/shared/widgets/glass/glass_confirm_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';
import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';
import '../../domain/venue_local_time.dart';

/// Booker-facing detail sheet for one evidence-gated booking group.
///
/// Shows the held slots, the server-computed evidence deadline countdown,
/// per-requirement state (missing / pending / verifying / verified /
/// approved / rejected / failed), the payment destination only while the
/// group is in the payment stage, payment-claim reporting after adverse
/// outcomes, and refund-case status.
///
/// All countdowns are computed against the server clock embedded in the
/// listing response — the device clock is never trusted.
class BookingGroupSheet {
  static Future<void> show(
    BuildContext context, {
    required BookCourtRepository repo,
    required String userId,
    required VenueBookingGroup group,
    required DateTime? serverNow,

    /// When non-null the sheet offers a "เลือกเวลาใหม่" CTA on adverse
    /// terminal states. Invoked after the sheet has closed.
    Future<void> Function()? onRebook,
  }) {
    return GlassDialog.show<void>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 24,
      ),
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => _BookingGroupSheetBody(
        repo: repo,
        userId: userId,
        initialGroup: group,
        initialServerNow: serverNow,
        onRebook: onRebook,
      ),
    );
  }
}

class _BookingGroupSheetBody extends StatefulWidget {
  final BookCourtRepository repo;
  final String userId;
  final VenueBookingGroup initialGroup;
  final DateTime? initialServerNow;
  final Future<void> Function()? onRebook;

  const _BookingGroupSheetBody({
    required this.repo,
    required this.userId,
    required this.initialGroup,
    required this.initialServerNow,
    this.onRebook,
  });

  @override
  State<_BookingGroupSheetBody> createState() =>
      _BookingGroupSheetBodyState();
}

class _BookingGroupSheetBodyState extends State<_BookingGroupSheetBody> {
  late VenueBookingGroup _group = widget.initialGroup;

  /// Offset between the server clock and the device clock at fetch time.
  /// Deadlines/countdowns always derive from [serverNow], never from
  /// DateTime.now() alone.
  late Duration _clockOffset = _computeOffset(widget.initialServerNow);
  Timer? _ticker;
  bool _busy = false;
  String? _uploadingKey;
  String? _notice;
  bool _noticeIsError = false;

  static Duration _computeOffset(DateTime? serverNow) =>
      serverNow == null
          ? Duration.zero
          : serverNow.difference(DateTime.now());

  /// Best-effort server-aligned "now" for countdown display.
  DateTime get _serverNow => DateTime.now().add(_clockOffset);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final res = await widget.repo.listMyBookingGroups(widget.userId);
      if (!mounted) return;
      final fresh = res.groups
          .where((g) => g.id == _group.id)
          .cast<VenueBookingGroup?>()
          .firstOrNull;
      setState(() {
        _clockOffset = _computeOffset(res.serverNow);
        if (fresh != null) _group = fresh;
      });
    } catch (_) {}
  }

  String _money(double amount) =>
      amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2);

  String _fmtInstant(DateTime instant) =>
      VenueLocalTime.formatInstantWall(instant, _group.timezone);

  String? get _countdownLabel {
    final due = _group.evidenceDueAt;
    if (due == null || !_group.isOpen) return null;
    final remaining = due.difference(_serverNow);
    if (remaining.isNegative) return 'หมดเวลาส่งหลักฐานแล้ว';
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);
    final s = remaining.inSeconds.remainder(60);
    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return 'ส่งหลักฐานภายใน $hh:$mm:$ss — กำหนด ${_fmtInstant(due)}';
  }

  // =============== Evidence upload =====================================

  /// Pick → compress for bandwidth → grant → Node gateway (magic-byte
  /// check + EXIF/GPS strip) → submit the pre-assigned revision path
  /// through the RPC. Direct bucket writes are rejected server-side.
  Future<void> _uploadEvidence(EvidenceRequirement req) async {
    if (_busy) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _uploadingKey = req.key;
      _notice = null;
    });
    try {
      final bytes = await compressImageToBytes(
        picked,
        quality: 80,
        maxDimension: 1600,
      );
      final grant = await widget.repo.createEvidenceUploadGrant(
        userId: widget.userId,
        groupId: _group.id,
        purpose: 'evidence',
        requirementKey: req.key,
      );
      final uploaded = await widget.repo.uploadEvidenceViaGateway(
        grant: grant,
        bytes: bytes,
      );
      await widget.repo.submitGroupEvidence(
        userId: widget.userId,
        groupId: _group.id,
        items: [
          (
            requirementKey: req.key,
            storagePath: grant.path,
            mime: uploaded.mime,
            sizeBytes: uploaded.sizeBytes,
          ),
        ],
      );
      if (!mounted) return;
      setState(() {
        _notice = 'ส่ง${req.label}แล้ว';
        _noticeIsError = false;
      });
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = _mapError(e);
        _noticeIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadingKey = null;
        });
      }
    }
  }

  // =============== Group-level actions ==================================

  Future<void> _cancelGroup() async {
    if (_busy) return;
    final ok = await GlassConfirmDialog.show(
      context,
      title: 'ยกเลิกการจองกลุ่มนี้?',
      content: const Text(
        'ช่วงเวลาที่พักไว้ทั้งหมดจะถูกคืน '
        'และต้องส่งหลักฐานใหม่หากจองอีกครั้ง',
        style: TextStyle(color: Colors.white70, fontSize: 13.5),
      ),
      accentColor: Colors.red,
      confirmLabel: 'ยกเลิกการจอง',
      cancelLabel: 'เก็บไว้',
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repo.cancelBookingGroup(widget.userId, _group.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = _mapError(e);
        _noticeIsError = true;
        _busy = false;
      });
      await _reload();
    }
  }

  Future<void> _reportPaymentClaim() async {
    if (_busy) return;
    final amountController = TextEditingController(
      text: _group.totalAmount == null
          ? ''
          : _money(_group.totalAmount!),
    );
    final refController = TextEditingController();
    XFile? slipFile;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('แจ้งว่าโอนเงินแล้ว'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ถ้าคุณโอนเงินจริงแล้วแต่ระบบยังไม่ยืนยัน '
                'ให้แจ้งยอดและเลขอ้างอิง เจ้าของจะตรวจสอบยอดเข้าจริง',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'ยอดที่โอน (บาท)',
                ),
              ),
              TextField(
                controller: refController,
                decoration: const InputDecoration(
                  labelText: 'เลขอ้างอิง/เวลาโอน (ถ้ามี)',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final picked = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 2048,
                      imageQuality: 90,
                    );
                    if (picked != null) {
                      setDialogState(() => slipFile = picked);
                    }
                  },
                  icon: const Icon(Icons.attach_file_rounded, size: 16),
                  label: Text(
                    slipFile == null
                        ? 'แนบสลิป (ไม่บังคับ)'
                        : 'แนบแล้ว: ${slipFile!.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ส่งแจ้ง'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      // Optional claim slip goes through the same grant+gateway pipeline
      // as evidence — server assigns the `groups/<id>/claim/` path.
      String? evidencePath;
      final slip = slipFile;
      if (slip != null) {
        final bytes = await compressImageToBytes(
          slip,
          quality: 80,
          maxDimension: 1600,
        );
        final grant = await widget.repo.createEvidenceUploadGrant(
          userId: widget.userId,
          groupId: _group.id,
          purpose: 'claim',
        );
        await widget.repo.uploadEvidenceViaGateway(
          grant: grant,
          bytes: bytes,
        );
        evidencePath = grant.path;
      }
      await widget.repo.reportGroupPaymentClaim(
        userId: widget.userId,
        groupId: _group.id,
        reportedAmount: double.tryParse(amountController.text.trim()),
        transferReference: refController.text.trim().isEmpty
            ? null
            : refController.text.trim(),
        evidencePath: evidencePath,
      );
      if (!mounted) return;
      setState(() {
        _notice = 'ส่งแจ้งยอดโอนแล้ว เจ้าของจะตรวจสอบ';
        _noticeIsError = false;
      });
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = _mapError(e);
        _noticeIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Rebook CTA — close this sheet first so the venue detail sheet opens
  /// on the page navigator underneath, then hand control to the caller.
  Future<void> _rebook() async {
    final onRebook = widget.onRebook;
    if (onRebook == null) return;
    Navigator.of(context).pop();
    await onRebook();
  }

  String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('EVIDENCE_STAGE_NOT_OPEN')) {
      return 'ยังไม่ถึงขั้นตอนส่งหลักฐานนี้';
    }
    if (raw.contains('EVIDENCE_DEADLINE_PASSED') ||
        raw.contains('GROUP_NOT_OPEN')) {
      return 'หมดเวลาแล้ว กรุณาเริ่มจองใหม่';
    }
    if (raw.contains('INVALID_STORAGE_PATH')) {
      return 'ไฟล์ไม่ถูกต้อง กรุณาลองอัปโหลดอีกครั้ง';
    }
    if (raw.contains('CLAIM_ALREADY_OPEN')) {
      return 'มีการแจ้งยอดโอนที่รอตรวจสอบอยู่แล้ว';
    }
    if (raw.contains('GROUP_CLAIM_NOT_ALLOWED')) {
      return 'ยังแจ้งยอดโอนไม่ได้ในสถานะนี้';
    }
    if (raw.contains('TOO_MANY_HOLDS')) {
      return 'คุณมีการจองที่รอหลักฐานเกินกำหนดของสถานที่';
    }
    if (raw.contains('UNAUTHORIZED')) return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่';
  }

  // =============== Rendering ============================================

  String _statusLabel() => switch (_group.status) {
    BookingGroupStatus.pending =>
      _group.approvalMode == BookingApprovalMode.ownerApproval
          ? 'รอเจ้าของอนุมัติเบื้องต้น'
          : 'รอดำเนินการ',
    BookingGroupStatus.awaitingEvidence => 'รอหลักฐาน/ชำระเงิน',
    BookingGroupStatus.confirmed => 'ยืนยันแล้ว',
    BookingGroupStatus.partiallyCancelled => 'ยกเลิกบางช่วง',
    BookingGroupStatus.forfeited => 'หมดเวลาส่งหลักฐาน',
    BookingGroupStatus.rejected => 'ถูกปฏิเสธ',
    BookingGroupStatus.expired => 'หมดอายุ',
    BookingGroupStatus.cancelled => 'ยกเลิกแล้ว',
    BookingGroupStatus.completed => 'เสร็จสิ้น',
  };

  Color _statusColor() => switch (_group.status) {
    BookingGroupStatus.confirmed ||
    BookingGroupStatus.completed => Colors.green.shade700,
    BookingGroupStatus.awaitingEvidence => Colors.amber.shade800,
    BookingGroupStatus.pending => Colors.blueGrey.shade700,
    BookingGroupStatus.partiallyCancelled => Colors.orange.shade800,
    _ => Colors.red.shade700,
  };

  ({IconData icon, String label, Color color}) _evidenceState(
    EvidenceRequirement req,
  ) {
    final item = _group.evidenceFor(req.key);
    if (item == null) {
      return (
        icon: Icons.upload_file_rounded,
        label: 'ยังไม่ได้ส่ง',
        color: Colors.grey.shade700,
      );
    }
    return switch (item.verificationStatus) {
      GroupEvidenceVerification.pending => (
        icon: Icons.hourglass_top_rounded,
        label: 'รอตรวจสอบ',
        color: Colors.blueGrey.shade700,
      ),
      GroupEvidenceVerification.verifying => (
        icon: Icons.sync_rounded,
        label: 'ระบบกำลังตรวจสอบ',
        color: Colors.blue.shade700,
      ),
      GroupEvidenceVerification.verified => (
        icon: Icons.verified_rounded,
        label: 'ระบบยืนยันแล้ว',
        color: Colors.green.shade700,
      ),
      GroupEvidenceVerification.approved => (
        icon: Icons.check_circle_rounded,
        label: 'เจ้าของอนุมัติแล้ว',
        color: Colors.green.shade700,
      ),
      GroupEvidenceVerification.rejected => (
        icon: Icons.cancel_rounded,
        label: 'ถูกปฏิเสธ — ส่งใหม่ได้',
        color: Colors.red.shade700,
      ),
      GroupEvidenceVerification.failed => (
        icon: Icons.error_outline_rounded,
        label: 'ตรวจสอบไม่ผ่าน',
        color: Colors.red.shade700,
      ),
    };
  }

  /// The payment destination is only disclosed while the group is in the
  /// payment stage — the server already nulls it for earlier stages, this
  /// is defence-in-depth on the client.
  bool get _showPaymentDestination =>
      _group.isAwaitingEvidence &&
      _group.paymentDestination?.isNotEmpty == true;

  /// Payment claims are meaningful once money could have moved: after a
  /// failed verification, forfeit, or an adverse owner decision. The RPC
  /// rejects claims while the group is still open (pending/awaiting), so
  /// the button must mirror that gate instead of dead-ending on
  /// GROUP_CLAIM_NOT_ALLOWED.
  bool get _canReportPayment => !_group.isOpen;

  /// Adverse terminal states where the held slots were lost — the rebook
  /// CTA sends the booker back to the venue's court sheet.
  bool get _canRebook =>
      widget.onRebook != null &&
      (_group.status == BookingGroupStatus.forfeited ||
          _group.status == BookingGroupStatus.rejected ||
          _group.status == BookingGroupStatus.expired ||
          _group.status == BookingGroupStatus.cancelled);

  bool get _hasOpenClaim =>
      _group.claims.any((c) => c.status == 'submitted');

  @override
  Widget build(BuildContext context) {
    final countdown = _countdownLabel;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 440,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _group.venueName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor().withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _statusColor().withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      _statusLabel(),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _statusColor(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final child in _group.bookings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${child.unitLabel ?? 'สนาม'} ${child.courtName} — '
                    '${_fmtInstant(child.startsAt)}'
                    '${child.priceTotal != null ? ' · ${_money(child.priceTotal!)} บาท' : ''}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (_group.totalAmount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'ยอดรวม ${_money(_group.totalAmount!)} ${_group.currency}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (countdown != null) ...[
                const SizedBox(height: 10),
                LitGlassSurface.frosted(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 18,
                          color: Colors.amber.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            countdown,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_group.ownerDecisionDueAt != null && _group.isOpen) ...[
                const SizedBox(height: 6),
                Text(
                  'เจ้าของตัดสินภายใน ${_fmtInstant(_group.ownerDecisionDueAt!)}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_showPaymentDestination) ...[
                const SizedBox(height: 10),
                LitGlassSurface.frosted(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ช่องทางชำระเงิน',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          _group.paymentDestination!,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_group.requirements.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'หลักฐานที่ต้องส่ง',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final req in _group.requirements)
                  _requirementTile(req),
              ],
              if (_group.claims.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final claim in _group.claims)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'แจ้งโอน ${_money(claim.reportedAmount ?? 0)} บาท — '
                      '${switch (claim.status) {
                        'received' => 'เจ้าของยืนยันรับเงินแล้ว',
                        'not_received' => 'เจ้าของแจ้งว่ายังไม่ได้รับ',
                        _ => 'รอเจ้าของตรวจสอบ',
                      }}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
              if (_group.refundCases.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'การคืนเงิน',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                for (final rc in _group.refundCases)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'คืน ${_money(rc.refundAmount ?? rc.allocatedAmount ?? 0)} บาท — '
                      '${switch (rc.status) {
                        'open' => 'รอเจ้าของพิจารณา',
                        'approved' => 'อนุมัติแล้ว รอโอนคืน',
                        'processing' => 'กำลังโอนคืน',
                        'completed' => 'โอนคืนแล้ว${rc.externalRef?.isNotEmpty == true ? ' (${rc.externalRef})' : ''}',
                        'not_refundable' => 'ไม่คืนเงิน${rc.reason?.isNotEmpty == true ? ' — ${rc.reason}' : ''}',
                        'failed' => 'โอนคืนไม่สำเร็จ — เจ้าของจะติดต่อ',
                        _ => rc.status,
                      }}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
              if (_group.rejectionReason?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'เหตุผลที่ถูกปฏิเสธ: ${_group.rejectionReason}',
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              if (_notice != null) ...[
                const SizedBox(height: 10),
                Text(
                  _notice!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: _noticeIsError
                        ? Colors.red.shade300
                        : Colors.green.shade300,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_canRebook)
                    _pillButton(
                      label: 'เลือกเวลาใหม่',
                      icon: Icons.event_available_rounded,
                      color: Colors.green.shade300,
                      onTap: _busy ? null : _rebook,
                    ),
                  if (_canReportPayment &&
                      !_hasOpenClaim &&
                      _group.requirements.any((r) => r.isPaymentSlip))
                  _pillButton(
                    label: 'แจ้งว่าโอนเงินแล้ว',
                    icon: Icons.receipt_long_rounded,
                    onTap: _busy ? null : _reportPaymentClaim,
                  ),
                  if (_group.isOpen)
                    _pillButton(
                      label: 'ยกเลิกการจอง',
                      icon: Icons.cancel_outlined,
                      color: Colors.red.shade300,
                      onTap: _busy ? null : _cancelGroup,
                    ),
                  _pillButton(
                    label: 'รีเฟรช',
                    icon: Icons.refresh_rounded,
                    onTap: _busy ? null : _reload,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required IconData icon,
    VoidCallback? onTap,
    Color? color,
  }) {
    final effective = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: effective.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: effective.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: effective.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: effective.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requirementTile(EvidenceRequirement req) {
    final state = _evidenceState(req);
    final item = _group.evidenceFor(req.key);
    final open = _group.requirementOpen(req);
    final uploading = _uploadingKey == req.key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: LitGlassSurface.frosted(
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(state.icon, size: 20, color: state.color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${req.label}${req.required ? '' : ' (ไม่บังคับ)'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (req.note?.isNotEmpty == true)
                    Text(
                      req.note!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  Text(
                    item == null
                        ? state.label
                        : '${state.label}${item.revision > 1 ? ' · ครั้งที่ ${item.revision}' : ''}',
                    style: TextStyle(fontSize: 12, color: state.color),
                  ),
                  if (item?.duplicateFingerprint == true)
                    Text(
                      'สลิปนี้เคยถูกใช้กับการจองอื่นแล้ว',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.red.shade700,
                      ),
                    ),
                ],
              ),
            ),
            if (open)
              uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton.icon(
                      onPressed: _busy ? null : () => _uploadEvidence(req),
                      icon: const Icon(Icons.upload_rounded, size: 16),
                      label: Text(
                        item == null ? 'ส่ง' : 'ส่งใหม่',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
          ],
        ),
        ),
      ),
    );
  }
}
