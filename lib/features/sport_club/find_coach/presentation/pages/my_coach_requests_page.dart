import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';

import '../../application/coach_request_service.dart';
import '../../data/coach_models.dart';
import '../../data/find_coach_repository.dart';

/// Requester-side coach request list: pending/confirmed plus history, with
/// cancel and post-completion review actions.
class MyCoachRequestsPage extends StatefulWidget {
  final FindCoachRepository repo;

  const MyCoachRequestsPage({super.key, required this.repo});

  @override
  State<MyCoachRequestsPage> createState() => _MyCoachRequestsPageState();
}

class _MyCoachRequestsPageState extends State<MyCoachRequestsPage> {
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
      final requests = await widget.repo.listMyBookingRequests(userId);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(CoachBookingRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ยกเลิกคำขอนัด'),
        content: Text('ยืนยันยกเลิกนัดกับ ${r.coachName ?? 'โค้ช'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ไม่ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('ยืนยันยกเลิก'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.cancel(userId: _userId, request: r);
      _toast('ยกเลิกคำขอแล้ว');
      await _load();
    } catch (e) {
      _toast(_mapError(e));
    }
  }

  Future<void> _writeReview(CoachBookingRequest r) async {
    int rating = 0;
    final comment = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheetState) => AlertDialog(
          title: Text('รีวิว ${r.coachName ?? 'โค้ช'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '$i ดาว',
                      icon: Icon(
                        i <= rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: AppColors.alertGold,
                      ),
                      onPressed: () => setSheetState(() => rating = i),
                    ),
                ],
              ),
              TextField(
                controller: comment,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'เล่าประสบการณ์ (ไม่บังคับ)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: rating == 0
                  ? null
                  : () => Navigator.pop(c, true),
              child: const Text('ส่งรีวิว'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) return;
    try {
      await _service.review(
        userId: _userId,
        request: r,
        rating: rating,
        comment: comment.text.trim().isEmpty ? null : comment.text.trim(),
      );
      _toast('ขอบคุณสำหรับรีวิว');
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
      appBar: AppBar(
        title: const Text('คำขอนัดโค้ชของฉัน'),
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
                    r.coachName ?? 'โค้ช',
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
            if (r.teachingMode != null || r.hourlyRate != null)
              Text(
                [
                  if (r.teachingMode != null)
                    r.teachingMode == TeachingMode.online
                        ? 'ออนไลน์'
                        : 'ออนไซต์',
                  if (r.hourlyRate != null)
                    '${r.hourlyRate!.toStringAsFixed(0)} บาท/ชม.',
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
                    FilledButton.tonalIcon(
                      onPressed: () => _writeReview(r),
                      icon: const Icon(Icons.rate_review_outlined, size: 16),
                      label: const Text('เขียนรีวิว'),
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

  static String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('SLOT_UNAVAILABLE')) {
      return 'ช่วงเวลานี้โค้ชไม่ว่างหรือถูกจองแล้ว';
    }
    if (raw.contains('REQUEST_NOT_COMPLETED')) {
      return 'รีวิวได้หลังนัดเสร็จสิ้นเท่านั้น';
    }
    if (raw.contains('ALREADY_REVIEWED')) return 'คุณรีวิวนัดนี้แล้ว';
    if (raw.contains('UNAUTHORIZED')) return 'กรุณาเข้าสู่ระบบใหม่';
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
}
