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
/// Server-filtered groups (all / due soon / overdue / slip / document /
/// deferred) with keyset pagination, grouped by play date. Personal
/// defer snoozes a group for this manager only — deadlines and status
/// never change. Bulk actions are reject-only with a confirmation
/// summary; approve and money decisions stay per-group. Money decisions
/// are enforced owner-only server-side; the UI surfaces
/// `OWNER_DECISION_REQUIRED` as a toast.
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

/// Structured rejection codes (stored verbatim for audit) with Thai
/// labels. 'other' requires a free-text note.
const Map<String, String> kQueueReasonCodes = {
  'slip_unreadable': 'สลิปอ่านไม่ชัดเจน',
  'amount_mismatch': 'ยอดเงินไม่ตรง',
  'duplicate_slip': 'สลิปซ้ำ/ถูกใช้แล้ว',
  'wrong_destination': 'โอนผิดบัญชี/ช่องทาง',
  'doc_expired': 'เอกสารหมดอายุ',
  'doc_mismatch': 'เอกสารไม่ตรงเงื่อนไข',
  'slot_unavailable': 'ช่วงเวลาไม่ว่างแล้ว',
  'other': 'อื่น ๆ (ระบุเพิ่มเติม)',
};

class _CourtOwnerEvidenceQueueState
    extends State<CourtOwnerEvidenceQueue> {
  List<OwnerQueueGroup> _groups = const [];
  List<GroupPaymentClaim> _claims = const [];
  List<GroupRefundCase> _refundCases = const [];
  bool _hasMore = false;
  OwnerQueueCursor? _nextCursor;
  int _deferredCount = 0;

  String _filter = 'all';
  bool _loading = true;
  bool _loadingMore = false;
  bool _busy = false;
  bool _loadFailed = false;
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load({bool append = false}) async {
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _loadFailed = false;
    });
    try {
      final queue = await widget.repo.listEvidenceQueue(
        widget.userId,
        widget.venue.id,
        filter: _filter,
        cursor: append ? _nextCursor : null,
      );
      if (!mounted) return;
      setState(() {
        _groups = append ? [..._groups, ...queue.groups] : queue.groups;
        _claims = queue.claims;
        _refundCases = queue.refundCases;
        _hasMore = queue.hasMore;
        _nextCursor = queue.nextCursor;
        _deferredCount = queue.deferredCount;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _loadFailed = true;
        });
      }
    }
  }

  void _setFilter(String filter) {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _selecting = false;
      _selected.clear();
    });
    _load();
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

  // =============== Reason picker =======================================

  /// Preset reason code + optional note. The code is required; a note is
  /// mandatory for 'other'. Returns null when cancelled.
  Future<({String code, String? note})?> _promptRejectReason(
    String title,
  ) async {
    String code = kQueueReasonCodes.keys.first;
    final noteController = TextEditingController();
    final result = await showDialog<({String code, String? note})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: code,
                decoration: const InputDecoration(labelText: 'เหตุผล'),
                items: [
                  for (final entry in kQueueReasonCodes.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (v) => setSheet(() => code = v ?? code),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                decoration: InputDecoration(
                  labelText: code == 'other'
                      ? 'ระบุเหตุผล (จำเป็น)'
                      : 'รายละเอียดเพิ่มเติม (ไม่บังคับ)',
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                final note = noteController.text.trim();
                if (code == 'other' && note.isEmpty) return;
                Navigator.pop(
                  ctx,
                  (code: code, note: note.isEmpty ? null : note),
                );
              },
              child: const Text('ยืนยัน'),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
    return result;
  }

  // =============== Group decisions =====================================

  Future<void> _decideGroup(OwnerQueueGroup g, bool approve) async {
    String? reason;
    String? reasonCode;
    if (!approve) {
      final picked = await _promptRejectReason('เหตุผลที่ปฏิเสธการจอง');
      if (picked == null || !mounted) return;
      reasonCode = picked.code;
      reason = picked.note;
    }
    await _run(
      () => widget.repo.decideBookingGroup(
        userId: widget.userId,
        groupId: g.id,
        decision: approve ? 'approve' : 'reject',
        reason: reason,
        reasonCode: reasonCode,
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
    String? reasonCode;
    if (!approve) {
      final picked = await _promptRejectReason('เหตุผลที่ปฏิเสธหลักฐาน');
      if (picked == null || !mounted) return;
      reasonCode = picked.code;
      reason = picked.note;
    }
    await _run(
      () => widget.repo.decideBookingGroup(
        userId: widget.userId,
        groupId: g.id,
        decision: approve ? 'approve' : 'reject',
        reason: reason,
        reasonCode: reasonCode,
        requirementKey: item.requirementKey,
      ),
      approve ? 'อนุมัติหลักฐานแล้ว' : 'ปฏิเสธหลักฐานแล้ว',
    );
  }

  // =============== Personal defer ======================================

  Future<void> _deferGroup(OwnerQueueGroup g) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'เลื่อนออกจากคิวของฉันชั่วคราว',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('ไม่เปลี่ยนเวลาหรือสถานะการจอง'),
            ),
            for (final (mins, label) in [
              (60, '1 ชั่วโมง'),
              (240, '4 ชั่วโมง'),
              (1440, '1 วัน'),
            ])
              ListTile(
                title: Text(label),
                onTap: () => Navigator.pop(ctx, mins),
              ),
          ],
        ),
      ),
    );
    if (minutes == null || !mounted) return;
    await _run(
      () async {
        await widget.repo.deferQueueItem(
          userId: widget.userId,
          groupId: g.id,
          minutes: minutes,
        );
      },
      'เลื่อนออกจากคิวแล้ว',
    );
  }

  Future<void> _undeferGroup(OwnerQueueGroup g) async {
    await _run(
      () async {
        await widget.repo.deferQueueItem(
          userId: widget.userId,
          groupId: g.id,
        );
      },
      'คืนเข้าคิวแล้ว',
    );
  }

  // =============== Bulk reject =========================================

  void _toggleSelect(OwnerQueueGroup g, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(g.id);
      } else {
        _selected.remove(g.id);
      }
    });
  }

  Future<void> _bulkReject() async {
    final targets = _groups
        .where((g) => _selected.contains(g.id))
        .toList(growable: false);
    if (targets.isEmpty) return;
    final total = targets.fold<double>(
      0,
      (sum, g) => sum + (g.totalAmount ?? 0),
    );
    final picked = await _promptRejectReason(
      'ปฏิเสธ ${targets.length} กลุ่ม (รวม ${_money(total)} บาท)',
    );
    if (picked == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันปฏิเสธกลุ่มที่เลือก'),
        content: Text(
          'จะปฏิเสธ ${targets.length} กลุ่ม '
          '(มูลค่ารวม ${_money(total)} บาท)\n'
          'เหตุผล: ${kQueueReasonCodes[picked.code]}'
          '${picked.note != null ? '\n${picked.note}' : ''}\n\n'
          'ผู้จองแต่ละกลุ่มจะได้รับแจ้งเตือนและช่วงเวลาถูกปล่อย',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('ปฏิเสธทั้งหมด'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () async {
        final results = await widget.repo.bulkRejectBookingGroups(
          userId: widget.userId,
          venueId: widget.venue.id,
          groupIds: [for (final g in targets) g.id],
          reason: picked.note,
          reasonCode: picked.code,
        );
        final failed = results.where((r) => !r.ok).length;
        if (failed > 0 && mounted) {
          _toast('ปฏิเสธสำเร็จ ${results.length - failed} จาก '
              '${results.length} กลุ่ม — ที่เหลือถูกตัดสินไปแล้ว');
        }
      },
      'ปฏิเสธกลุ่มที่เลือกแล้ว',
    );
    if (mounted) {
      setState(() {
        _selecting = false;
        _selected.clear();
      });
    }
  }

  /// Private evidence renders through the Node endpoint with a minted
  /// read token — never a public storage URL.
  Future<void> _viewEvidence(GroupEvidenceItem item) async {
    final path = item.storagePath;
    if (path == null || path.isEmpty) return;
    await _viewEvidencePath(path);
  }

  Future<void> _viewEvidencePath(String path) async {
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
    if (_loadFailed) {
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
    if (_groups.isEmpty && _claims.isEmpty && _refundCases.isEmpty) {
      if (_deferredCount == 0 || _filter == 'deferred') {
        return const SizedBox.shrink();
      }
      // Empty current filter but deferred items exist — still show chips.
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filterBar(),
        if (_selecting) _selectionBar(),
        if (_groups.isNotEmpty)
          for (final section in _dateSections(_groups)) ...[
            _header(section.key),
            for (final g in section.value) _groupCard(g),
          ]
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'ไม่มีรายการในตัวกรองนี้',
              style: TextStyle(
                fontSize: 12.5,
                color: NeumorphicTheme.textSecondary,
              ),
            ),
          ),
        if (_hasMore)
          Center(
            child: TextButton.icon(
              onPressed: _loadingMore ? null : () => _load(append: true),
              icon: _loadingMore
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded, size: 18),
              label: const Text('โหลดเพิ่ม'),
            ),
          ),
        if (_claims.isNotEmpty) ...[
          _header('แจ้งโอนเงินรอตรวจ (${_claims.length})'),
          for (final claim in _claims) _claimCard(claim),
        ],
        if (_refundCases.isNotEmpty) ...[
          _header('การคืนเงิน (${_refundCases.length})'),
          for (final rc in _refundCases) _refundCard(rc),
        ],
      ],
    );
  }

  Widget _filterBar() {
    final filters = <(String, String)>[
      ('all', 'ทั้งหมด'),
      ('due_soon', 'ใกล้ครบกำหนด'),
      ('overdue', 'เกินกำหนด'),
      ('payment', 'สลิปชำระเงิน'),
      ('document', 'เอกสาร'),
      ('deferred', 'เลื่อนไว้${_deferredCount > 0 ? ' ($_deferredCount)' : ''}'),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (value, label) in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: _filter == value,
                onSelected: (_) => _setFilter(value),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(
                _selecting ? Icons.close_rounded : Icons.checklist_rounded,
                size: 16,
              ),
              label: Text(
                _selecting ? 'ยกเลิกเลือก' : 'เลือกหลายรายการ',
                style: const TextStyle(fontSize: 12),
              ),
              selected: _selecting,
              onSelected: (on) => setState(() {
                _selecting = on;
                if (!on) _selected.clear();
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar() {
    final targets = _groups.where((g) => _selected.contains(g.id));
    final total = targets.fold<double>(
      0,
      (sum, g) => sum + (g.totalAmount ?? 0),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'เลือก ${_selected.length} กลุ่ม · ${_money(total)} บาท',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _selected.isEmpty || _busy ? null : _bulkReject,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              backgroundColor: Colors.red.shade700,
            ),
            icon: const Icon(Icons.block_rounded, size: 16),
            label: const Text(
              'ปฏิเสธที่เลือก',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  /// Groups by play date (venue timezone) keeping the server ordering.
  List<MapEntry<String, List<OwnerQueueGroup>>> _dateSections(
    List<OwnerQueueGroup> groups,
  ) {
    final sections = <String, List<OwnerQueueGroup>>{};
    for (final g in groups) {
      final start = g.firstStartsAt;
      final key = start == null
          ? 'ยังไม่ระบุวันเล่น'
          : 'เล่นวันที่ ${VenueLocalTime.formatInstantWall(start, g.timezone).split(' ').first}';
      sections.putIfAbsent(key, () => []).add(g);
    }
    return sections.entries.toList();
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
    final open = g.isPending || g.isAwaitingEvidence;
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
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Checkbox(
                    value: _selected.contains(g.id),
                    onChanged: open
                        ? (v) => _toggleSelect(g, v ?? false)
                        : null,
                  ),
                ),
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
                      ? (g.stage == 'payment' ? 'รอสลิปชำระเงิน' : 'รอหลักฐาน')
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
          if (g.deferredUntil != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'เลื่อนไว้ถึง ${VenueLocalTime.formatInstantWall(g.deferredUntil!, g.timezone)}',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
              ),
            ),
          for (final item in g.evidence) _evidenceRow(g, item),
          if (open && !_selecting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (_filter == 'deferred')
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _undeferGroup(g),
                        icon: const Icon(Icons.undo_rounded, size: 16),
                        label: const Text(
                          'คืนเข้าคิว',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _deferGroup(g),
                        icon: const Icon(Icons.snooze_rounded, size: 16),
                        label: const Text(
                          'เลื่อนไว้ก่อน',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  if (g.isPending &&
                      g.approvalMode ==
                          BookingApprovalMode.ownerApproval) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => _decideGroup(g, false),
                        child: const Text(
                          'ปฏิเสธ',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            _busy ? null : () => _decideGroup(g, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        child: const Text(
                          'อนุมัติ',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
          if (claim.evidencePath?.isNotEmpty == true)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _viewEvidencePath(claim.evidencePath!),
                icon: const Icon(Icons.receipt_rounded, size: 16),
                label: const Text(
                  'ดูสลิปที่แนบ',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
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
