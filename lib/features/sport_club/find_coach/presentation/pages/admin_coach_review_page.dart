import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';

import '../../data/coach_models.dart';
import '../../data/find_coach_repository.dart';

/// Admin review panel for coach profiles: approve/suspend plus the
/// verification badge toggle. Reads via `list_coach_applications` which
/// enforces admin server-side.
class AdminCoachReviewPage extends StatefulWidget {
  final FindCoachRepository repo;

  const AdminCoachReviewPage({super.key, required this.repo});

  @override
  State<AdminCoachReviewPage> createState() => _AdminCoachReviewPageState();
}

class _AdminCoachReviewPageState extends State<AdminCoachReviewPage> {
  String _status = 'pending';
  List<CoachSummary> _coaches = [];
  bool _loading = true;

  String? get _adminId => AuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final adminId = _adminId;
    if (adminId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final coaches = await widget.repo.listCoachApplications(
        adminId,
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        _coaches = coaches;
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

  Future<void> _review(
    CoachSummary coach,
    String decision, {
    bool? verified,
  }) async {
    final adminId = _adminId;
    if (adminId == null) return;
    final reason = decision == 'approved'
        ? null
        : await _askReason('เหตุผล');
    if (decision != 'approved' && reason == null) return;
    try {
      await widget.repo.reviewCoachProfile(
        adminId,
        coach.id,
        decision,
        verified: verified,
        reason: reason,
      );
      _toast('อัปเดตโปรไฟล์โค้ชแล้ว');
      await _load();
    } catch (e) {
      _toast(e.toString().contains('NOT_ADMIN')
          ? 'เฉพาะผู้ดูแลระบบเท่านั้น'
          : 'ดำเนินการไม่สำเร็จ');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('ตรวจสอบโค้ช'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pending', label: Text('รอตรวจ')),
                ButtonSegment(value: 'approved', label: Text('อนุมัติ')),
                ButtonSegment(value: 'suspended', label: Text('ระงับ')),
              ],
              selected: {_status},
              onSelectionChanged: (sel) {
                setState(() => _status = sel.first);
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _coaches.isEmpty
                        ? ListView(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(48),
                                child: Center(
                                  child: Text(
                                    'ไม่มีโปรไฟล์ในสถานะนี้',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              for (final c in _coaches) _buildCard(c),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(CoachSummary coach) {
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
                CircleAvatar(
                  radius: 20,
                  backgroundImage: (coach.avatarUrl?.isNotEmpty == true)
                      ? NetworkImage(coach.avatarUrl!)
                      : null,
                  child: coach.avatarUrl?.isNotEmpty == true
                      ? null
                      : const Icon(Icons.person, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              coach.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (coach.isVerified) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: Colors.blue.shade700,
                            ),
                          ],
                        ],
                      ),
                      if (coach.hourlyRate != null)
                        Text(
                          '${coach.hourlyRate!.toStringAsFixed(0)} บาท/ชม. • ${coach.teachingMode.name}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (coach.bio?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  coach.bio!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (_status == 'pending') ...[
                  TextButton(
                    onPressed: () => _review(coach, 'suspended'),
                    child: const Text(
                      'ระงับ',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                    ),
                    onPressed: () => _review(coach, 'approved'),
                    child: const Text('อนุมัติ'),
                  ),
                  FilledButton.tonal(
                    onPressed: () =>
                        _review(coach, 'approved', verified: true),
                    child: const Text('อนุมัติ + ยืนยันตัวตน'),
                  ),
                ] else if (_status == 'approved') ...[
                  TextButton(
                    onPressed: () => _review(coach, 'suspended'),
                    child: const Text(
                      'ระงับ',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  if (!coach.isVerified)
                    TextButton(
                      onPressed: () =>
                          _review(coach, 'approved', verified: true),
                      child: const Text('ยืนยันตัวตน'),
                    ),
                ] else
                  TextButton(
                    onPressed: () => _review(coach, 'approved'),
                    child: const Text('ปลดระงับ'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
