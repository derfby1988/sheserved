import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';

import '../../application/coach_request_service.dart';
import '../../data/coach_models.dart';
import '../../data/find_coach_repository.dart';

/// Coach-side request queue: approve/reject pending requests and cancel
/// confirmed sessions with a reason.
class CoachRequestsQueuePage extends StatefulWidget {
  final FindCoachRepository repo;

  const CoachRequestsQueuePage({super.key, required this.repo});

  @override
  State<CoachRequestsQueuePage> createState() =>
      _CoachRequestsQueuePageState();
}

class _CoachRequestsQueuePageState extends State<CoachRequestsQueuePage> {
  List<CoachBookingRequest> _requests = [];
  bool _loading = true;
  bool _showHistory = false;

  String? get _userId => AuthService.instance.currentUser?.id;

  late final CoachRequestService _service = CoachRequestService(
    createRequest: widget.repo.createBookingRequest,
    decideRequest: widget.repo.decideBookingRequest,
    cancelRequest: widget.repo.cancelBookingRequest,
    submitReview: widget.repo.submitReview,
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
      final requests = await widget.repo.listCoachBookingRequestsForCoach(
        userId,
      );
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askReason(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(c, text);
            },
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }

  Future<void> _decide(CoachBookingRequest r, bool approve) async {
    final reason = approve ? null : await _askReason('เหตุผลที่ปฏิเสธ');
    if (!approve && reason == null) return;
    try {
      await _service.decide(
        userId: _userId,
        request: r,
        approve: approve,
        reason: reason,
      );
      _toast(approve ? 'ตอบรับนัดแล้ว' : 'ปฏิเสธคำขอแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _cancelConfirmed(CoachBookingRequest r) async {
    final reason = await _askReason('เหตุผลที่ยกเลิกนัด');
    if (reason == null) return;
    try {
      await _service.cancel(userId: _userId, request: r, reason: reason);
      _toast('ยกเลิกนัดแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
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
    final pending = _requests.where((r) => r.isPending).toList();
    final confirmed = _requests.where((r) => r.isConfirmed).toList();
    final history = _requests
        .where((r) => !r.isPending && !r.isConfirmed)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('คำขอนัด (โค้ช)'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _userId == null
          ? const Center(child: Text('กรุณาเข้าสู่ระบบ'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  _sectionHeader('รอตอบรับ (${pending.length})'),
                  if (pending.isEmpty)
                    _empty('ไม่มีคำขอรอตอบรับ')
                  else
                    for (final r in pending) _buildCard(r, actions: true),
                  _sectionHeader('ยืนยันแล้ว (${confirmed.length})'),
                  if (confirmed.isEmpty)
                    _empty('ไม่มีนัดที่ยืนยัน')
                  else
                    for (final r in confirmed)
                      _buildCard(r, cancellable: true),
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

  Widget _buildCard(
    CoachBookingRequest r, {
    bool actions = false,
    bool cancellable = false,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.requesterName ?? 'ผู้ใช้',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
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
            if (r.message?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '"${r.message}"',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            if (actions || cancellable) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (actions) ...[
                    TextButton(
                      onPressed: () => _decide(r, false),
                      child: const Text(
                        'ปฏิเสธ',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                      onPressed: () => _decide(r, true),
                      child: const Text('ตอบรับ'),
                    ),
                  ] else
                    TextButton(
                      onPressed: () => _cancelConfirmed(r),
                      child: const Text(
                        'ยกเลิกนัด',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
    ),
  );

  static Widget _statusChip(CoachRequestStatus status) {
    final (label, color) = switch (status) {
      CoachRequestStatus.pending => ('รอตอบรับ', Colors.orange),
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
    return '${start.day}/${start.month} '
        '${two(start.hour)}:${two(start.minute)}'
        '–${two(end.hour)}:${two(end.minute)}';
  }

  static String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('REQUEST_NOT_PENDING')) {
      return 'คำขอนี้ถูกจัดการไปแล้ว';
    }
    if (raw.contains('REASON_REQUIRED')) return 'กรุณาระบุเหตุผล';
    if (raw.contains('NOT_AUTHORIZED') || raw.contains('UNAUTHORIZED')) {
      return 'คุณไม่มีสิทธิ์ดำเนินการนี้';
    }
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
}
