import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_confirm_dialog.dart';

import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';

class AdminPlatformVenueTermsPanel extends StatefulWidget {
  final BookCourtRepository repo;
  final String? adminId;

  const AdminPlatformVenueTermsPanel({
    super.key,
    required this.repo,
    required this.adminId,
  });

  @override
  State<AdminPlatformVenueTermsPanel> createState() =>
      _AdminPlatformVenueTermsPanelState();
}

class _AdminPlatformVenueTermsPanelState
    extends State<AdminPlatformVenueTermsPanel> {
  final _termsController = TextEditingController();
  final _cutoffController = TextEditingController();
  PlatformVenueTerms? _terms;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  int? get _cutoffValue {
    final raw = _cutoffController.text.trim();
    if (raw.isEmpty) return null;
    final value = int.tryParse(raw);
    return value != null && value >= 0 ? value : null;
  }

  bool get _valid =>
      _termsController.text.trim().isNotEmpty &&
      _termsController.text.trim().length <= 10000 &&
      _termsController.text.trim() != VenueTerms.baseTermsText &&
      _cutoffValue != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _termsController.dispose();
    _cutoffController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final adminId = widget.adminId;
    if (adminId == null) {
      setState(() {
        _loading = false;
        _error = 'กรุณาเข้าสู่ระบบผู้ดูแลระบบ';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final terms = await widget.repo.getPlatformVenueTerms(adminId);
      if (!mounted) return;
      _termsController.text = terms.isConfigured ? terms.termsText : '';
      _cutoffController.text = terms.cancellationCutoffMinutes.toString();
      setState(() {
        _terms = terms;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _messageFor(error);
        _loading = false;
      });
    }
  }

  Future<void> _confirmSave() async {
    if (!_valid || _saving) return;
    final isUpdate = _terms?.isConfigured == true;
    final confirmed = await GlassConfirmDialog.show(
      context,
      icon: Icons.policy_outlined,
      title: 'ยืนยันการเปลี่ยนเงื่อนไขมาตรฐานสนาม',
      content: Text(
        isUpdate
            ? 'การบันทึกจะสร้างเวอร์ชันใหม่และมีผลกับสนามที่ใช้เงื่อนไขแพลตฟอร์ม ผู้จองจะต้องยอมรับเวอร์ชันใหม่ก่อนจองครั้งถัดไป ส่วนรายการจองเดิมจะคง snapshot เดิมไว้'
            : 'เมื่อบันทึกแล้ว เจ้าของสนามจะเลือกใช้เงื่อนไขมาตรฐานนี้ได้ และผู้จองจะเห็นข้อความกับเวลายกเลิกที่กำหนดไว้',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
      ),
      accentColor: AppColors.primary,
      cancelLabel: 'ยกเลิก',
      confirmLabel: 'ยืนยันและบันทึก',
      maxWidth: 360,
    );
    if (confirmed == true && mounted) await _save();
  }

  Future<void> _save() async {
    final adminId = widget.adminId;
    final cutoff = _cutoffValue;
    if (adminId == null || cutoff == null || !_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.repo.setPlatformVenueTerms(
        adminId: adminId,
        termsText: _termsController.text.trim(),
        cancellationCutoffMinutes: cutoff,
      );
      if (!mounted) return;
      setState(() => _terms = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'บันทึกเงื่อนไขมาตรฐานสนามเวอร์ชัน ${updated.version} แล้ว',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _messageFor(Object error) {
    final raw = error.toString();
    if (raw.contains('NOT_ADMIN')) {
      return 'บัญชีนี้ไม่มีสิทธิ์จัดการเงื่อนไขมาตรฐาน';
    }
    if (raw.contains('UNAUTHORIZED')) return 'กรุณาเข้าสู่ระบบผู้ดูแลระบบใหม่';
    if (raw.contains('INVALID_PLATFORM_TERMS')) {
      return 'กรุณากรอกเงื่อนไขจริง 1–10,000 ตัวอักษร ไม่ใช้ข้อความตัวอย่าง';
    }
    if (raw.contains('INVALID_CUTOFF')) {
      return 'กรุณาระบุเวลายกเลิกเป็นจำนวนนาทีที่ไม่ติดลบ';
    }
    if (raw.contains('PGRST202')) {
      return 'ไม่พบ RPC สำหรับเงื่อนไขมาตรฐาน กรุณาอัปเดต Supabase migrations';
    }
    return 'ดำเนินการไม่สำเร็จ: $raw';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _terms == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_terms == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'โหลดเงื่อนไขมาตรฐานไม่สำเร็จ'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
      );
    }

    final terms = _terms!;
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'เงื่อนไขมาตรฐานสนาม',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('platform-venue-terms-refresh'),
                          tooltip: 'โหลดข้อมูลล่าสุด',
                          onPressed: _loading || _saving ? null : _load,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    Text(
                      terms.isConfigured
                          ? 'เวอร์ชันปัจจุบัน ${terms.version}'
                          : 'ยังไม่ได้ตั้งค่าโดยแอดมิน — เจ้าของสนามยังเลือกใช้เงื่อนไขแพลตฟอร์มไม่ได้',
                      style: TextStyle(
                        fontSize: 12,
                        color: terms.isConfigured
                            ? Colors.grey.shade700
                            : Colors.orange.shade900,
                        fontWeight: terms.isConfigured
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ข้อความนี้จะแสดงให้ผู้จองก่อนยืนยันการจอง เมื่อสนามเลือกใช้เงื่อนไขมาตรฐานของแพลตฟอร์ม',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('platform-venue-terms-text'),
                      controller: _termsController,
                      minLines: 6,
                      maxLines: 10,
                      maxLength: 10000,
                      decoration: const InputDecoration(
                        labelText: 'ข้อความเงื่อนไขมาตรฐานสนาม',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('platform-venue-terms-cutoff'),
                      controller: _cutoffController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ยกเลิกล่วงหน้าได้ไม่เกิน (นาที)',
                        helperText:
                            'ผู้จองยกเลิกได้ฟรีจนถึงเวลานี้ก่อนเริ่มจอง',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_cutoffController.text.trim().isNotEmpty &&
                        _cutoffValue == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'กรุณากรอกจำนวนนาทีเป็นจำนวนเต็มที่ไม่ติดลบ',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('platform-venue-terms-save'),
                      onPressed: _valid && !_saving ? _confirmSave : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _saving ? 'กำลังบันทึก' : 'บันทึกเวอร์ชันใหม่',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'การแก้ไขสร้างเวอร์ชันใหม่ รายการจองเดิมเก็บข้อความและเวลายกเลิกที่ผู้จองยอมรับไว้ ส่วนการจองใหม่ของสนามที่ใช้มาตรฐานจะใช้เวอร์ชันล่าสุด',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
